import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';

const _eventChannelName = 'rodplayer/private_network_events_test';

const _eventControlChannel = MethodChannel(
  _eventChannelName,
);

const _eventChannel = EventChannel(
  _eventChannelName,
);

const _eventCodec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _eventControlChannel,
      null,
    );
  });

  test(
    'status events report direct path loss',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final listened = Completer<void>();

      messenger.setMockMethodCallHandler(
        _eventControlChannel,
        (call) async {
          if (call.method == 'listen') {
            if (!listened.isCompleted) {
              listened.complete();
            }

            return null;
          }

          if (call.method == 'cancel') {
            return null;
          }

          throw PlatformException(
            code: 'unexpected_method',
          );
        },
      );

      final runtime = MethodChannelPrivateNetworkRuntime(
        eventChannel: _eventChannel,
        platformSupported: true,
      );

      final eventsFuture = runtime.statuses.take(2).toList();

      await listened.future.timeout(
        const Duration(seconds: 2),
      );

      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
        _eventChannelName,
        _eventCodec.encodeSuccessEnvelope(
          <String, Object?>{
            'state': 'ready',
            'path': 'direct',
            'hasPersistedIdentity': true,
            'reason': 'none',
            'gatewayUrl': 'http://127.0.0.1:43127',
          },
        ),
        null,
      );

      // Simulate the native host detecting that the
      // direct path has degraded to relay.
      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
        _eventChannelName,
        _eventCodec.encodeSuccessEnvelope(
          <String, Object?>{
            'state': 'unavailable',
            'path': 'relay',
            'hasPersistedIdentity': true,
            'reason': 'direct_path_unavailable',
            'gatewayUrl': null,
          },
        ),
        null,
      );

      final events = await eventsFuture.timeout(
        const Duration(seconds: 2),
      );

      expect(events, hasLength(2));

      expect(events[0].canProxy, isTrue);
      expect(
        events[0].state,
        PrivateNetworkState.ready,
      );
      expect(
        events[0].path,
        PrivateNetworkPath.direct,
      );

      expect(events[1].canProxy, isFalse);
      expect(
        events[1].state,
        PrivateNetworkState.unavailable,
      );
      expect(
        events[1].path,
        PrivateNetworkPath.relay,
      );
      expect(
        events[1].unavailableReason,
        PrivateNetworkUnavailableReason.directPathUnavailable,
      );
    },
  );

  test(
    'malformed status event fails closed',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final listened = Completer<void>();

      messenger.setMockMethodCallHandler(
        _eventControlChannel,
        (call) async {
          if (call.method == 'listen') {
            if (!listened.isCompleted) {
              listened.complete();
            }

            return null;
          }

          if (call.method == 'cancel') {
            return null;
          }

          throw PlatformException(
            code: 'unexpected_method',
          );
        },
      );

      final runtime = MethodChannelPrivateNetworkRuntime(
        eventChannel: _eventChannel,
        platformSupported: true,
      );

      final eventFuture = runtime.statuses.first;

      final expectation = expectLater(
        eventFuture,
        throwsA(
          isA<PrivateNetworkException>().having(
            (error) => error.failure,
            'failure',
            PrivateNetworkFailure.invalidNativeResponse,
          ),
        ),
      );

      await listened.future.timeout(
        const Duration(seconds: 2),
      );

      // Native is never allowed to call a relay
      // path ready/proxyable.
      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
        _eventChannelName,
        _eventCodec.encodeSuccessEnvelope(
          <String, Object?>{
            'state': 'ready',
            'path': 'relay',
            'hasPersistedIdentity': true,
            'reason': 'none',
            'gatewayUrl': 'http://127.0.0.1:43127',
          },
        ),
        null,
      );

      await expectation;
    },
  );

  test(
    'native status event errors are sanitized',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      final listened = Completer<void>();

      messenger.setMockMethodCallHandler(
        _eventControlChannel,
        (call) async {
          if (call.method == 'listen') {
            if (!listened.isCompleted) {
              listened.complete();
            }

            return null;
          }

          if (call.method == 'cancel') {
            return null;
          }

          throw PlatformException(
            code: 'unexpected_method',
          );
        },
      );

      final runtime = MethodChannelPrivateNetworkRuntime(
        eventChannel: _eventChannel,
        platformSupported: true,
      );

      final eventFuture = runtime.statuses.first;

      // Attach the error handler before injecting the
      // native error so Dart never treats it as unhandled.
      final expectation = expectLater(
        eventFuture,
        throwsA(
          isA<PrivateNetworkException>()
              .having(
                (error) => error.failure,
                'failure',
                PrivateNetworkFailure.operationFailed,
              )
              .having(
                (error) => error.toString(),
                'sanitized diagnostics',
                isNot(
                  contains(
                    'secret native path detail',
                  ),
                ),
              ),
        ),
      );

      await listened.future.timeout(
        const Duration(seconds: 2),
      );

      // ignore: deprecated_member_use
      await messenger.handlePlatformMessage(
        _eventChannelName,
        _eventCodec.encodeErrorEnvelope(
          code: 'native_mesh_failure',
          message: 'secret native path detail',
          details: null,
        ),
        null,
      );

      await expectation;
    },
  );
}
