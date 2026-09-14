import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('authentication metadata uses RodPlayer keys after migration', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'remux_server_url': 'https://media.example.com', 'remux_user_id': 'user'});
    final p = await SharedPreferences.getInstance();
    await CredentialMigration(preferences: p, credentialStore: _NoopStore()).migrate();
    expect(p.getString(CredentialMigration.serverUrlKey), 'https://media.example.com');
    expect(p.getString(CredentialMigration.userIdKey), 'user');
  });
}

class _NoopStore implements CredentialStore {
  Future<void> writeToken(String key, String token) async {}
  Future<String?> readToken(String key) async => null;
  Future<void> deleteToken(String key) async {}
}
