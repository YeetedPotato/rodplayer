import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/settings/ui_settings_persistence.dart';

class PlaybackSettingsSheet extends StatefulWidget {
  const PlaybackSettingsSheet({
    required this.settings,
    required this.onChanged,
    this.activeBinding,
    this.commandController,
    this.loadMediaSources,
    this.onSelectMediaSource,
    super.key,
  });

  final PlayerUiSettings settings;
  final ValueChanged<PlayerUiSettings> onChanged;
  final ValueListenable<PlaybackRuntimeViewBinding>? activeBinding;
  final PlaybackCommandController? commandController;
  final Future<List<MediaSourceInfo>> Function()? loadMediaSources;
  final Future<void> Function(MediaSourceInfo source)? onSelectMediaSource;

  static Future<void> show(
    BuildContext context, {
    required PlayerUiSettings settings,
    required ValueChanged<PlayerUiSettings> onChanged,
    ValueListenable<PlaybackRuntimeViewBinding>? activeBinding,
    PlaybackCommandController? commandController,
    Future<List<MediaSourceInfo>> Function()? loadMediaSources,
    Future<void> Function(MediaSourceInfo source)? onSelectMediaSource,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaybackSettingsSheet(
          settings: settings,
          onChanged: onChanged,
          activeBinding: activeBinding,
          commandController: commandController,
          loadMediaSources: loadMediaSources,
          onSelectMediaSource: onSelectMediaSource,
        ),
      );

  @override
  State<PlaybackSettingsSheet> createState() => _PlaybackSettingsSheetState();
}

class _PlaybackSettingsSheetState extends State<PlaybackSettingsSheet> {
  late PlayerUiSettings _settings = widget.settings;
  Future<List<MediaSourceInfo>>? _sourcesFuture;
  bool _switchingSource = false;
  UiSettingsPersistence? _persistence;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    try {
      final store = await UiSettingsPersistence.acquire(
          await SharedPreferences.getInstance());
      if (!mounted) return;
      setState(() {
        _persistence = store;
        _settings = store.intent.player;
        _saving = store.isSaving;
        if (!store.baselineVerified) {
          _saveError = 'Stored playback settings could not be verified.';
        }
      });
      if (store.isSaving) {
        await store.whenSettled;
        if (!mounted) return;
        setState(() {
          _saving = false;
          _settings = store.baseline.player;
          if (!store.baselineVerified) {
            _saveError = 'Stored playback settings could not be verified.';
          }
        });
        if (store.baselineVerified) widget.onChanged(store.baseline.player);
      }
    } on Object {
      if (mounted)
        setState(() => _saveError = 'Unable to load playback settings.');
    }
  }

  void _loadSources() {
    final load = widget.loadMediaSources;
    if (load == null || _sourcesFuture != null) return;
    setState(() {
      _sourcesFuture = load();
    });
  }

  Future<void> _selectSource(MediaSourceInfo source) async {
    final select = widget.onSelectMediaSource;
    if (select == null || _switchingSource) return;
    setState(() => _switchingSource = true);
    try {
      await select(source);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to change video version.')),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingSource = false);
    }
  }

