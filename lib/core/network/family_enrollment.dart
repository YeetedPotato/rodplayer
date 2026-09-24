import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum FamilyEnrollmentFailure {
  invalidSetupCode,
  rateLimited,
  unavailable,
  invalidResponse,
}

class FamilyEnrollmentException implements Exception {
  const FamilyEnrollmentException(
    this.failure, {
    this.retryAfter,
  });

  final FamilyEnrollmentFailure failure;
  final Duration? retryAfter;

  @override
  String toString() => 'FamilyEnrollmentException($failure)';
}

class FamilyEnrollmentResult {
  const FamilyEnrollmentResult({
    required this.version,
    required this.controlUrl,
    required this.authKey,
    required this.authKeyLifetime,
    required this.homeIpv4,
    required this.homePort,
  });

  final int version;
  final Uri controlUrl;

  /// One-use Headscale enrollment credential.
  ///
  /// This value is intentionally memory-only at this layer. Callers should
  /// hand it directly to the private-network runtime and discard it after the
  /// runtime has persisted its own node identity.
  final String authKey;

  final Duration authKeyLifetime;
  final String homeIpv4;
  final int homePort;

  Uri get homeBaseUrl => Uri(
        scheme: 'http',
        host: homeIpv4,
        port: homePort,
      );

  @override
  String toString() => 'FamilyEnrollmentResult('
      'version: $version, '
      'controlUrl: $controlUrl, '
      'authKey: <redacted>, '
      'authKeyLifetime: $authKeyLifetime, '
      'homeIpv4: $homeIpv4, '
      'homePort: $homePort'
      ')';
}

class FamilyEnrollmentClient {
  FamilyEnrollmentClient({
    http.Client? client,
    required Uri endpoint,
    this.timeout = const Duration(seconds: 15),
  })  : endpoint = _validatedEndpoint(endpoint),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  static Uri _validatedEndpoint(Uri endpoint) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        (endpoint.hasPort && (endpoint.port < 1 || endpoint.port > 65535)) ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.path.isEmpty) {
      throw ArgumentError.value(
          endpoint, 'endpoint', 'Expected an HTTPS enrollment endpoint');
    }
    return endpoint;
  }

  final http.Client _client;
  final bool _ownsClient;

  final Uri endpoint;
  final Duration timeout;

  Future<FamilyEnrollmentResult> enroll(
    String setupCode,
  ) async {
    final code = setupCode.trim();

    if (code.isEmpty) {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.invalidSetupCode,
      );
    }

    late http.Response response;

    try {
      response = await _client
          .post(
            endpoint,
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(
              <String, Object?>{
                'code': code,
              },
            ),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.unavailable,
      );
    } on http.ClientException {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.unavailable,
      );
    } catch (_) {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.unavailable,
      );
    }

    if (response.statusCode == 400) {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.invalidSetupCode,
      );
    }

    if (response.statusCode == 403 || response.statusCode == 429) {
      throw FamilyEnrollmentException(
        FamilyEnrollmentFailure.rateLimited,
        retryAfter: _retryAfter(response.headers),
      );
    }

    if (response.statusCode >= 500) {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.unavailable,
      );
    }

    if (response.statusCode != 200) {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.invalidResponse,
      );
    }

    return _parseSuccess(response.body);
  }

  FamilyEnrollmentResult _parseSuccess(
    String body,
  ) {
    try {
      final decoded = jsonDecode(body);

      if (decoded is! Map) {
        throw const FormatException();
      }

      final json = Map<String, dynamic>.from(decoded);

      final version = json['version'];
      final controlUrlValue = json['control_url'];
      final authKey = json['auth_key'];
      final lifetimeSeconds = json['auth_key_expires_in_seconds'];
      final home = json['home'];

      if (version != 1 ||
          controlUrlValue is! String ||
          authKey is! String ||
          lifetimeSeconds is! int ||
          home is! Map) {
        throw const FormatException();
      }

      final controlUrl = Uri.tryParse(
        controlUrlValue,
      );

      if (controlUrl == null ||
          controlUrl.scheme != 'https' ||
          controlUrl.host.isEmpty ||
          controlUrl.userInfo.isNotEmpty ||
          controlUrl.query.isNotEmpty ||
          controlUrl.fragment.isNotEmpty) {
        throw const FormatException();
      }

      final homeJson = Map<String, dynamic>.from(home);
      final homeIpv4 = homeJson['ipv4'];
      final homePort = homeJson['port'];

      if (authKey.isEmpty ||
          !_looksLikeHeadscaleAuthKey(authKey) ||
          lifetimeSeconds <= 0 ||
          homeIpv4 is! String ||
          !_looksLikeIpv4(homeIpv4) ||
          homePort is! int ||
          homePort < 1 ||
          homePort > 65535) {
        throw const FormatException();
      }

      return FamilyEnrollmentResult(
        version: version,
        controlUrl: controlUrl,
        authKey: authKey,
        authKeyLifetime: Duration(
          seconds: lifetimeSeconds,
        ),
        homeIpv4: homeIpv4,
        homePort: homePort,
      );
    } catch (_) {
      throw const FamilyEnrollmentException(
        FamilyEnrollmentFailure.invalidResponse,
      );
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

Duration? _retryAfter(
  Map<String, String> headers,
) {
  final value = headers['retry-after'];

  if (value == null) {
    return null;
  }

  final seconds = int.tryParse(
    value.trim(),
  );

  if (seconds == null || seconds < 0) {
    return null;
  }

  return Duration(seconds: seconds);
}

bool _looksLikeHeadscaleAuthKey(
  String value,
) =>
    RegExp(
      r'^hskey-auth-[A-Za-z0-9_-]{12}-[A-Za-z0-9_-]{64}$',
    ).hasMatch(value);

bool _looksLikeIpv4(
  String value,
) {
  final parts = value.split('.');

  if (parts.length != 4) {
    return false;
  }

  for (final part in parts) {
    if (part.isEmpty) {
      return false;
    }

    final number = int.tryParse(part);

    if (number == null || number < 0 || number > 255 || '$number' != part) {
      return false;
    }
  }

  return true;
}
