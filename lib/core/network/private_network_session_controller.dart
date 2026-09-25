import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';

/// Resumes an existing private-network identity without enrolling a device.
///
/// This is intentionally application-scoped: login, profile changes, and
/// Jellyfin client recreation do not own the persisted mesh identity.
class PrivateNetworkSessionController {
  PrivateNetworkSessionController(this._runtime, this._claim);

  final PrivateNetworkRuntime _runtime;
  final PrivateNetworkIdentityClaim _claim;
  final ValueNotifier<PrivateNetworkStatus?> status =
      ValueNotifier<PrivateNetworkStatus?>(null);

  StreamSubscription<PrivateNetworkStatus>? _subscription;
  var _started = false;
  var _closed = false;
  var _statusStreamFailed = false;
  var _terminal = false;
  var _revision = 0;
  var _verified = false;
  PrivateNetworkStatus? _latestStatus;
  PrivateNetworkFailure? _terminalFailure;
  final Completer<PrivateNetworkFailure?> _readiness = Completer();

  /// Shared by all clients using this profile; success still requires each
  /// request to recheck the live status before it is routed.
  Future<void> waitUntilReady() async {
    if (!_started && !_closed) unawaited(start());
    final failure = await _readiness.future;
    if (_closed) {
      throw const PrivateNetworkException(PrivateNetworkFailure.closed);
    }
    if (_terminal) {
      throw PrivateNetworkException(
          _terminalFailure ?? failure ?? PrivateNetworkFailure.operationFailed);
    }
    if (failure != null) throw PrivateNetworkException(failure);
  }

  void _settle(PrivateNetworkFailure? failure) {
    if (!_readiness.isCompleted) _readiness.complete(failure);
  }

  void _enterTerminal(PrivateNetworkFailure failure) {
    if (_terminal) return;
    _terminal = true;
    _terminalFailure = failure;
    _settle(failure);
  }

  bool _isRecoverableStatus(PrivateNetworkStatus current) =>
      current.canProxy ||
      (current.hasPersistedIdentity &&
          (current.state == PrivateNetworkState.starting ||
              (current.state == PrivateNetworkState.unavailable &&
                  (current.unavailableReason ==
                          PrivateNetworkUnavailableReason.directPathUnavailable ||
                      current.unavailableReason ==
                          PrivateNetworkUnavailableReason.transportFailure))));

  void _settleStatus(PrivateNetworkStatus current) {
    if (current.canProxy) {
      _settle(null);
    } else if (_isRecoverableStatus(current)) {
      // Native monitoring may recover these path/sample failures.
    } else {
      _enterTerminal(PrivateNetworkFailure.operationFailed);
    }
  }

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;

    bool hostAvailable;
    try {
      hostAvailable = await _runtime.confirmHostAvailable();
    } catch (error) {
      _enterTerminal(error is PrivateNetworkException
          ? error.failure
          : PrivateNetworkFailure.hostUnavailable);
      return;
    }
    if (!hostAvailable) {
      _enterTerminal(PrivateNetworkFailure.hostUnavailable);
    }
    if (!hostAvailable || _closed) return;

    try {
      _subscription = _runtime.statuses.listen(
        _acceptStatus,
        onError: (_, __) => _statusChannelFailed(),
        onDone: _statusChannelFailed,
      );
      final statusRevision = _revision;
      final current = await _runtime.status();
      if (_closed || _statusStreamFailed || _terminal) return;
      PrivateNetworkStatus? effective;
      if (statusRevision == _revision) {
        _acceptStatus(current);
        effective = current;
      } else {
        // The cached EventChannel replay may arrive before status() returns.
        effective = _latestStatus;
      }

      if (_closed || effective == null) return;
      if (!effective.hasPersistedIdentity) {
        status.value = effective;
        _enterTerminal(PrivateNetworkFailure.operationFailed);
        return;
      }
      if (effective.state == PrivateNetworkState.unavailable &&
          effective.unavailableReason !=
              PrivateNetworkUnavailableReason.directPathUnavailable &&
          effective.unavailableReason !=
              PrivateNetworkUnavailableReason.transportFailure) {
        _enterTerminal(PrivateNetworkFailure.operationFailed);
        return;
      }

      final resumeRevision = _revision;
      final resumed = await _runtime.resume(_claim);
      if (_closed || _statusStreamFailed || _terminal) return;
      if (!resumed.hasPersistedIdentity) {
        status.value = resumed;
        _enterTerminal(PrivateNetworkFailure.operationFailed);
        return;
      }
      _verified = true;
      if (!_isRecoverableStatus(resumed)) {
        status.value = resumed;
        _enterTerminal(PrivateNetworkFailure.operationFailed);
        return;
      }
      status.value =
          resumeRevision == _revision ? resumed : _latestStatus ?? resumed;
      _settleStatus(status.value!);
    } catch (error) {
      // Private networking is optional and must not block application startup.
      _enterTerminal(error is PrivateNetworkException
          ? error.failure
          : PrivateNetworkFailure.operationFailed);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _enterTerminal(PrivateNetworkFailure.closed);
    await _subscription?.cancel();
    status.dispose();
  }

  void _acceptStatus(PrivateNetworkStatus next) {
    if (_closed || _statusStreamFailed || _terminal) return;
    _revision++;
    _latestStatus = next;
    if (_verified) {
      status.value = next;
      _settleStatus(next);
    }
  }

  void _statusChannelFailed() {
    if (_closed || _statusStreamFailed || _terminal) return;
    _statusStreamFailed = true;
    _verified = false;
    _revision++;
    final unavailable = PrivateNetworkStatus(
      state: PrivateNetworkState.unavailable,
      path: PrivateNetworkPath.none,
      hasPersistedIdentity: status.value?.hasPersistedIdentity ?? false,
      unavailableReason: PrivateNetworkUnavailableReason.transportFailure,
    );
    _latestStatus = unavailable;
    status.value = unavailable;
    _enterTerminal(PrivateNetworkFailure.operationFailed);
  }
}
