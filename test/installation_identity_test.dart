import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/device/installation_identity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('first load generates ID and later load returns same ID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPreferencesInstallationIdentityStore(prefs, appVersion: '2.3.4');
    final first = await store.load();
    final second = await store.load();
    expect(first.deviceId, isNotEmpty);
    expect(second.deviceId, first.deviceId);
    expect(first.clientName, 'RodPlayer');
    expect(first.deviceName, isNot('FireTV'));
    expect(first.appVersion, '2.3.4');
  });
}
