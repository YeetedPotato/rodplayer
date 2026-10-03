import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/nautilus_settings_backup.dart';

/// One in-flight save and one coalesced latest intent. Import uses the same
/// transaction as ordinary edits; failures restore raw values then reread disk.
final class UiSettingsPersistence extends ChangeNotifier {
  UiSettingsPersistence(this.preferences, this.baseline);
  static final _owners = Expando<Future<UiSettingsPersistence>>();
  static Future<UiSettingsPersistence> acquire(SharedPreferences preferences) =>
      _owners[preferences] ??= _load(preferences);
  static Future<UiSettingsPersistence> _load(
      SharedPreferences preferences) async {
    try {
      return UiSettingsPersistence(
          preferences,
          NautilusSettingsBackup(
              player: await PlayerUiSettings.load(preferences: preferences),
              home: await HomeShelfPreferences.load(preferences: preferences)));
    } on Object {
      _owners[preferences] = null;
      rethrow;
    }
  }

  final SharedPreferences preferences;
  NautilusSettingsBackup baseline;
  bool baselineVerified = true;
  _SettingsWrite? _pending;
  bool _saving = false;
  bool get isSaving => _saving;
  Completer<void>? _settled;
  Future<void> get whenSettled => _settled?.future ?? Future<void>.value();
  NautilusSettingsBackup? _intent;
  NautilusSettingsBackup get intent => _intent ?? baseline;
  Future<bool> updatePlayer(
          PlayerUiSettings Function(PlayerUiSettings) update) =>
      save(NautilusSettingsBackup(
          player: update(intent.player), home: intent.home));

  static const keys = <String>[
    PlayerUiSettings.seekKey,
    PlayerUiSettings.hideKey,
    PlayerUiSettings.endTimeKey,
    PlayerUiSettings.clickKey,
    PlayerUiSettings.doubleClickKey,
    PlayerUiSettings.wheelKey,
    HomeShelfPreferences.orderKey,
    HomeShelfPreferences.visibleKey,
    HomeShelfPreferences.schemaVersionKey,
  ];

  Future<bool> save(NautilusSettingsBackup value, {bool resetPlayer = false}) {
    _intent = value;
    final pending = _pending;
    if (pending != null) {
      pending.value = value;
      pending.resetPlayer = resetPlayer;
      notifyListeners();
      return pending.result.future;
    }
    final request = _SettingsWrite(value, resetPlayer);
    _pending = request;
    if (!_saving) {
      unawaited(_drain());
    } else {
      notifyListeners();
    }
    return request.result.future;
  }

  Future<void> _drain() async {
    _saving = true;
    _settled = Completer<void>();
    notifyListeners();
    while (_pending != null) {
      final request = _pending!;
      _pending = null;
      var success = false;
      try {
        success = await _write(request);
      } on Object {
        // Optional local persistence never leaves an unobserved Future error.
      }
      notifyListeners();
      request.result.complete(success);
    }
    _saving = false;
    _intent = baseline;
    _settled!.complete();
    _settled = null;
    notifyListeners();
  }

  Future<bool> _write(_SettingsWrite request) async {
    final before = <String, Object?>{
      for (final key in keys) key: preferences.get(key),
    };
    try {
      if (request.resetPlayer) {
        await PlayerUiSettings.reset(preferences);
      } else {
        await request.value.player.save(preferences);
      }
      await request.value.home.save(preferences);
      baseline = request.value;
      baselineVerified = true;
      return true;
    } on Object {
      for (final entry in before.entries) {
        try {
          final value = entry.value;
          final bool restored;
          if (value == null) {
            restored = await preferences.remove(entry.key);
          } else if (value is bool) {
            restored = await preferences.setBool(entry.key, value);
          } else if (value is int) {
            restored = await preferences.setInt(entry.key, value);
          } else if (value is List<String>) {
            restored = await preferences.setStringList(entry.key, value);
          } else if (value is String) {
            restored = await preferences.setString(entry.key, value);
          } else {
            throw StateError('Unsupported stored UI setting');
          }
          if (!restored) throw StateError('UI settings rollback failed');
        } on Object {
          // Continue restoring other keys; reload determines durable truth.
        }
      }
      baselineVerified = false;
      await preferences.reload();
      baseline = NautilusSettingsBackup(
        player: await PlayerUiSettings.load(preferences: preferences),
        home: await HomeShelfPreferences.load(preferences: preferences),
      );
      baselineVerified = true;
      return false;
    }
  }
}

final class _SettingsWrite {
  _SettingsWrite(this.value, this.resetPlayer);
  NautilusSettingsBackup value;
  bool resetPlayer;
  final result = Completer<bool>();
}
