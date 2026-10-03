import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/nautilus_settings_backup.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/settings/ui_settings_persistence.dart';
import 'package:rodplayer/core/theme/appearance_controller.dart';
import 'package:rodplayer/core/theme/appearance_mode.dart';

/// App-local settings only. Jellyfin account preferences remain on Profile.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    this.appearanceController,
    this.onHomeShelfPreferencesChanged,
    super.key,
  });

  final AppearanceController? appearanceController;
  final ValueChanged<HomeShelfPreferences>? onHomeShelfPreferencesChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  UiSettingsPersistence? _persistence;
  PlayerUiSettings _settings = PlayerUiSettings.defaults;
  HomeShelfPreferences _homeShelves = HomeShelfPreferences.defaults;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  bool _unverified = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _persistence?.removeListener(_syncSettings);
    super.dispose();
  }

  void _syncSettings() {
    final store = _persistence;
    if (!mounted || store == null) return;
    final model = store.isSaving ? store.intent : store.baseline;
    setState(() {
      _settings = model.player;
      _homeShelves = model.home;
      _saving = store.isSaving;
      _unverified = !store.baselineVerified;
      _loading = false;
    });
    if (!store.isSaving && store.baselineVerified) {
      widget.onHomeShelfPreferencesChanged?.call(store.baseline.home);
    }
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    try {
      final prefs = await SharedPreferences.getInstance();
      final store = await UiSettingsPersistence.acquire(prefs);
      if (!mounted) return;
      _persistence?.removeListener(_syncSettings);
      _persistence = store;
      store.addListener(_syncSettings);
      _syncSettings();
    } on Object {
      if (mounted)
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
    }
  }

  Future<void> _setAppearance(AppearanceMode mode) async {
    try {
      await widget.appearanceController!.setMode(mode);
      if (mounted) setState(() {});
    } on Object {
      if (mounted)
        _message('Unable to save appearance. Previous mode retained.');
    }
  }

  Future<void> _save(
      PlayerUiSettings Function(PlayerUiSettings) update) async {
    final store = _persistence;
    if (store == null) return;
    await _persist(
      NautilusSettingsBackup(
          player: update(store.intent.player), home: store.intent.home),
    );
  }

  Future<void> _saveHomeShelves(
      HomeShelfPreferences Function(HomeShelfPreferences) update) async {
    final store = _persistence;
    if (store == null) return;
    await _persist(NautilusSettingsBackup(
        player: store.intent.player, home: update(store.intent.home)));
  }

  Future<bool> _persist(
    NautilusSettingsBackup value, {
    bool resetPlayer = false,
  }) async {
    final store = _persistence!;
    final result = await store.save(value, resetPlayer: resetPlayer);
    if (!mounted) return result;
    if (!result)
      _message(
        store.baselineVerified
            ? 'Unable to save UI settings. Stored settings have been reloaded.'
            : 'Unable to save UI settings. Stored state could not be verified.',
      );
    return result;
  }

  void _moveHomeShelf(HomeShelfId shelf, int delta) {
    final current = _persistence?.intent.home;
    if (current == null) return;
    final order = current.order.toList();
    final index = order.indexOf(shelf);
    final destination = index + delta;
    if (index < 0 || destination < 0 || destination >= order.length) return;
    order.removeAt(index);
    order.insert(destination, shelf);
    unawaited(_saveHomeShelves((value) => value.copyWith(order: order)));
  }

  Future<void> _export() async {
    final store = _persistence;
    if (store == null) return;
    if (!store.baselineVerified) {
      _message('Stored settings could not be verified. Export is unavailable.');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: store.baseline.exportJson()));
      if (mounted) _message('UI settings copied. No credentials are included.');
    } on Object {
      if (mounted) _message('Unable to copy UI settings.');
    }
  }

  Future<void> _import() async {
    final source = await showDialog<String>(
      context: context,
      builder: (context) => const _SettingsImportDialog(),
    );
    if (source == null || !mounted) return;
    try {
      final backup = NautilusSettingsBackup.parseImport(source);
      final saved = await _persist(backup);
      if (mounted && saved) _message('UI settings imported.');
    } on Object {
      if (mounted) {
        _message('That settings document is invalid or unsupported.');
      }
    }
  }

  Future<void> _reset() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset UI settings?'),
        content: const Text(
          'This resets appearance, Home layout, and local player controls. Your profile, server connections, credentials, and private-network identity are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset UI settings'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    if (_persistence == null) return;
    if (!await _persist(
      const NautilusSettingsBackup(
        player: PlayerUiSettings.defaults,
        home: HomeShelfPreferences.defaults,
      ),
      resetPlayer: true,
    )) return;
    try {
      await widget.appearanceController?.setMode(AppearanceMode.oled);
    } on Object {
      if (mounted)
        _message('UI settings reset, but appearance could not be saved.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _settings = PlayerUiSettings.defaults;
      _homeShelves = HomeShelfPreferences.defaults;
    });
    widget.onHomeShelfPreferencesChanged?.call(HomeShelfPreferences.defaults);
    _message('UI settings reset.');
  }

  void _message(String value) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('App settings')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadFailed
                ? Center(
                    child: TextButton(
                        onPressed: () => unawaited(_load()),
                        child: const Text('Settings unavailable. Retry')))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: <Widget>[
                      if (_saving) const Text('Saving UI settings...'),
                      if (_unverified)
                        const Text('Stored settings could not be verified.'),
                      if (widget.appearanceController != null)
                        _section(
                          context,
                          'Appearance',
                          Icons.palette_outlined,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('App-local color mode'),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: <Widget>[
                                  for (final mode in AppearanceMode.values)
                                    ChoiceChip(
                                      label: Text(_appearanceLabel(mode)),
                                      selected:
                                          widget.appearanceController!.mode ==
                                              mode,
                                      onSelected: (selected) {
                                        if (selected) {
                                          unawaited(
                                            _setAppearance(mode),
                                          );
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      _section(
                        context,
                        'Player',
                        Icons.play_circle_outline,
                        Column(
                          children: <Widget>[
                            DropdownButtonFormField<int>(
                              key: ValueKey('seek-${_settings.seekIntervalSeconds}'),
                              initialValue: _settings.seekIntervalSeconds,
                              decoration: const InputDecoration(
                                labelText: 'Seek interval',
                              ),
                              items: const <int>[10, 15, 30]
                                  .map(
                                    (value) => DropdownMenuItem<int>(
                                      value: value,
                                      child: Text('$value seconds'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  unawaited(
                                    _save(
                                      (current) => current.copyWith(
                                          seekIntervalSeconds: value),
                                    ),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                              key: ValueKey('hide-${_settings.autoHideSeconds}'),
                              initialValue: _settings.autoHideSeconds,
                              decoration: const InputDecoration(
                                labelText: 'Controls hide after',
                              ),
                              items: const <int>[3, 5, 8]
                                  .map(
                                    (value) => DropdownMenuItem<int>(
                                      value: value,
                                      child: Text('$value seconds'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  unawaited(
                                    _save((current) => current.copyWith(
                                        autoHideSeconds: value)),
                                  );
                                }
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Show estimated end time'),
                              value: _settings.showEndTime,
                              onChanged: (value) => unawaited(
                                _save((current) => current.copyWith(showEndTime: value)),
                              ),
                            ),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Click video to play or pause'),
                              subtitle: const Text(
                                'Single-click always toggles playback.',
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                  'Double-click video for fullscreen'),
                              value: _settings.doubleClickFullscreen,
                              onChanged: (value) => unawaited(
                                _save((current) => current.copyWith(
                                    doubleClickFullscreen: value)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        context,
                        'Home',
                        Icons.home_outlined,
                        Column(
                          children: <Widget>[
                            for (final shelf in _homeShelves.order)
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(shelf.label),
                                      value:
                                          _homeShelves.visible.contains(shelf),
                                      onChanged: (visible) {
                                        unawaited(
                                          _saveHomeShelves(
                                            (current) {
                                              final next = current.visible.toSet();
                                              if (visible) {
                                                next.add(shelf);
                                              } else {
                                                next.remove(shelf);
                                              }
                                              return current.copyWith(visible: next);
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Move ${shelf.label} up',
                                    onPressed: _homeShelves.order.first == shelf
                                        ? null
                                        : () => _moveHomeShelf(shelf, -1),
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: 'Move ${shelf.label} down',
                                    onPressed: _homeShelves.order.last == shelf
                                        ? null
                                        : () => _moveHomeShelf(shelf, 1),
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                ],
                              ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => unawaited(
                                  _saveHomeShelves(
                                    (current) => current.copyWith(
                                      order:
                                          HomeShelfPreferences.defaults.order,
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.restart_alt),
                                label: const Text('Restore default Home order'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        context,
                        'Keyboard & mouse',
                        Icons.keyboard_outlined,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Left/Right or J/L seeks by the selected interval. K or Space toggles playback; M toggles mute.',
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                  'Mouse wheel changes player volume'),
                              value: _settings.mouseWheelVolume,
                              onChanged: (value) => unawaited(
                                _save((current) => current.copyWith(
                                    mouseWheelVolume: value)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        context,
                        'Audio & subtitles',
                        Icons.subtitles_outlined,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Language and subtitle defaults are saved with your Jellyfin profile.',
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              child: const Text('Manage profile preferences'),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        context,
                        'Data & backup',
                        Icons.import_export,
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: _export,
                              icon: const Icon(Icons.copy),
                              label: const Text('Export UI settings'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _import,
                              icon: const Icon(Icons.paste),
                              label: const Text('Import UI settings'),
                            ),
                            TextButton.icon(
                              onPressed: _reset,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset UI settings'),
                            ),
                          ],
                        ),
                      ),
                      _section(
                        context,
                        'About & diagnostics',
                        Icons.info_outline,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('Nautilus'),
                            Text('Platform: ${_platformLabel()}'),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text:
                                        'Nautilus\nPlatform: ${_platformLabel()}',
                                  ),
                                );
                                if (mounted)
                                  _message('Diagnostic summary copied.');
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy diagnostic summary'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      );

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    Widget child,
  ) =>
      Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: <Widget>[
                  Icon(icon),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

String _appearanceLabel(AppearanceMode mode) => switch (mode) {
      AppearanceMode.system => 'System',
      AppearanceMode.light => 'Light',
      AppearanceMode.dark => 'Dark',
      AppearanceMode.oled => 'OLED',
    };

String _platformLabel() => kIsWeb ? 'Web' : defaultTargetPlatform.name;

class _SettingsImportDialog extends StatefulWidget {
  const _SettingsImportDialog();
  @override
  State<_SettingsImportDialog> createState() => _SettingsImportDialogState();
}

class _SettingsImportDialogState extends State<_SettingsImportDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Import UI settings'),
        content: TextField(
            controller: _controller,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
                hintText: 'Paste a Nautilus UI settings export')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: const Text('Import')),
        ],
      );
}
