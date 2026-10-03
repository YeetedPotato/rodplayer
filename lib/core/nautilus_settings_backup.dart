import 'dart:convert';

import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/player_ui_settings.dart';

/// Versioned app-local settings export. Server profiles and credentials are
/// intentionally outside this model.
class NautilusSettingsBackup {
  const NautilusSettingsBackup({required this.player, required this.home});

  static const schemaVersion = 1;

  final PlayerUiSettings player;
  final HomeShelfPreferences home;

  Map<String, Object> toJson() => <String, Object>{
        'schemaVersion': schemaVersion,
        'player': player.toJson(),
        'homeShelves': home.toJson(),
      };

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static NautilusSettingsBackup parseImport(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.length != 3 ||
        !decoded.keys.toSet().containsAll(
            const <String>{'schemaVersion', 'player', 'homeShelves'}) ||
        decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported settings backup.');
    }
    final player = PlayerUiSettings.parseImport(jsonEncode(decoded['player']));
    final home = HomeShelfPreferences.fromJson(decoded['homeShelves']);
    return NautilusSettingsBackup(player: player, home: home);
  }
}
