import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local player presentation preferences; this model contains no credentials.
class PlayerUiSettings {
  const PlayerUiSettings({
    required this.seekIntervalSeconds,
    required this.autoHideSeconds,
    required this.showEndTime,
    required this.singleClickPlayPause,
    required this.doubleClickFullscreen,
    required this.mouseWheelVolume,
  });

  static const schemaVersion = 1;
  static const seekKey = 'rodplayer_player_seek_interval_seconds';
  static const hideKey = 'rodplayer_player_auto_hide_seconds';
  static const endTimeKey = 'rodplayer_player_show_end_time';
  static const clickKey = 'rodplayer_player_single_click';
  static const doubleClickKey = 'rodplayer_player_double_click_fullscreen';
  static const wheelKey = 'rodplayer_player_mouse_wheel_volume';

  static const defaults = PlayerUiSettings(
    seekIntervalSeconds: 10,
    autoHideSeconds: 3,
    showEndTime: true,
    singleClickPlayPause: true,
    doubleClickFullscreen: true,
    mouseWheelVolume: true,
  );

  final int seekIntervalSeconds;
  final int autoHideSeconds;
  final bool showEndTime;
  final bool singleClickPlayPause;
  final bool doubleClickFullscreen;
  final bool mouseWheelVolume;

  static Future<PlayerUiSettings> load({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    return PlayerUiSettings(
      seekIntervalSeconds: _intIn(prefs.getInt(seekKey), const <int>[
        10,
        15,
        30,
      ], 10),
      autoHideSeconds: _intIn(prefs.getInt(hideKey), const <int>[3, 5, 8], 3),
      showEndTime: prefs.getBool(endTimeKey) ?? true,
      singleClickPlayPause: prefs.getBool(clickKey) ?? true,
      doubleClickFullscreen: prefs.getBool(doubleClickKey) ?? true,
      mouseWheelVolume: prefs.getBool(wheelKey) ?? true,
    );
  }

  PlayerUiSettings copyWith({
    int? seekIntervalSeconds,
    int? autoHideSeconds,
    bool? showEndTime,
    bool? singleClickPlayPause,
    bool? doubleClickFullscreen,
    bool? mouseWheelVolume,
  }) => PlayerUiSettings(
    seekIntervalSeconds: seekIntervalSeconds ?? this.seekIntervalSeconds,
    autoHideSeconds: autoHideSeconds ?? this.autoHideSeconds,
    showEndTime: showEndTime ?? this.showEndTime,
    singleClickPlayPause: singleClickPlayPause ?? this.singleClickPlayPause,
    doubleClickFullscreen: doubleClickFullscreen ?? this.doubleClickFullscreen,
    mouseWheelVolume: mouseWheelVolume ?? this.mouseWheelVolume,
  );

  Future<void> save(SharedPreferences preferences) async {
    if (!await preferences.setInt(seekKey, seekIntervalSeconds) ||
        !await preferences.setInt(hideKey, autoHideSeconds) ||
        !await preferences.setBool(endTimeKey, showEndTime) ||
        !await preferences.setBool(clickKey, singleClickPlayPause) ||
        !await preferences.setBool(doubleClickKey, doubleClickFullscreen) ||
        !await preferences.setBool(wheelKey, mouseWheelVolume)) {
      throw StateError('UI settings could not be saved');
    }
  }

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': schemaVersion,
    'seekIntervalSeconds': seekIntervalSeconds,
    'autoHideSeconds': autoHideSeconds,
    'showEndTime': showEndTime,
    'singleClickPlayPause': singleClickPlayPause,
    'doubleClickFullscreen': doubleClickFullscreen,
    'mouseWheelVolume': mouseWheelVolume,
  };

  String exportJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  static final Set<String> toJsonKeys = defaults.toJson().keys.toSet();

  static PlayerUiSettings parseImport(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().difference(toJsonKeys).isNotEmpty ||
        decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported settings document.');
    }
    final seek = decoded['seekIntervalSeconds'];
    final hide = decoded['autoHideSeconds'];
    final endTime = decoded['showEndTime'];
    final click = decoded['singleClickPlayPause'];
    final doubleClick = decoded['doubleClickFullscreen'] ?? true;
    final wheel = decoded['mouseWheelVolume'];
    if (seek is! int ||
        !const <int>[10, 15, 30].contains(seek) ||
        hide is! int ||
        !const <int>[3, 5, 8].contains(hide) ||
        endTime is! bool ||
        click is! bool ||
        doubleClick is! bool ||
        wheel is! bool) {
      throw const FormatException('Invalid player settings values.');
    }
    return PlayerUiSettings(
      seekIntervalSeconds: seek,
      autoHideSeconds: hide,
      showEndTime: endTime,
      singleClickPlayPause: click,
      doubleClickFullscreen: doubleClick,
      mouseWheelVolume: wheel,
    );
  }

  static Future<void> reset(SharedPreferences preferences) async {
    for (final key in <String>[
      seekKey,
      hideKey,
      endTimeKey,
      clickKey,
      doubleClickKey,
      wheelKey,
    ]) {
      if (!await preferences.remove(key))
        throw StateError('UI settings could not be reset');
    }
  }
}

int _intIn(int? value, List<int> allowed, int fallback) =>
    value != null && allowed.contains(value) ? value : fallback;
