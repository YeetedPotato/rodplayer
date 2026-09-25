import 'dart:convert';

import 'package:rodplayer/core/network/family_enrollment.dart';
import 'package:rodplayer/core/network/private_network_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PrivateTransportProfileOrigin { managedInvite, custom }

/// Stable configuration only. Credentials and the ephemeral gateway are not stored here.
class PrivateTransportProfile {
  PrivateTransportProfile({
    required this.id,
    required this.displayName,
    required this.origin,
    required Uri controlUrl,
    required this.serviceIpv4,
    required this.servicePort,
    this.enrollmentEndpoint,
  }) : controlUrl = _canonicalControlUrl(controlUrl) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$').hasMatch(id) ||
        displayName.trim().isEmpty ||
        displayName != displayName.trim() ||
        displayName.length > 120 ||
        !_validIpv4(serviceIpv4) ||
        servicePort < 1 ||
        servicePort > 65535 ||
        (enrollmentEndpoint != null &&
            !_validEnrollmentEndpoint(enrollmentEndpoint!)) ||
        (origin == PrivateTransportProfileOrigin.managedInvite &&
            enrollmentEndpoint == null)) {
      throw const FormatException('Invalid private transport profile');
    }
  }

  static const schemaVersion = 1;
  final String id;
  final String displayName;
  final PrivateTransportProfileOrigin origin;
  final Uri controlUrl;
  final String serviceIpv4;
  final int servicePort;
  final Uri? enrollmentEndpoint;

  /// Enrollment supplied by the selected owner, never by a product default.
  factory PrivateTransportProfile.fromEnrollment({
    required String id,
    required String displayName,
    required Uri enrollmentEndpoint,
    required FamilyEnrollmentResult enrollment,
  }) =>
      PrivateTransportProfile(
        id: id,
        displayName: displayName,
        origin: PrivateTransportProfileOrigin.managedInvite,
        controlUrl: enrollment.controlUrl,
        serviceIpv4: enrollment.homeIpv4,
        servicePort: enrollment.homePort,
        enrollmentEndpoint: enrollmentEndpoint,
      );

  PrivateNetworkIdentityClaim get identityClaim => PrivateNetworkIdentityClaim(
        profileId: id,
        controlUrl: controlUrl,
        homeIpv4: serviceIpv4,
        homePort: servicePort,
      );

  Map<String, Object?> toJson() => {
        'version': schemaVersion,
        'id': id,
        'displayName': displayName,
        'origin': origin.name,
        'controlUrl': controlUrl.toString(),
        'serviceIpv4': serviceIpv4,
        'servicePort': servicePort,
        if (enrollmentEndpoint != null)
          'enrollmentEndpoint': enrollmentEndpoint.toString(),
      };

  factory PrivateTransportProfile.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != schemaVersion ||
        value.keys.any((key) => !{
              'version',
              'id',
              'displayName',
              'origin',
              'controlUrl',
              'serviceIpv4',
              'servicePort',
              'enrollmentEndpoint'
            }.contains(key)) ||
        value['id'] is! String ||
        value['displayName'] is! String ||
        value['controlUrl'] is! String ||
        value['serviceIpv4'] is! String ||
        value['servicePort'] is! int ||
        (value['enrollmentEndpoint'] != null &&
            value['enrollmentEndpoint'] is! String)) {
      throw const FormatException('Invalid private transport profile');
    }
    final origin = PrivateTransportProfileOrigin.values.where(
      (candidate) => candidate.name == value['origin'],
    );
    if (origin.length != 1) {
      throw const FormatException('Invalid private transport profile origin');
    }
    final controlUrl = Uri.tryParse(value['controlUrl'] as String);
    final endpoint = value['enrollmentEndpoint'] == null
        ? null
        : Uri.tryParse(value['enrollmentEndpoint'] as String);
    if (controlUrl == null ||
        (value['enrollmentEndpoint'] != null && endpoint == null)) {
      throw const FormatException('Invalid private transport URL');
    }
    return PrivateTransportProfile(
      id: value['id'] as String,
      displayName: value['displayName'] as String,
      origin: origin.single,
      controlUrl: controlUrl,
      serviceIpv4: value['serviceIpv4'] as String,
      servicePort: value['servicePort'] as int,
      enrollmentEndpoint: endpoint,
    );
  }

  static bool _validHttpsRoot(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || (uri.port >= 1 && uri.port <= 65535)) &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path.isEmpty || uri.path == '/');

  // A control endpoint is identified by HTTPS host (case-insensitive) and
  // effective port. The root slash and explicit default :443 are equivalent.
  static Uri _canonicalControlUrl(Uri uri) {
    if (!_validHttpsRoot(uri)) {
      throw const FormatException('Invalid private transport control URL');
    }
    return Uri(
      scheme: 'https',
      host: uri.host.toLowerCase(),
      port: uri.port == 443 ? null : uri.port,
    );
  }

  static bool _validEnrollmentEndpoint(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || (uri.port >= 1 && uri.port <= 65535)) &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.path.isNotEmpty;

  static bool _validIpv4(String value) {
    final parts = value.split('.');
    return parts.length == 4 &&
        parts.every((part) {
          final number = int.tryParse(part);
          return number != null &&
              number >= 0 &&
              number <= 255 &&
              number.toString() == part;
        });
  }
}

