import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:rodplayer/core/security/credential_migration.dart';
import 'package:rodplayer/core/network/private_transport_profile.dart';
import 'package:rodplayer/core/network/private_transport_profile_association.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {

  test('existing preference identifiers remain compatibility-stable', () {
    expect(SharedPreferencesInstallationIdentityStore.deviceIdKey, 'rodplayer_device_id');
    expect(CredentialMigration.tokenKey, 'rodplayer_access_token');
    expect(CredentialMigration.serverUrlKey, 'rodplayer_server_url');
    expect(CredentialMigration.recentSearchesKey, 'rodplayer_recent_searches');
    expect(PrivateTransportProfileStore.preferenceKey, 'rodplayer_private_transport_profiles');
    expect(PrivateTransportProfileAssociation.preferenceKey, 'rodplayer_server_private_transport_profile');
    expect(PrivateTransportProfileAssociation.pendingSetupKey, 'rodplayer_private_transport_setup_pending');
  });

  test('first load generates ID and later load returns same ID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesInstallationIdentityStore(prefs, appVersion: '2.3.4');
    final first = await store.load();
    final second = await store.load();
    expect(first.deviceId, isNotEmpty);
    expect(second.deviceId, first.deviceId);
    expect(first.clientName, 'Nautilus');
    final expectedDeviceName = kIsWeb ? 'Web device' : switch (Platform.operatingSystem) {
      'android' => 'Android device',
      'ios' => 'iOS device',
      'macos' => 'macOS device',
      'windows' => 'Windows device',
      'linux' => 'Linux device',
      _ => 'Unknown device',
    };
    expect(first.deviceName, expectedDeviceName);
    expect(first.appVersion, '2.3.4');
    expect(prefs.getString(SharedPreferencesInstallationIdentityStore.deviceIdKey), first.deviceId);
  });

  test('legacy ID is retained and moved to the current preference key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SharedPreferencesInstallationIdentityStore.legacyDeviceIdKey: 'existing-id',
    });
    final prefs = await SharedPreferences.getInstance();
    final identity = await SharedPreferencesInstallationIdentityStore(prefs).load();
    expect(identity.deviceId, 'existing-id');
    expect(prefs.getString(SharedPreferencesInstallationIdentityStore.deviceIdKey), 'existing-id');
    expect(prefs.containsKey(SharedPreferencesInstallationIdentityStore.legacyDeviceIdKey), isFalse);
  });
}
