import 'dart:convert';

import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PrivateTransportAssociationKind { none, associated, invalid }

class PrivateTransportAssociationLookup {
  const PrivateTransportAssociationLookup(this.kind, [this.profileId]);

  final PrivateTransportAssociationKind kind;
  final String? profileId;
}

/// Associates the saved canonical server with an explicitly configured transport.
/// The profile ID is opaque; gateway addresses never belong in this record.
class PrivateTransportProfileAssociation {
  const PrivateTransportProfileAssociation(this.preferences);

  static const preferenceKey = 'rodplayer_server_private_transport_profile';
  final SharedPreferences preferences;

  PrivateTransportAssociationLookup lookupFor(String canonicalServerUrl) {
    final saved = preferences.getString(CredentialMigration.serverUrlKey);
    if (saved != canonicalServerUrl ||
        !preferences.containsKey(preferenceKey)) {
      return const PrivateTransportAssociationLookup(
          PrivateTransportAssociationKind.none);
    }
    final encoded = preferences.get(preferenceKey);
    if (encoded is! String) {
      return const PrivateTransportAssociationLookup(
          PrivateTransportAssociationKind.invalid);
    }
    try {
      final record = jsonDecode(encoded);
      if (record is! Map || record['serverUrl'] != canonicalServerUrl) {
        return const PrivateTransportAssociationLookup(
            PrivateTransportAssociationKind.invalid);
      }
      final id = record['profileId'];
      if (id is String && id.isNotEmpty && id == id.trim()) {
        return PrivateTransportAssociationLookup(
            PrivateTransportAssociationKind.associated, id);
      }
    } on FormatException {
      // A present but unreadable association must never become public routing.
    }
    return const PrivateTransportAssociationLookup(
        PrivateTransportAssociationKind.invalid);
  }

  Future<void> associate(String canonicalServerUrl, String profileId) async {
    final url = Uri.tryParse(canonicalServerUrl);
    if (url == null ||
        !{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        profileId.isEmpty ||
        profileId != profileId.trim()) {
      throw ArgumentError(
          'A saved server URL and nonempty profile ID are required.');
    }
    if (preferences.getString(CredentialMigration.serverUrlKey) !=
        canonicalServerUrl) {
      throw StateError('The canonical server must be saved first.');
    }
    await preferences.setString(
        preferenceKey,
        jsonEncode({
          'serverUrl': canonicalServerUrl,
          'profileId': profileId,
        }));
  }

  Future<void> clear() => preferences.remove(preferenceKey);
}
