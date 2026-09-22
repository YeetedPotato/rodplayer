import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';

/// Resumes an existing private-network identity without enrolling a device.
///
/// This is intentionally application-scoped: login, profile changes, and
/// Jellyfin client recreation do not own the persisted mesh identity.
class PrivateNetworkSessionController {
  PrivateNetworkSessionController(this._runtime);

  final PrivateNetworkRuntime _runtime;
  final ValueNotifier<PrivateNetworkStatus?> status =
      ValueNotifier<PrivateNetworkStatus?>(null);

  StreamSubscription<PrivateNetworkStatus>? _subscription;
  var _started = false;
  var _closed = false;
  var _revision = 0;

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
      if (_closed || statusRevision != _revision) return;
      _acceptStatus(current);

      if (!current.hasPersistedIdentity ||
          current.state != PrivateNetworkState.stopped) {
        return;
      }

      final resumeRevision = _revision;
      final resumed = await _runtime.resume();
      if (_closed || resumeRevision != _revision) return;
      _acceptStatus(resumed);
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
    status.value = next;
  }
}
