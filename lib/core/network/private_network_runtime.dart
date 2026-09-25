import 'package:rodplayer/core/network/family_enrollment.dart';

enum PrivateNetworkState {
  stopped,
  starting,
  ready,
  unavailable,
}

enum PrivateNetworkPath {
  none,
  direct,
  relay,
}

enum PrivateNetworkUnavailableReason {
  none,
  noIdentity,
  directPathUnavailable,
  hostUnavailable,
  transportFailure,
  unknown,
}

enum PrivateNetworkFailure {
  hostUnavailable,
  operationFailed,
  invalidNativeResponse,
  closed,
}

class PrivateNetworkException implements Exception {
  const PrivateNetworkException(this.failure);

  final PrivateNetworkFailure failure;

  @override
  String toString() => 'PrivateNetworkException($failure)';
}

class PrivateNetworkBootstrap {
  const PrivateNetworkBootstrap({
    required this.profileId,
    required this.version,
    required this.controlUrl,
    required this.authKey,
    required this.homeIpv4,
    required this.homePort,
  });

  factory PrivateNetworkBootstrap.fromEnrollment(
    FamilyEnrollmentResult enrollment, {
    required String profileId,
  }) =>
      PrivateNetworkBootstrap(
        profileId: profileId,
        version: enrollment.version,
        controlUrl: enrollment.controlUrl,
        authKey: enrollment.authKey,
        homeIpv4: enrollment.homeIpv4,
        homePort: enrollment.homePort,
      );

  final String profileId;
  final int version;
  final Uri controlUrl;

  /// One-use Headscale credential.
  ///
  /// This is passed directly to the native private-network host during
  /// bootstrap and must never be persisted by Dart.
  final String authKey;

  final String homeIpv4;
  final int homePort;

  @override
  String toString() => 'PrivateNetworkBootstrap('
      'profileId: $profileId, '
      'version: $version, '
      'controlUrl: $controlUrl, '
      'authKey: <redacted>, '
      'homeIpv4: $homeIpv4, '
      'homePort: $homePort'
      ')';
}

/// Explicit claim checked by native code before retained identity is resumed.
class PrivateNetworkIdentityClaim {
  const PrivateNetworkIdentityClaim({
    required this.profileId,
    required this.controlUrl,
    required this.homeIpv4,
    required this.homePort,
    this.allowLegacyClaim = false,
  });

  final String profileId;
  final Uri controlUrl;
  final String homeIpv4;
  final int homePort;
  final bool allowLegacyClaim;
}

class PrivateNetworkStatus {
  const PrivateNetworkStatus({
    required this.state,
    required this.path,
    required this.hasPersistedIdentity,
    required this.unavailableReason,
    this.gatewayBaseUrl,
  });

  final PrivateNetworkState state;
  final PrivateNetworkPath path;
  final bool hasPersistedIdentity;
  final PrivateNetworkUnavailableReason unavailableReason;
  final Uri? gatewayBaseUrl;

  bool get canProxy {
    final gateway = gatewayBaseUrl;
    if (state != PrivateNetworkState.ready ||
        path != PrivateNetworkPath.direct ||
        !hasPersistedIdentity ||
        unavailableReason != PrivateNetworkUnavailableReason.none ||
        gateway == null) {
      return false;
    }
    try {
      _parseLoopbackGateway(gateway.toString());
      return true;
    } on FormatException {
      return false;
    }
  }

  factory PrivateNetworkStatus.fromPayload(
    Object? payload,
  ) {
    try {
      if (payload is! Map) {
        throw const FormatException();
      }

      final values = Map<String, Object?>.from(payload);

      final state = _parseState(values['state']);
      final path = _parsePath(values['path']);
      final hasIdentity = values['hasPersistedIdentity'];

      if (hasIdentity is! bool) {
        throw const FormatException();
      }

      final gatewayValue = values['gatewayUrl'];
      final gateway =
          gatewayValue == null ? null : _parseLoopbackGateway(gatewayValue);

      final reason = _parseUnavailableReason(
        values['reason'],
      );

      if (state == PrivateNetworkState.ready) {
        if (path != PrivateNetworkPath.direct ||
            gateway == null ||
            !hasIdentity) {
          throw const FormatException();
        }
      } else if (gateway != null) {
        throw const FormatException();
      }

      if (state == PrivateNetworkState.stopped &&
          path != PrivateNetworkPath.none) {
        throw const FormatException();
      }

      if (state == PrivateNetworkState.unavailable) {
        if (reason == PrivateNetworkUnavailableReason.none) {
          throw const FormatException();
        }
      } else if (reason != PrivateNetworkUnavailableReason.none) {
        throw const FormatException();
      }

      return PrivateNetworkStatus(
        state: state,
        path: path,
        hasPersistedIdentity: hasIdentity,
        unavailableReason: reason,
        gatewayBaseUrl: gateway,
      );
    } catch (_) {
      throw const PrivateNetworkException(
        PrivateNetworkFailure.invalidNativeResponse,
      );
    }
  }

  @override
  String toString() => 'PrivateNetworkStatus('
      'state: $state, '
      'path: $path, '
      'hasPersistedIdentity: $hasPersistedIdentity, '
      'unavailableReason: $unavailableReason, '
      'gatewayBaseUrl: $gatewayBaseUrl'
      ')';
}

abstract interface class PrivateNetworkRuntime {
  Future<bool> confirmHostAvailable();

  Future<PrivateNetworkStatus> status();

  Future<PrivateNetworkStatus> bootstrap(
    PrivateNetworkBootstrap bootstrap,
  );

  Future<PrivateNetworkStatus> resume(PrivateNetworkIdentityClaim claim);

  Future<void> stop();

  /// Deletes the locally persisted mesh identity and Family Setup state.
  ///
  /// This is separate from Jellyfin logout/profile switching.
  Future<void> reset();

  Stream<PrivateNetworkStatus> get statuses;
}

PrivateNetworkState _parseState(
  Object? value,
) =>
    switch (value) {
      'stopped' => PrivateNetworkState.stopped,
      'starting' => PrivateNetworkState.starting,
      'ready' => PrivateNetworkState.ready,
      'unavailable' => PrivateNetworkState.unavailable,
      _ => throw const FormatException(),
    };

PrivateNetworkPath _parsePath(
  Object? value,
) =>
    switch (value) {
      'none' => PrivateNetworkPath.none,
      'direct' => PrivateNetworkPath.direct,
      'relay' => PrivateNetworkPath.relay,
      _ => throw const FormatException(),
    };

PrivateNetworkUnavailableReason _parseUnavailableReason(
  Object? value,
) =>
    switch (value) {
      null || 'none' => PrivateNetworkUnavailableReason.none,
      'no_identity' => PrivateNetworkUnavailableReason.noIdentity,
      'direct_path_unavailable' =>
        PrivateNetworkUnavailableReason.directPathUnavailable,
      'host_unavailable' => PrivateNetworkUnavailableReason.hostUnavailable,
      'transport_failure' => PrivateNetworkUnavailableReason.transportFailure,
      String() => PrivateNetworkUnavailableReason.unknown,
      _ => throw const FormatException(),
    };

Uri _parseLoopbackGateway(
  Object? value,
) {
  if (value is! String) {
    throw const FormatException();
  }

  final uri = Uri.tryParse(value);

  if (uri == null ||
      uri.scheme != 'http' ||
      uri.host != '127.0.0.1' ||
      !uri.hasPort ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException();
  }

  return uri.replace(path: '');
}
