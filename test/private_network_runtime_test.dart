import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';

const _authKey = 'hskey-auth-ABCDEFGHIJKL-'
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '0123456789_-';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivateNetworkStatus', () {
    test(
      'accepts a ready direct loopback gateway',
      () {
        final status = PrivateNetworkStatus.fromPayload(
          <String, Object?>{
            'state': 'ready',
            'path': 'direct',
            'hasPersistedIdentity': true,
            'reason': 'none',
            'gatewayUrl': 'http://127.0.0.1:43127',
          },
        );

        expect(status.state, PrivateNetworkState.ready);
        expect(status.path, PrivateNetworkPath.direct);
        expect(status.canProxy, isTrue);
        expect(
          status.gatewayBaseUrl.toString(),
          'http://127.0.0.1:43127',
        );
      },
    );

    test(
      'rejects ready status when native reports relay',
      () {
        expect(
          () => PrivateNetworkStatus.fromPayload(
            <String, Object?>{
              'state': 'ready',
              'path': 'relay',
              'hasPersistedIdentity': true,
              'reason': 'none',
              'gatewayUrl': 'http://127.0.0.1:43127',
            },
          ),
          throwsA(
            isA<PrivateNetworkException>().having(
              (error) => error.failure,
              'failure',
              PrivateNetworkFailure.invalidNativeResponse,
            ),
          ),
        );
      },
    );

    test(
      'rejects non-loopback gateway',
      () {
        expect(
          () => PrivateNetworkStatus.fromPayload(
            <String, Object?>{
              'state': 'ready',
              'path': 'direct',
              'hasPersistedIdentity': true,
              'reason': 'none',
              'gatewayUrl': 'http://100.64.0.1:3000',
            },
          ),
          throwsA(
            isA<PrivateNetworkException>().having(
              (error) => error.failure,
              'failure',
              PrivateNetworkFailure.invalidNativeResponse,
            ),
          ),
        );
      },
    );

    test(
      'rejects unavailable status without a reason',
      () {
        expect(
          () => PrivateNetworkStatus.fromPayload(
            <String, Object?>{
              'state': 'unavailable',
              'path': 'none',
              'hasPersistedIdentity': true,
              'reason': 'none',
              'gatewayUrl': null,
            },
          ),
          throwsA(
            isA<PrivateNetworkException>().having(
              (error) => error.failure,
              'failure',
              PrivateNetworkFailure.invalidNativeResponse,
            ),
          ),
        );
      },
    );

    test(
      'unavailable relay state is not proxyable',
      () {
        final status = PrivateNetworkStatus.fromPayload(
          <String, Object?>{
            'state': 'unavailable',
            'path': 'relay',
            'hasPersistedIdentity': true,
            'reason': 'direct_path_unavailable',
            'gatewayUrl': null,
          },
        );

        expect(status.canProxy, isFalse);
        expect(
          status.unavailableReason,
          PrivateNetworkUnavailableReason.directPathUnavailable,
        );
      },
    );
  });

  group('PrivateNetworkBootstrap', () {
    test(
      'redacts Headscale auth key from diagnostics',
      () {
        final enrollment = FamilyEnrollmentResult(
          version: 1,
          controlUrl: Uri.parse(
            'https://mesh.rodserver.top',
          ),
          authKey: _authKey,
          authKeyLifetime: const Duration(minutes: 10),
          homeIpv4: '100.64.0.1',
          homePort: 3000,
        );

        final bootstrap = PrivateNetworkBootstrap.fromEnrollment(
          enrollment,
        );

        expect(bootstrap.authKey, _authKey);
        expect(
          bootstrap.toString(),
          isNot(contains(_authKey)),
        );
        expect(
          bootstrap.toString(),
          contains('<redacted>'),
        );
      },
    );
  });

  group('MethodChannelPrivateNetworkRuntime', () {
    const channel = MethodChannel(
      'rodplayer/private_network_test',
    );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        null,
      );
    });

    test(
      'bootstrap sends enrollment material only to native host',
      () async {
        MethodCall? captured;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (call) async {
            captured = call;

            return <String, Object?>{
              'state': 'ready',
              'path': 'direct',
              'hasPersistedIdentity': true,
              'reason': 'none',
              'gatewayUrl': 'http://127.0.0.1:43127',
            };
          },
        );

        final runtime = MethodChannelPrivateNetworkRuntime(
          channel: channel,
          platformSupported: true,
        );

        final status = await runtime.bootstrap(
          PrivateNetworkBootstrap(
            version: 1,
            controlUrl: Uri.parse(
              'https://mesh.rodserver.top',
            ),
            authKey: _authKey,
            homeIpv4: '100.64.0.1',
            homePort: 3000,
          ),
        );

        expect(captured?.method, 'bootstrap');

        final arguments = Map<String, Object?>.from(
          captured?.arguments as Map,
        );

        expect(
          arguments,
          <String, Object?>{
            'version': 1,
            'controlUrl': 'https://mesh.rodserver.top',
            'authKey': _authKey,
            'homeIpv4': '100.64.0.1',
            'homePort': 3000,
          },
        );

        expect(status.canProxy, isTrue);
      },
    );

    test(
      'native PlatformException is sanitized',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (_) async {
            throw PlatformException(
              code: 'native_failure',
              message: 'secret native detail',
            );
          },
        );

        final runtime = MethodChannelPrivateNetworkRuntime(
          channel: channel,
          platformSupported: true,
        );

        try {
          await runtime.resume();
          fail('expected private-network failure');
        } on PrivateNetworkException catch (error) {
          expect(
            error.failure,
            PrivateNetworkFailure.operationFailed,
          );
          expect(
            error.toString(),
            isNot(
              contains('secret native detail'),
            ),
          );
        }
      },
    );

    test(
      'unsupported platform does not invoke native host',
      () async {
        var called = false;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          channel,
          (_) async {
            called = true;
            return true;
          },
        );

        final runtime = MethodChannelPrivateNetworkRuntime(
          channel: channel,
          platformSupported: false,
        );

        expect(
          await runtime.confirmHostAvailable(),
          isFalse,
        );
        expect(called, isFalse);
      },
    );
  });
}
