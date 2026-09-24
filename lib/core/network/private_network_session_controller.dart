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
  var _revision = 0;
  var _verified = false;
  PrivateNetworkStatus? _latestStatus;

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;

    bool hostAvailable;
    try {
      hostAvailable = await _runtime.confirmHostAvailable();
    } catch (_) {
      return;
    }
    if (!hostAvailable || _closed) return;

    _subscription = _runtime.statuses.listen(
      _acceptStatus,
      onError: (_, __) {},
    );

    final statusRevision = _revision;
    try {
      final current = await _runtime.status();
      if (_closed) return;
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
        return;
      }

      final resumeRevision = _revision;
      final resumed = await _runtime.resume(_claim);
      if (_closed) return;
      if (!resumed.hasPersistedIdentity) {
        status.value = resumed;
        return;
      }
      _verified = true;
      status.value =
          resumeRevision == _revision ? resumed : _latestStatus ?? resumed;
    } catch (_) {
      // Private networking is optional and must not block application startup.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    status.dispose();
  }

  void _acceptStatus(PrivateNetworkStatus next) {
    if (_closed) return;
    _revision++;
    _latestStatus = next;
    if (_verified) status.value = next;
  }
}
