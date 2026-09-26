import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';

class MethodChannelPrivateNetworkRuntime implements PrivateNetworkRuntime {
  MethodChannelPrivateNetworkRuntime({
    MethodChannel channel = const MethodChannel('rodplayer/private_network'),
    EventChannel eventChannel =
        const EventChannel('rodplayer/private_network_events'),
    bool? platformSupported,
  })  : _channel = channel,
        _eventChannel = eventChannel,
        _platformSupported = platformSupported ?? _supportsCurrentPlatform;

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  final bool _platformSupported;

  static bool get _supportsCurrentPlatform {
    if (kIsWeb) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => true,
      TargetPlatform.android ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia =>
        false,
    };
  }

  @override
  Future<bool> confirmHostAvailable() async {
    if (!_platformSupported) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('ping') == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PrivateNetworkStatus> status() => _invokeStatus('status');

  @override
  Future<PrivateNetworkStatus> bootstrap(
    PrivateNetworkBootstrap bootstrap,
  ) =>
      _invokeStatus(
        'bootstrap',
        <String, Object?>{
          'profileId': bootstrap.profileId,
          'version': bootstrap.version,
          'controlUrl': bootstrap.controlUrl.toString(),
          'authKey': bootstrap.authKey,
          'homeIpv4': bootstrap.homeIpv4,
          'homePort': bootstrap.homePort,
        },
      );

  @override
  Future<PrivateNetworkStatus> resume(PrivateNetworkIdentityClaim claim) =>
      _invokeStatus('resume', <String, Object?>{
        'profileId': claim.profileId,
        'controlUrl': claim.controlUrl.toString(),
        'homeIpv4': claim.homeIpv4,
        'homePort': claim.homePort,
        'allowLegacyClaim': claim.allowLegacyClaim,
      });

  @override
  Future<void> stop() => _invokeVoid('stop');

  @override
  Future<void> reset() => _invokeVoid('reset');

  @override
  Stream<PrivateNetworkStatus> get statuses {
    if (!_platformSupported) {
      return const Stream<PrivateNetworkStatus>.empty();
    }

    return _statusEvents();
  }

  Stream<PrivateNetworkStatus> _statusEvents() async* {
    try {
      await for (final payload in _eventChannel.receiveBroadcastStream()) {
        yield PrivateNetworkStatus.fromPayload(payload);
      }
    } on MissingPluginException {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.hostUnavailable,
      );
    } on PlatformException {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.operationFailed,
      );
    } catch (error) {
      if (error is PrivateNetworkException) {
        rethrow;
      }

      throw const PrivateNetworkException(
        PrivateNetworkFailure.operationFailed,
      );
    }
  }

  Future<PrivateNetworkStatus> _invokeStatus(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!_platformSupported) {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.hostUnavailable,
      );
    }

    Object? payload;

    try {
      payload = await _channel.invokeMethod<Object?>(
        method,
        arguments,
      );
    } on MissingPluginException {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.hostUnavailable,
      );
    } on PlatformException {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.operationFailed,
      );
    } catch (_) {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.operationFailed,
      );
    }

    return PrivateNetworkStatus.fromPayload(payload);
  }

  Future<void> _invokeVoid(
    String method,
  ) async {
    if (!_platformSupported) {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.hostUnavailable,
      );
    }

    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.hostUnavailable,
      );
    } on PlatformException {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.operationFailed,
      );
    } catch (_) {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.operationFailed,
      );
    }
  }
}