/// Owner-supplied invite configuration. It performs no network operation itself.
class PrivateTransportInvitation {
  PrivateTransportInvitation({
    required this.profileId,
    required this.displayName,
    required this.enrollmentEndpoint,
  }) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$').hasMatch(profileId) ||
        displayName.trim().isEmpty ||
        displayName != displayName.trim() ||
        displayName.length > 120 ||
        !PrivateTransportProfile._validEnrollmentEndpoint(enrollmentEndpoint)) {
      throw const FormatException('Invalid private transport invitation');
    }
  }

  final String profileId;
  final String displayName;
  final Uri enrollmentEndpoint;

  static PrivateTransportInvitation parse(String document) {
    try {
      final value = jsonDecode(document);
      if (value is! Map<String, dynamic> ||
          value.length != 4 ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['profileId'] is! String ||
          value['displayName'] is! String ||
          value['enrollmentEndpoint'] is! String ||
          value.keys.any((key) => !{
                'version',
                'profileId',
                'displayName',
                'enrollmentEndpoint',
              }.contains(key))) {
        throw const FormatException();
      }
      return PrivateTransportInvitation(
        profileId: value['profileId'] as String,
        displayName: value['displayName'] as String,
        enrollmentEndpoint: Uri.parse(value['enrollmentEndpoint'] as String),
      );
    } catch (_) {
      throw const FormatException('Invalid private transport invitation');
    }
  }

  PrivateTransportProfile profileFrom(FamilyEnrollmentResult enrollment) =>
      PrivateTransportProfile.fromEnrollment(
        id: profileId,
        displayName: displayName,
        enrollmentEndpoint: enrollmentEndpoint,
        enrollment: enrollment,
      );

  PrivateNetworkBootstrap bootstrapFrom(FamilyEnrollmentResult enrollment) =>
      PrivateNetworkBootstrap.fromEnrollment(enrollment, profileId: profileId);
}

class PrivateTransportProfileStore {
  const PrivateTransportProfileStore(this.preferences);

  static const preferenceKey = 'rodplayer_private_transport_profiles';
  final SharedPreferences preferences;

  List<PrivateTransportProfile> all() {
    final raw = preferences.get(preferenceKey);
    if (raw == null) return const [];
    if (raw is! String) throw const FormatException('Invalid profile store');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded['version'] != 1 ||
        decoded['profiles'] is! List) {
      throw const FormatException('Invalid profile store');
    }
    final profiles = (decoded['profiles'] as List)
        .map(PrivateTransportProfile.fromJson)
        .toList(growable: false);
    if (profiles.map((profile) => profile.id).toSet().length !=
        profiles.length) {
      throw const FormatException('Duplicate profile ID');
    }
    return List.unmodifiable(profiles);
  }

  PrivateTransportProfile? find(String id) {
    for (final profile in all()) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// A legacy unlabelled node may be claimed only by one canonical config.
  bool uniquelyMatches(PrivateTransportProfile profile) =>
      all()
          .where((other) =>
              other.controlUrl == profile.controlUrl &&
              other.serviceIpv4 == profile.serviceIpv4 &&
              other.servicePort == profile.servicePort)
          .length ==
      1;

  Future<void> put(PrivateTransportProfile profile) async {
    final profiles = [...all()];
    final index = profiles.indexWhere((existing) => existing.id == profile.id);
    if (index < 0) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _write(profiles);
  }

  Future<void> remove(String id) async {
    await _write(all().where((profile) => profile.id != id).toList());
  }

  Future<void> _write(List<PrivateTransportProfile> profiles) => preferences
          .setString(
              preferenceKey,
              jsonEncode({
                'version': 1,
                'profiles':
                    profiles.map((profile) => profile.toJson()).toList(),
              }))
          .then((saved) {
        if (!saved) {
          throw StateError('Could not save private transport profiles');
        }
      });
}
