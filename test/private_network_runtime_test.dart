import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:rodplayer/platform/network/method_channel_private_network_runtime.dart';

const _authKey = 'hskey-auth-ABCDEFGHIJKL-'
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '0123456789_-';

final _claim = PrivateNetworkIdentityClaim(
  profileId: 'invite:one',
  controlUrl: Uri.parse('https://mesh.rodserver.top'),
  homeIpv4: '100.64.0.1',
  homePort: 3000,
);

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

    test('constructed status needs identity, no error, and loopback', () {
      final gateway = Uri.parse('http://127.0.0.1:43127');
      expect(
        PrivateNetworkStatus(
          state: PrivateNetworkState.ready,
          path: PrivateNetworkPath.direct,
          hasPersistedIdentity: false,
          unavailableReason: PrivateNetworkUnavailableReason.none,
          gatewayBaseUrl: gateway,
        ).canProxy,
        isFalse,
      );
      expect(
        PrivateNetworkStatus(
          state: PrivateNetworkState.ready,
          path: PrivateNetworkPath.direct,
          hasPersistedIdentity: true,
          unavailableReason: PrivateNetworkUnavailableReason.transportFailure,
          gatewayBaseUrl: gateway,
        ).canProxy,
        isFalse,
      );
      expect(
        PrivateNetworkStatus(
          state: PrivateNetworkState.ready,
          path: PrivateNetworkPath.direct,
          hasPersistedIdentity: true,
          unavailableReason: PrivateNetworkUnavailableReason.none,
          gatewayBaseUrl: Uri.parse('http://100.64.0.1:3000'),
        ).canProxy,
        isFalse,
      );
    });

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

    test('rejects malformed or non-exact loopback gateways', () {
      const invalidGateways = <String>[
        'https://127.0.0.1:43127',
        'http://localhost:43127',
        'http://0.0.0.0:43127',
        'http://100.64.0.1:43127',
        'http://[::1]:43127',
        'http://127.0.0.1',
        'http://127.0.0.1:0',
        'http://127.0.0.1:65536',
        'http://user@127.0.0.1:43127',
        'http://127.0.0.1:43127?token=secret',
        'http://127.0.0.1:43127#fragment',
        'http://127.0.0.1:43127/jellyfin',
        'not a uri',
      ];

      for (final gateway in invalidGateways) {
        expect(
          () => PrivateNetworkStatus.fromPayload(
            <String, Object?>{
              'state': 'ready',
              'path': 'direct',
              'hasPersistedIdentity': true,
              'reason': 'none',
              'gatewayUrl': gateway,
            },
          ),
          throwsA(
            isA<PrivateNetworkException>().having(
              (error) => error.failure,
              'failure',
              PrivateNetworkFailure.invalidNativeResponse,
            ),
          ),
          reason: gateway,
        );
      }
    });

    test('rejects invalid ready and non-ready gateway combinations', () {
      const validGateway = 'http://127.0.0.1:43127';
      final invalidPayloads = <Map<String, Object?>>[
        <String, Object?>{
          'state': 'ready',
          'path': 'none',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': validGateway,
        },
        <String, Object?>{
          'state': 'ready',
          'path': 'direct',
          'hasPersistedIdentity': false,
          'reason': 'none',
          'gatewayUrl': validGateway,
        },
        <String, Object?>{
          'state': 'ready',
          'path': 'direct',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': null,
        },
        <String, Object?>{
          'state': 'starting',
          'path': 'direct',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': validGateway,
        },
      ];

      for (final payload in invalidPayloads) {
        expect(
          () => PrivateNetworkStatus.fromPayload(payload),
          throwsA(isA<PrivateNetworkException>()),
        );
      }
    });

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

    test(
      'direct monitoring state is not proxyable before a gateway exists',
      () {
        final status = PrivateNetworkStatus.fromPayload(
          <String, Object?>{
            'state': 'starting',
            'path': 'direct',
            'hasPersistedIdentity': true,
            'reason': 'none',
            'gatewayUrl': null,
          },
        );

        expect(status.path, PrivateNetworkPath.direct);
        expect(status.canProxy, isFalse);
        expect(status.gatewayBaseUrl, isNull);
      },
    );

    test('failed verification and lost direct path revoke gateway access', () {
      final transitions = <Map<String, Object?>>[
        {
          'state': 'starting',
          'path': 'none',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': null,
        },
        {
          'state': 'starting',
          'path': 'direct',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': null,
        },
        {
          'state': 'ready',
          'path': 'direct',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': 'http://127.0.0.1:43127',
        },
        {
          'state': 'unavailable',
          'path': 'none',
          'hasPersistedIdentity': true,
          'reason': 'direct_path_unavailable',
          'gatewayUrl': null,
        },
        {
          'state': 'starting',
          'path': 'direct',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': null,
        },
      ];
      final proxyable = transitions
          .map(PrivateNetworkStatus.fromPayload)
          .map((status) => status.canProxy)
          .toList();
      expect(proxyable, [false, false, true, false, false]);
    });

    test(
      'direct path unavailable state is not proxyable',
      () {
        final status = PrivateNetworkStatus.fromPayload(
          <String, Object?>{
            'state': 'unavailable',
            'path': 'none',
            'hasPersistedIdentity': true,
            'reason': 'direct_path_unavailable',
            'gatewayUrl': null,
          },
        );

        expect(
          status.unavailableReason,
          PrivateNetworkUnavailableReason.directPathUnavailable,
        );
        expect(status.canProxy, isFalse);
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
          profileId: 'invite:one',
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

    test('default private-network support is Apple-only', () async {
      final cases = <TargetPlatform, bool>{
        TargetPlatform.iOS: true,
        TargetPlatform.macOS: true,
        TargetPlatform.windows: false,
        TargetPlatform.android: false,
      };

      try {
        for (final entry in cases.entries) {
          debugDefaultTargetPlatformOverride = entry.key;
          var nativeCalls = 0;

          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
            channel,
            (_) async {
              nativeCalls++;
              return true;
            },
          );

          final runtime = MethodChannelPrivateNetworkRuntime(
            channel: channel,
          );

          expect(
            await runtime.confirmHostAvailable(),
            entry.value,
            reason: '${entry.key}',
          );

          expect(
            nativeCalls,
            entry.value ? 1 : 0,
            reason: '${entry.key}',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('resume sends explicit owner and exact retained configuration',
        () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return <String, Object?>{
          'state': 'starting',
          'path': 'none',
          'hasPersistedIdentity': true,
          'reason': 'none',
          'gatewayUrl': null,
        };
      });
      final runtime = MethodChannelPrivateNetworkRuntime(
          channel: channel, platformSupported: true);
      final status = await runtime.resume(PrivateNetworkIdentityClaim(
        profileId: _claim.profileId,
        controlUrl: _claim.controlUrl,
        homeIpv4: _claim.homeIpv4,
        homePort: _claim.homePort,
        allowLegacyClaim: true,
      ));
      expect(captured?.method, 'resume');
      expect(Map<String, Object?>.from(captured?.arguments as Map), {
        'profileId': 'invite:one',
        'controlUrl': 'https://mesh.rodserver.top',
        'homeIpv4': '100.64.0.1',
        'homePort': 3000,
        'allowLegacyClaim': true,
      });
      expect(status.canProxy, isFalse);
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
            profileId: 'invite:one',
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
            'profileId': 'invite:one',
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
          await runtime.resume(_claim);
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
