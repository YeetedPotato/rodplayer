import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/security/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingStore implements CredentialStore {
  @override
  Future<void> deleteToken(String key) async {}
  @override
  Future<String?> readToken(String key) async => null;
  @override
  Future<void> writeToken(String key, String token) async => throw StateError('no secure storage');
}

void main() {
  test('successful migration imports token and removes plaintext only after write verifies', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'remux_access_token': 'secret', 'remux_server_url': 'https://server', 'remux_user_id': 'user'});
    final prefs = await SharedPreferences.getInstance();
    final store = MemoryCredentialStore();
    await CredentialMigration(preferences: prefs, credentialStore: store).migrate();
    expect(await store.readToken(CredentialMigration.tokenKey), 'secret');
    expect(prefs.getString('remux_access_token'), isNull);
    expect(prefs.getString(CredentialMigration.serverUrlKey), 'https://server');
  });

  test('migration is idempotent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'remux_access_token': 'secret'});
    final prefs = await SharedPreferences.getInstance();
    final store = MemoryCredentialStore();
    final migration = CredentialMigration(preferences: prefs, credentialStore: store);
    await migration.migrate();
    await migration.migrate();
    expect(await store.readToken(CredentialMigration.tokenKey), 'secret');
  });

  test('failed secure write keeps legacy token', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'remux_access_token': 'secret'});
    final prefs = await SharedPreferences.getInstance();
    await expectLater(CredentialMigration(preferences: prefs, credentialStore: FailingStore()).migrate(), throwsStateError);
    expect(prefs.getString('remux_access_token'), 'secret');
  });
}
