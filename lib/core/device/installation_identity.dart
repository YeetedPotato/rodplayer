import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class InstallationIdentity {
  const InstallationIdentity({
    required this.deviceId,
    required this.clientName,
    required this.deviceName,
    required this.appVersion,
  });

  final String deviceId;
  final String clientName;
  final String deviceName;
  final String appVersion;
}

abstract interface class InstallationIdentityStore {
  Future<InstallationIdentity> load();
}

class SharedPreferencesInstallationIdentityStore implements InstallationIdentityStore {
  SharedPreferencesInstallationIdentityStore(this.preferences, {Uuid? uuid, String? appVersion})
      : _uuid = uuid ?? const Uuid(),
        _appVersion = appVersion ?? '0.1.1';

  static const deviceIdKey = 'rodplayer_device_id';
  static const legacyDeviceIdKey = 'remux_device_id';

  final SharedPreferences preferences;
  final Uuid _uuid;
  final String _appVersion;

  @override
  Future<InstallationIdentity> load() async {
    var id = preferences.getString(deviceIdKey);
    id ??= preferences.getString(legacyDeviceIdKey);
    if (id == null || id.trim().isEmpty) {
      id = _uuid.v4();
    }
    await preferences.setString(deviceIdKey, id);
    if (preferences.containsKey(legacyDeviceIdKey)) {
      await preferences.remove(legacyDeviceIdKey);
    }
    return InstallationIdentity(
      deviceId: id,
      clientName: 'RodPlayer',
      deviceName: _platformDeviceName(),
      appVersion: _appVersion,
    );
  }

  static String _platformDeviceName() {
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iOS device';
    if (Platform.isMacOS) return 'macOS device';
    if (Platform.isWindows) return 'Windows device';
    if (Platform.isLinux) return 'Linux device';
    return 'Unknown device';
  }
}
