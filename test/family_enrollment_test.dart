import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/network/family_enrollment.dart';

const _authKey = 'hskey-auth-ABCDEFGHIJKL-'
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '0123456789_-';

void main() {
  test(
    'posts setup code and parses enrollment response',
    () async {
      late http.Request captured;

      final client = FamilyEnrollmentClient(
        client: MockClient((request) async {
          captured = request;

          return http.Response(
            jsonEncode(
              <String, Object?>{
                'version': 1,
                'control_url': 'https://mesh.rodserver.top',
                'auth_key': _authKey,
                'auth_key_expires_in_seconds': 600,
                'home': <String, Object?>{
                  'ipv4': '100.64.0.1',
                  'port': 3000,
                },
              },
            ),
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }),
      );

      final result = await client.enroll(
        'ABCD-EFGH-JKLM-NPQR-STUV',
      );

      expect(
        captured.url.toString(),
        'https://stream.rodserver.top/v1/enroll',
      );
      expect(captured.method, 'POST');

      expect(
        jsonDecode(captured.body),
        <String, Object?>{
          'code': 'ABCD-EFGH-JKLM-NPQR-STUV',
        },
      );

      expect(result.version, 1);
      expect(
        result.controlUrl.toString(),
        'https://mesh.rodserver.top',
      );
      expect(result.authKey, _authKey);
      expect(
        result.authKeyLifetime,
        const Duration(minutes: 10),
      );
      expect(result.homeIpv4, '100.64.0.1');
      expect(result.homePort, 3000);
      expect(
        result.homeBaseUrl.toString(),
        'http://100.64.0.1:3000',
      );

      expect(
        result.toString(),
        isNot(contains(_authKey)),
      );
      expect(
        result.toString(),
        contains('<redacted>'),
      );
    },
  );

  test(
    'empty setup code is rejected without network request',
    () async {
      var requests = 0;

      final client = FamilyEnrollmentClient(
        client: MockClient((request) async {
          requests++;

          return http.Response('{}', 200);
        }),
      );

      await expectLater(
        client.enroll('   '),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.invalidSetupCode,
          ),
        ),
      );

      expect(requests, 0);
    },
  );

  test(
    'HTTP 400 maps to invalid setup code',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"invalid_setup_code"}',
            400,
          ),
        ),
      );

      await expectLater(
        client.enroll('BAD-CODE'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.invalidSetupCode,
          ),
        ),
      );
    },
  );

  test(
    'HTTP 429 maps to rate limited with Retry-After',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"rate_limited"}',
            429,
            headers: const <String, String>{
              'retry-after': '600',
            },
          ),
        ),
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>()
              .having(
                (error) => error.failure,
                'failure',
                FamilyEnrollmentFailure.rateLimited,
              )
              .having(
                (error) => error.retryAfter,
                'retryAfter',
                const Duration(minutes: 10),
              ),
        ),
      );
    },
  );

  test(
    'HTTP 403 maps to rate limited',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            '{}',
            403,
          ),
        ),
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.rateLimited,
          ),
        ),
      );
    },
  );
  test(
    'server failures map to unavailable',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            '{"error":"enrollment_unavailable"}',
            503,
          ),
        ),
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.unavailable,
          ),
        ),
      );
    },
  );

  test(
    'transport failures map to unavailable without leaking details',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient((_) async {
          throw http.ClientException(
            'secret transport detail',
          );
        }),
      );

      try {
        await client.enroll(
          'ABCD-EFGH-JKLM-NPQR-STUV',
        );

        fail('expected enrollment failure');
      } on FamilyEnrollmentException catch (error) {
        expect(
          error.failure,
          FamilyEnrollmentFailure.unavailable,
        );
        expect(
          error.toString(),
          isNot(contains('secret transport detail')),
        );
      }
    },
  );

  test(
    'timeout maps to unavailable',
    () async {
      final completer = Completer<http.Response>();

      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) => completer.future,
        ),
        timeout: Duration.zero,
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.unavailable,
          ),
        ),
      );
    },
  );

  test(
    'malformed success response is rejected',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              <String, Object?>{
                'version': 1,
                'control_url': 'https://mesh.rodserver.top',
                'auth_key': 'not-a-real-key',
                'auth_key_expires_in_seconds': 600,
                'home': <String, Object?>{
                  'ipv4': '100.64.0.1',
                  'port': 3000,
                },
              },
            ),
            200,
          ),
        ),
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'non-HTTPS control URL is rejected',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              <String, Object?>{
                'version': 1,
                'control_url': 'http://mesh.rodserver.top',
                'auth_key': _authKey,
                'auth_key_expires_in_seconds': 600,
                'home': <String, Object?>{
                  'ipv4': '100.64.0.1',
                  'port': 3000,
                },
              },
            ),
            200,
          ),
        ),
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'invalid home endpoint is rejected',
    () async {
      final client = FamilyEnrollmentClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(
              <String, Object?>{
                'version': 1,
                'control_url': 'https://mesh.rodserver.top',
                'auth_key': _authKey,
                'auth_key_expires_in_seconds': 600,
                'home': <String, Object?>{
                  'ipv4': '999.64.0.1',
                  'port': 70000,
                },
              },
            ),
            200,
          ),
        ),
      );

      await expectLater(
        client.enroll('ABCD-EFGH-JKLM-NPQR-STUV'),
        throwsA(
          isA<FamilyEnrollmentException>().having(
            (error) => error.failure,
            'failure',
            FamilyEnrollmentFailure.invalidResponse,
          ),
        ),
      );
    },
  );
}
