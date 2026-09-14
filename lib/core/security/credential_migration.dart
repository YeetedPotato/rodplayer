import 'package:rodplayer/core/security/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CredentialMigration {
  CredentialMigration({required this.preferences, required this.credentialStore});

  static const tokenKey = 'rodplayer_access_token';
  static const legacyTokenKey = 'remux_access_token';
  static const serverUrlKey = 'rodplayer_server_url';
  static const legacyServerUrlKey = 'remux_server_url';
  static const userIdKey = 'rodplayer_user_id';
  static const legacyUserIdKey = 'remux_user_id';
  static const recentSearchesKey = 'rodplayer_recent_searches';
  static const legacyRecentSearchesKey = 'remux_recent_searches';

  final SharedPreferences preferences;
  final CredentialStore credentialStore;

  Future<void> migrate() async {
    await _migrateString(legacyServerUrlKey, serverUrlKey);
    await _migrateString(legacyUserIdKey, userIdKey);
    await _migrateStringList(legacyRecentSearchesKey, recentSearchesKey);

    final legacyToken = preferences.getString(legacyTokenKey);
    if (legacyToken == null || legacyToken.isEmpty) return;
    await credentialStore.writeToken(tokenKey, legacyToken);
    final stored = await credentialStore.readToken(tokenKey);
    if (stored == legacyToken) {
      await preferences.remove(legacyTokenKey);
    }
  }

  Future<void> _migrateString(String oldKey, String newKey) async {
    if (!preferences.containsKey(newKey)) {
      final value = preferences.getString(oldKey);
      if (value != null) await preferences.setString(newKey, value);
    }
    if (preferences.containsKey(oldKey)) await preferences.remove(oldKey);
  }

  Future<void> _migrateStringList(String oldKey, String newKey) async {
    if (!preferences.containsKey(newKey)) {
      final value = preferences.getStringList(oldKey);
      if (value != null) await preferences.setStringList(newKey, value);
    }
    if (preferences.containsKey(oldKey)) await preferences.remove(oldKey);
  }
}