  Future<void> _save(PlayerUiSettings Function(PlayerUiSettings) update) async {
    final store = _persistence;
    if (store == null) return;
    try {
      final write = store.updatePlayer(update);
      setState(() {
        _settings = store.intent.player;
        _saving = true;
        _saveError = null;
      });
      final saved = await write;
      if (!mounted) return;
      setState(() {
        _saving = store.isSaving;
        _settings =
            store.isSaving ? store.intent.player : store.baseline.player;
        if (!saved)
          _saveError = store.baselineVerified
              ? 'Unable to save playback settings. Stored settings reloaded.'
              : 'Stored playback settings could not be verified.';
      });
      if (!store.isSaving && store.baselineVerified)
        widget.onChanged(store.baseline.player);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save playback settings.')),
        );
      }
    }
  }

  Future<void> _setRate(AdvancedPlaybackControls controls, double value) async {
    try {
      final commandController = widget.commandController;
      if (commandController == null) {
        await controls.setRate(value);
      } else {
        final result = await commandController.dispatchCurrent(
          command: SetPlaybackRateCommand(value),
          origin: PlaybackCommandOrigin.localUi,
        );
        if (!result.wasApplied) {
          throw StateError('Playback speed command was not applied');
        }
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to change playback speed.')),
        );
      }
    }
  }

  Widget _rateControl(AdvancedPlaybackControls? controls) {
    if (controls == null ||
        controls.capabilities.playbackRate != CapabilitySupport.supported) {
      return const SizedBox.shrink();
    }
    const rates = <double>[0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
    return ValueListenableBuilder<double>(
      valueListenable: controls.rate,
      builder: (_, current, __) => DropdownButtonFormField<double>(
        initialValue: rates.contains(current) ? current : 1,
        decoration: const InputDecoration(labelText: 'Playback speed'),
        items: rates
            .map((rate) => DropdownMenuItem<double>(
                  value: rate,
                  child: Text('${rate}x'),
                ))
            .toList(growable: false),
        onChanged: (rate) {
          if (rate != null) unawaited(_setRate(controls, rate));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Playback settings',
                    style: Theme.of(context).textTheme.titleLarge),
                if (_saving) const Text('Saving settings...'),
                if (_saveError != null) Text(_saveError!),
                const SizedBox(height: 12),
                if (widget.activeBinding != null)
                  ValueListenableBuilder<PlaybackRuntimeViewBinding>(
                    valueListenable: widget.activeBinding!,
                    builder: (_, binding, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _rateControl(binding.advanced),
                        if (binding.plan?.source != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Version & Quality'),
                                  subtitle: Text(
                                      'Current: ${_versionSummary(binding.plan!.source).split('\n').first}'),
                                  trailing: TextButton(
                                    onPressed: _switchingSource ||
                                            widget.loadMediaSources == null
                                        ? null
                                        : _loadSources,
                                    child: const Text('Change'),
                                  ),
                                ),
                                if (_sourcesFuture != null &&
                                    widget.loadMediaSources != null)
                                  FutureBuilder<List<MediaSourceInfo>>(
                                    future: _sourcesFuture,
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState !=
                                          ConnectionState.done) {
                                        return const LinearProgressIndicator();
                                      }
                                      if (snapshot.hasError) {
                                        return TextButton(
                                            onPressed: () => setState(() {
                                                  _sourcesFuture = widget
                                                      .loadMediaSources!();
                                                }),
                                            child: const Text(
                                                'Versions unavailable · Retry'));
                                      }
                                      final sources = snapshot.data ??
                                          const <MediaSourceInfo>[];
                                      return Column(
                                        children: [
                                          for (final source in sources)
                                            ListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                _versionSummary(source)
                                                    .split('\n')
                                                    .first,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              subtitle: Text(
                                                _versionSummary(source)
                                                    .split('\n')
                                                    .skip(1)
                                                    .join(' · '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              trailing: source.id ==
                                                      binding
                                                          .plan!.mediaSourceId
                                                  ? const Icon(Icons.check)
                                                  : null,
                                              enabled: !_switchingSource,
                                              onTap: source.id ==
                                                      binding
                                                          .plan!.mediaSourceId
                                                  ? null
                                                  : () => unawaited(
                                                      _selectSource(source)),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                DropdownButtonFormField<int>(
                  key: ValueKey('seek-${_settings.seekIntervalSeconds}'),
                  initialValue: _settings.seekIntervalSeconds,
                  decoration: const InputDecoration(labelText: 'Seek interval'),
                  items: const <int>[10, 15, 30]
                      .map((value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value seconds'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_save((settings) =>
                          settings.copyWith(seekIntervalSeconds: value)));
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('hide-${_settings.autoHideSeconds}'),
                  initialValue: _settings.autoHideSeconds,
                  decoration: const InputDecoration(
                    labelText: 'Controls hide after',
                  ),
                  items: const <int>[3, 5, 8]
                      .map((value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('$value seconds'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      unawaited(_save((settings) =>
                          settings.copyWith(autoHideSeconds: value)));
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show estimated end time'),
                  value: _settings.showEndTime,
                  onChanged: (value) => unawaited(_save(
                      (settings) => settings.copyWith(showEndTime: value))),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Click video to play or pause'),
                  subtitle: const Text('Single-click always toggles playback.'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Double-click video for fullscreen'),
                  value: _settings.doubleClickFullscreen,
                  onChanged: (value) => unawaited(_save((settings) =>
                      settings.copyWith(doubleClickFullscreen: value))),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mouse wheel changes volume'),
                  value: _settings.mouseWheelVolume,
                  onChanged: (value) => unawaited(_save((settings) =>
                      settings.copyWith(mouseWheelVolume: value))),
                ),
              ],
            ),
          ),
        ),
      );
}

String _versionSummary(MediaSourceInfo source) {
  final video = source.videoStreams.isEmpty ? null : source.videoStreams.first;
  final resolution = video?.width != null && video?.height != null
      ? _resolutionLabel(video!.width!, video.height!)
      : null;
  final name = '${source.raw['Name'] ?? ''}'.trim();
  final audio = source.audioStreams.isEmpty ? null : source.audioStreams.first;
  final primary = <String>[
    if (resolution != null) resolution,
    if (name.isNotEmpty) name,
  ];
  final secondary = <String>[
    if (video?.codec?.isNotEmpty == true) video!.codec!.toUpperCase(),
    if (video?.videoRangeType?.isNotEmpty == true &&
        video!.videoRangeType!.toLowerCase() != 'sdr')
      video.videoRangeType!,
    if (audio?.channels != null) '${audio!.channels} audio channels',
    if (source.bitrate != null && source.bitrate! > 0)
      '${(source.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
  ];
  final firstLine =
      primary.isEmpty ? 'Current server source' : primary.join(' · ');
  return secondary.isEmpty ? firstLine : '$firstLine\n${secondary.join(' · ')}';
}

String _resolutionLabel(int width, int height) => switch (height) {
      2160 => '4K',
      1440 => '1440p',
      1080 => '1080p',
      720 => '720p',
      576 => '576p',
      480 => '480p',
      _ => '${width}×$height',
    };
