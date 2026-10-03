import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/player_chrome_controller.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/track_selector_sheet.dart';
import 'package:rodplayer/ui/player/playback_settings_sheet.dart';
import 'package:rodplayer/ui/widgets/compatibility_panel.dart';
import 'package:window_manager/window_manager.dart';

abstract interface class PlayerFullscreenWindow {
  Future<bool> isFullscreen();
  Future<bool> isMaximized();
  Future<void> setFullscreen(bool value);
  Future<void> maximize();
}

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    this.engine,
    this.surface,
    this.activeBinding,
    this.commandController,
    required this.client,
    this.itemId,
    this.onUserDataChanged,
    this.logicalSession,
    this.reporter,
    this.onRenegotiateSubtitle,
    this.onPlaybackError,
    this.onToggleFullscreen,
    this.fullscreenWindow,
    this.loadMediaSources,
    this.onSelectMediaSource,
  }) : assert(activeBinding != null || (engine != null && surface != null));

  final PlaybackEngine? engine;
  final PlaybackVideoSurface? surface;
  final ValueListenable<PlaybackRuntimeViewBinding>? activeBinding;
  final PlaybackCommandController? commandController;
  final JellyfinApiClient client;
  final String? itemId;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final LogicalPlaybackSession? logicalSession;
  final PlaybackSessionReporter? reporter;
  final SubtitleRenegotiator? onRenegotiateSubtitle;
  final Future<void> Function()? onPlaybackError;
  @visibleForTesting
  final Future<void> Function()? onToggleFullscreen;
  @visibleForTesting
  final PlayerFullscreenWindow? fullscreenWindow;
  final Future<List<MediaSourceInfo>> Function()? loadMediaSources;
  final Future<void> Function(MediaSourceInfo source)? onSelectMediaSource;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

enum _PlayerMoreAction {
  tracks,
  info,
  settings,
  favorite,
  unfavorite,
  watched,
  unwatched,
}

bool _supportsUserDataActions(JellyfinLibraryItem item) =>
    item.id.isNotEmpty &&
    const <JellyfinItemKind>{
      JellyfinItemKind.movie,
      JellyfinItemKind.series,
      JellyfinItemKind.episode,
      JellyfinItemKind.audio,
    }.contains(item.kind);

class _VideoPlayerViewState extends State<VideoPlayerView> {
  Timer? _keepAlive;
  late final PlayerChromeController _chrome;
  final FocusNode _playerFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _backFocus = FocusNode(debugLabel: 'player-back');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player-play');
  final FocusNode _tracksFocus = FocusNode(debugLabel: 'player-tracks');
  final FocusNode _statsFocus = FocusNode(debugLabel: 'player-stats');
  final FocusNode _settingsFocus = FocusNode(debugLabel: 'player-settings');
  bool _disposed = false;
  bool _fullscreenToggleInFlight = false;
  bool _reportInFlight = false;
  bool _exitInFlight = false;
  bool _reportingStopped = false;
  bool _userDataBusy = false;
  bool get _controlsVisible => _chrome.visible;
  bool _sheetOpen = false;
  bool _pointerOverControls = false;
  bool _scrubbing = false;
  bool _skipBusy = false;
  int _seekIntervalSeconds = 10;
  int _autoHideSeconds = 3;
  bool _showEndTime = true;
  bool _doubleClickFullscreen = true;
  bool _isFullscreen = false;
  bool? _wasMaximizedBeforeFullscreen;
  bool _mouseWheelVolume = true;
  PlayerUiSettings _playerSettings = PlayerUiSettings.defaults;
  double _lastNonzeroVolume = 80;
  PlaybackSessionReporter? _reporter;
  JellyfinLibraryItem? _playerItem;
  late PlaybackEngine _engine;
  late PlaybackVideoSurface _surface;
  var _bound = false;

  @override
  void initState() {
    super.initState();
    _chrome = PlayerChromeController(
      hideAfter: Duration(seconds: _autoHideSeconds),
    )..addListener(_chromeChanged);
    FocusManager.instance.addListener(_focusedNodeChanged);
    widget.activeBinding?.addListener(_activeBindingChanged);
    _bind(_bindingEngine, _bindingSurface);
    final logicalSession = widget.logicalSession;
    if (logicalSession != null) {
      _reporter = widget.reporter ??
          PlaybackReporter(client: widget.client, session: logicalSession);
      unawaited(_reporter!.started(logicalSession.position > Duration.zero
          ? logicalSession.position
          : _engine.position));
    }
    _keepAlive = Timer.periodic(
        const Duration(seconds: 10), (_) => unawaited(_report()));
    _syncControls();
    unawaited(_loadUiSettings());
  }

  Future<void> _loadUiSettings() async {
    try {
      final settings = await PlayerUiSettings.load();
      if (!mounted || _disposed) return;
      setState(() {
        _playerSettings = settings;
        _seekIntervalSeconds = settings.seekIntervalSeconds;
        _autoHideSeconds = settings.autoHideSeconds;
        _showEndTime = settings.showEndTime;
        _doubleClickFullscreen = settings.doubleClickFullscreen;
        _mouseWheelVolume = settings.mouseWheelVolume;
      });
      _syncControls();
    } on Object {
      // Missing local preferences safely use deterministic defaults.
    }
  }

  PlaybackEngine get _bindingEngine =>
      widget.activeBinding?.value.engine ?? widget.engine!;
  PlaybackVideoSurface get _bindingSurface =>
      widget.activeBinding?.value.surface ?? widget.surface!;

  void _activeBindingChanged() {
    final binding = widget.activeBinding?.value;
    if (_disposed || binding?.engine == null || binding?.surface == null) {
      return;
    }
    _bind(binding!.engine!, binding.surface!);
    final reporter = _reporter;
    if (reporter != null) {
      unawaited(reporter.synchronize(binding.engine!.position));
    }
  }

  void _bind(PlaybackEngine engine, PlaybackVideoSurface surface) {
    if (_bound && identical(_engine, engine)) {
      if (identical(_surface, surface)) return;
      _surface = surface;
      if (mounted) setState(() {});
      return;
    }
    if (_bound) {
      _engine.error.removeListener(_showPlaybackError);
      _engine.playing.removeListener(_reportingStateChanged);
      _engine.buffering.removeListener(_reportingStateChanged);
    }
    _engine = engine;
    _surface = surface;
    if (engine.volume.value > 0) _lastNonzeroVolume = engine.volume.value;
    _bound = true;
    _engine.error.addListener(_showPlaybackError);
    _engine.playing.addListener(_reportingStateChanged);
    _engine.buffering.addListener(_reportingStateChanged);
    _syncControls();
    if (mounted) setState(() {});
  }

  void _reportingStateChanged() {
    if (!_disposed && !_engine.playing.value && !_engine.buffering.value) {
      _keepAlive?.cancel();
      _keepAlive = null;
    } else if (!_disposed && _keepAlive == null) {
      _keepAlive = Timer.periodic(
          const Duration(seconds: 10), (_) => unawaited(_report()));
    }
    _syncControls();
  }

  void _syncControls() {
    if (_disposed) return;
    _chrome.configureHideAfter(Duration(seconds: _autoHideSeconds));
    _chrome.playbackStateChanged(
      playing: _engine.playing.value,
      buffering: _engine.buffering.value,
    );
    _chrome.setHeld(PlayerChromeHold.modal, _sheetOpen);
    _chrome.setHeld(PlayerChromeHold.scrubbing, _scrubbing);
    _chrome.setHeld(
      PlayerChromeHold.interaction,
      _pointerOverControls || _hasPlayerControlFocus,
    );
  }

  bool get _hasPlayerControlFocus {
    if (_backFocus.hasFocus ||
        _playFocus.hasFocus ||
        _tracksFocus.hasFocus ||
        _statsFocus.hasFocus ||
        _settingsFocus.hasFocus) {
      return true;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    return focusContext?.findAncestorWidgetOfExactType<_Hud>() != null ||
        focusContext?.findAncestorWidgetOfExactType<_PlayerTopBar>() != null;
  }

  void _focusedNodeChanged() {
    if (!_disposed) _syncControls();
  }

  void _setPointerOverControls(bool value) {
    if (_pointerOverControls == value) return;
    _pointerOverControls = value;
    _syncControls();
    if (value) _showControls(mode: PlayerInputMode.pointer);
  }

  void _hideControls() {
    if (_disposed) return;
    _chrome.hide();
    if (!_chrome.visible && mounted) _playerFocus.requestFocus();
  }

  void _showControls({
    bool focusPlay = false,
    PlayerInputMode? mode,
  }) {
    _chrome.activity(mode: mode ?? _chrome.inputMode);
    if (focusPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _controlsVisible && _playFocus.context != null) {
          _playFocus.requestFocus();
        }
      });
    }
  }

  void _setSheetOpen(bool value) {
    _sheetOpen = value;
    _chrome.setHeld(PlayerChromeHold.modal, value);
    if (!value) _showControls();
  }

  void _setScrubbing(bool value) {
    _scrubbing = value;
    _chrome.setHeld(PlayerChromeHold.scrubbing, value);
    _showControls();
  }

  void _chromeChanged() {
    if (mounted && !_disposed) setState(() {});
  }

  PlayerInputMode _inputModeFor(KeyEvent event) => switch (event.deviceType) {
        ui.KeyEventDeviceType.directionalPad ||
        ui.KeyEventDeviceType.gamepad ||
        ui.KeyEventDeviceType.joystick ||
        ui.KeyEventDeviceType.hdmi => PlayerInputMode.dpad,
        _ => PlayerInputMode.keyboard,
      };

  PlaybackCommandOrigin _commandOriginFor(PlayerInputMode mode) =>
      switch (mode) {
        PlayerInputMode.dpad => PlaybackCommandOrigin.dpad,
        PlayerInputMode.keyboard => PlaybackCommandOrigin.keyboard,
        _ => PlaybackCommandOrigin.localUi,
      };

  PlayerInputMode _inputModeForOrigin(PlaybackCommandOrigin origin) =>
      switch (origin) {
        PlaybackCommandOrigin.dpad => PlayerInputMode.dpad,
        PlaybackCommandOrigin.keyboard || PlaybackCommandOrigin.systemMedia =>
          PlayerInputMode.keyboard,
        _ => _chrome.inputMode,
      };

  void _onPointerDown(PointerDownEvent event) {
    final touch = event.kind == ui.PointerDeviceKind.touch ||
        event.kind == ui.PointerDeviceKind.stylus ||
        event.kind == ui.PointerDeviceKind.invertedStylus;
    _chrome.setInputMode(
      touch ? PlayerInputMode.touch : PlayerInputMode.pointer,
    );
  }

  Future<void> _openPlaybackSettings() async {
    _setSheetOpen(true);
    try {
      await PlaybackSettingsSheet.show(
        context,
        settings: _playerSettings,
        activeBinding: widget.activeBinding,
        commandController: widget.commandController,
        loadMediaSources: widget.loadMediaSources,
        onSelectMediaSource: widget.onSelectMediaSource,
        onChanged: (settings) {
          if (!mounted) return;
          setState(() {
            _playerSettings = settings;
            _seekIntervalSeconds = settings.seekIntervalSeconds;
            _autoHideSeconds = settings.autoHideSeconds;
            _showEndTime = settings.showEndTime;
            _doubleClickFullscreen = settings.doubleClickFullscreen;
            _mouseWheelVolume = settings.mouseWheelVolume;
          });
          _syncControls();
        },
      );
    } finally {
      if (mounted) {
        _setSheetOpen(false);
        if (_settingsFocus.context != null) _settingsFocus.requestFocus();
      }
    }
  }

  Future<void> _openPlayerMoreActions() async {
    _setSheetOpen(true);
    try {
      final item = await _loadPlayerItem();
      if (!mounted) return;
      final binding = widget.activeBinding?.value;
      final action = await showModalBottomSheet<_PlayerMoreAction>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (item != null && _supportsUserDataActions(item)) ...[
              ListTile(
                leading: Icon(item.userData.isFavorite
                    ? Icons.favorite_border
                    : Icons.favorite),
                title: Text(item.userData.isFavorite
                    ? 'Remove from favorites'
                    : 'Add to favorites'),
                onTap: () => Navigator.pop(
                  sheetContext,
                  item.userData.isFavorite
                      ? _PlayerMoreAction.unfavorite
                      : _PlayerMoreAction.favorite,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                    item.userData.played ? 'Mark unwatched' : 'Mark watched'),
                onTap: () => Navigator.pop(
                  sheetContext,
                  item.userData.played
                      ? _PlayerMoreAction.unwatched
                      : _PlayerMoreAction.watched,
                ),
              ),
            ],
            if ((binding?.tracks?.audioTracks.length ?? 0) > 1 ||
                binding?.tracks?.subtitleTracks.isNotEmpty == true ||
                binding?.capabilities.subtitleTrackSwitching ==
                    CapabilitySupport.supported)
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Audio & subtitles'),
                onTap: () =>
                    Navigator.pop(sheetContext, _PlayerMoreAction.tracks),
              ),
            if (binding?.plan != null && widget.logicalSession != null)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Playback info'),
                onTap: () =>
                    Navigator.pop(sheetContext, _PlayerMoreAction.info),
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Playback settings'),
              onTap: () =>
                  Navigator.pop(sheetContext, _PlayerMoreAction.settings),
            ),
          ]),
        ),
      );
      if (!mounted || action == null) return;
      switch (action) {
        case _PlayerMoreAction.tracks:
          final controls = widget.activeBinding;
          if (controls == null) return;
          await TrackSelectorSheet.show(
            context,
            controls: controls,
            onRenegotiateSubtitle: widget.onRenegotiateSubtitle,
            commandController: widget.commandController,
          );
          break;
        case _PlayerMoreAction.info:
          final controls = widget.activeBinding;
          final session = widget.logicalSession;
          if (controls == null || session == null) return;
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => ValueListenableBuilder<PlaybackRuntimeViewBinding>(
              valueListenable: controls,
              builder: (_, current, __) => CompatibilityPanel(
                snapshot: current.plan == null
                    ? null
                    : PlaybackDiagnosticsSnapshot.fromPlan(
                        plan: current.plan!,
                        runtimeId: current.runtimeId,
                        selectedAudioStreamIndex: session.selectedAudio,
                        selectedSubtitleStreamIndex: session.selectedSubtitle,
                      ),
                runtimeDiagnostics: current.capabilities.diagnostics,
              ),
            ),
          );
          break;
        case _PlayerMoreAction.settings:
          await _openPlaybackSettings();
          break;
        case _PlayerMoreAction.favorite:
          await _setPlayerFavorite(item!, true);
          break;
        case _PlayerMoreAction.unfavorite:
          await _setPlayerFavorite(item!, false);
          break;
        case _PlayerMoreAction.watched:
          await _setPlayerPlayed(item!, true);
          break;
        case _PlayerMoreAction.unwatched:
          await _setPlayerPlayed(item!, false);
          break;
      }
    } finally {
      if (mounted) {
        _setSheetOpen(false);
        if (_playFocus.context != null) _playFocus.requestFocus();
      }
    }
  }

  Future<JellyfinLibraryItem?> _loadPlayerItem() async {
    final cached = _playerItem;
    if (cached != null) return cached;
    final itemId = widget.itemId;
    if (itemId == null || itemId.isEmpty) return null;
    try {
      final item = await widget.client.getItem(itemId);
      if (!mounted || _disposed) return null;
      _playerItem = item;
      return item;
    } on Object {
      return null;
    }
  }

  Future<void> _setPlayerFavorite(
      JellyfinLibraryItem item, bool isFavorite) async {
    if (_userDataBusy) return;
    setState(() => _userDataBusy = true);
    try {
      await widget.client.setFavorite(itemId: item.id, isFavorite: isFavorite);
      if (!mounted || _disposed) return;
      final change =
          JellyfinUserDataChange(itemId: item.id, isFavorite: isFavorite);
      _playerItem = item.withUserDataChange(change);
      widget.onUserDataChanged?.call(change);
    } on Object {
      if (mounted) _showActionError('Unable to update favorite');
    } finally {
      if (mounted) setState(() => _userDataBusy = false);
    }
  }

  Future<void> _setPlayerPlayed(JellyfinLibraryItem item, bool played) async {
    if (_userDataBusy) return;
    setState(() => _userDataBusy = true);
    try {
      await widget.client.setPlayed(itemId: item.id, played: played);
      if (!mounted || _disposed) return;
      final change = JellyfinUserDataChange(
          itemId: item.id,
          played: played,
          playbackProgressMayHaveChanged: true);
      _playerItem = item.withUserDataChange(change);
      widget.onUserDataChanged?.call(change);
    } on Object {
      if (mounted) _showActionError('Unable to update watched state');
    } finally {
      if (mounted) setState(() => _userDataBusy = false);
    }
  }

  void _hideOnPointerExit() {
    if (_sheetOpen ||
        _scrubbing ||
        _pointerOverControls ||
        !_engine.playing.value ||
        _engine.buffering.value) {
      return;
    }
    _hideControls();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_mouseWheelVolume ||
        event is! PointerScrollEvent ||
        _sheetOpen ||
        _scrubbing ||
        event.scrollDelta.dy == 0) {
      return;
    }
    _showControls();
    final delta = event.scrollDelta.dy < 0 ? 5.0 : -5.0;
    unawaited(_setVolume((_engine.volume.value + delta).clamp(0, 100)));
  }

  bool _isCurrentEngine(
          PlaybackEngine engine, PlaybackRuntimeViewBinding? binding) =>
      mounted &&
      identical(_engine, engine) &&
      (binding == null || identical(widget.activeBinding?.value, binding));

  void _showActionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _togglePlayback({
    PlaybackCommandOrigin origin = PlaybackCommandOrigin.localUi,
  }) async {
    final commands = widget.commandController;
    if (commands != null) {
      final result = await commands.dispatchCurrent(
        command: const TogglePlayPauseCommand(),
        origin: origin,
      );
      if (result.status != PlaybackCommandStatus.executed) {
        _showActionError('Unable to change playback state');
      }
      return;
    }
    await _engine.playOrPause();
  }

  Future<bool> _seekTo(Duration target, {bool showError = true}) async {
    final engine = _engine;
    final binding = widget.activeBinding?.value;
    final session = widget.logicalSession;
    _showControls();
    try {
      final commands = widget.commandController;
      if (commands != null) {
        final result = await commands.dispatchCurrent(
          command: SeekAbsoluteCommand(target),
          origin: PlaybackCommandOrigin.localUi,
        );
        if (result.status != PlaybackCommandStatus.executed) {
          throw StateError('Seek command was not executed.');
        }
      } else {
        await engine.seek(target);
      }
      if (_isCurrentEngine(engine, binding) &&
          identical(widget.logicalSession, session)) {
        if (session != null) session.position = engine.position;
        _showControls();
        return true;
      }
      return false;
    } on Object {
      if (showError && _isCurrentEngine(engine, binding)) {
        _showActionError('Unable to seek');
      }
      return false;
    }
  }

  Future<void> _seekBy(
    Duration delta, {
    PlaybackCommandOrigin origin = PlaybackCommandOrigin.localUi,
  }) async {
    final commands = widget.commandController;
    if (commands != null) {
      final result = await commands.dispatchCurrent(
        command: SeekRelativeCommand(delta),
        origin: origin,
      );
      if (result.status != PlaybackCommandStatus.executed) {
        _showActionError('Unable to seek');
      }
      _showControls(mode: _inputModeForOrigin(origin));
      return;
    }
    final engine = _engine;
    final position = engine.position + delta;
    final duration = engine.duration;
    final target = position < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && position > duration
            ? duration
            : position;
    await _seekTo(target);
  }

  Future<void> _toggleMute() async {
    final engine = _engine;
    final binding = widget.activeBinding?.value;
    final current = engine.volume.value;
    try {
      await _setVolume(current <= 0 ? _lastNonzeroVolume : 0);
      if (_isCurrentEngine(engine, binding) && current > 0) {
        _lastNonzeroVolume = current;
      }
    } on Object {
      if (_isCurrentEngine(engine, binding)) {
        _showActionError('Unable to change volume');
      }
    }
  }

  Future<void> _setVolume(double value) async {
    final engine = _engine;
    final binding = widget.activeBinding?.value;
    try {
      final commands = widget.commandController;
      if (commands != null) {
        final result = await commands.dispatchCurrent(
          command: SetVolumeCommand(value),
          origin: PlaybackCommandOrigin.localUi,
        );
        if (result.status != PlaybackCommandStatus.executed) {
          throw StateError('Volume command was not executed.');
        }
      } else {
        await engine.setVolume(value);
      }
      if (_isCurrentEngine(engine, binding) && value > 0) {
        _lastNonzeroVolume = value;
      }
    } on Object {
      if (_isCurrentEngine(engine, binding)) {
        _showActionError('Unable to change volume');
      }
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreenToggleInFlight) return;
    _fullscreenToggleInFlight = true;
    try {
      final injectedWindow = widget.fullscreenWindow;
      if (injectedWindow != null) {
        final currentlyFullscreen = await injectedWindow.isFullscreen();
        if (currentlyFullscreen) {
          final wasMaximized = _wasMaximizedBeforeFullscreen;
          await injectedWindow.setFullscreen(false);
          if (wasMaximized == true && !await injectedWindow.isMaximized()) {
            await injectedWindow.maximize();
          }
          _wasMaximizedBeforeFullscreen = null;
        } else {
          _wasMaximizedBeforeFullscreen = await injectedWindow.isMaximized();
          await injectedWindow.setFullscreen(true);
        }
        final actualFullscreen = await injectedWindow.isFullscreen();
        if (mounted) setState(() => _isFullscreen = actualFullscreen);
        return;
      }
      final testCallback = widget.onToggleFullscreen;
      if (testCallback != null) {
        await testCallback();
        if (mounted) setState(() => _isFullscreen = !_isFullscreen);
        return;
      }
      if (kIsWeb ||
          !const <TargetPlatform>{
            TargetPlatform.linux,
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }.contains(defaultTargetPlatform)) {
        return;
      }
      final isFullscreen = await windowManager.isFullScreen();
      if (isFullscreen) {
        await _leavePlatformFullscreen();
      } else {
        await _enterPlatformFullscreen();
      }
      final actualFullscreen = await windowManager.isFullScreen();
      if (mounted) setState(() => _isFullscreen = actualFullscreen);
    } on Object {
      if (mounted) _showActionError('Unable to change fullscreen');
    } finally {
      _fullscreenToggleInFlight = false;
    }
  }

  Future<bool> _actualFullscreenState() async {
    final injectedWindow = widget.fullscreenWindow;
    if (injectedWindow != null) return injectedWindow.isFullscreen();
    if (widget.onToggleFullscreen != null) return _isFullscreen;
    if (kIsWeb ||
        !const <TargetPlatform>{
          TargetPlatform.linux,
          TargetPlatform.macOS,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform)) {
      return false;
    }
    return windowManager.isFullScreen();
  }

  bool get _supportsFullscreen =>
      widget.fullscreenWindow != null ||
      (!kIsWeb &&
          const <TargetPlatform>{
            TargetPlatform.linux,
            TargetPlatform.macOS,
            TargetPlatform.windows,
          }.contains(defaultTargetPlatform));

  Future<void> _handleEscape() async {
    if (await _actualFullscreenState()) {
      await _toggleFullscreen();
    } else {
      await _stopReportingAndPop();
    }
  }

  Future<void> _skipMarker(PlaybackMarker marker) async {
    if (_skipBusy) return;
    final binding = widget.activeBinding?.value;
    final engine = binding?.engine;
    final session = widget.logicalSession;
    if (engine == null || session == null) return;
    setState(() => _skipBusy = true);
    try {
      final seeked = await _seekTo(marker.end, showError: false);
      if (!seeked) throw StateError('Skip seek was not completed.');
      if (_isCurrentEngine(engine, binding) &&
          identical(widget.logicalSession, session)) {
        session.position = marker.end;
      }
    } on Object {
      if (_isCurrentEngine(engine, binding) &&
          identical(widget.logicalSession, session)) {
        _showActionError('Unable to skip this segment');
      }
    } finally {
      if (mounted) setState(() => _skipBusy = false);
    }
  }

  void _showPlaybackError() {
    final source = _engine;
    final message = source.error.value;
    final capturedBinding = widget.activeBinding?.value;
    bool isCurrent() =>
        mounted &&
        identical(_engine, source) &&
        source.error.value == message &&
        (capturedBinding == null ||
            identical(widget.activeBinding?.value, capturedBinding));
    if (!mounted || message == null || message.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isCurrent()) return;
      unawaited(widget.onPlaybackError?.call() ?? Future<void>.value());
      final theme = Theme.of(context).extension<RodPlayerTheme>() ??
          const RodPlayerTheme();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Playback error: $message',
                style: TextStyle(color: theme.textPrimary)),
            backgroundColor: theme.obsidianRaised,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
                label: 'RETRY',
                textColor: theme.accentBright,
                onPressed: () {
                  if (isCurrent()) {
                    unawaited(
                        widget.onPlaybackError?.call() ?? Future<void>.value());
                  }
                })));
    });
  }

  Future<void> _report() async {
    if (_disposed ||
        _reportInFlight ||
        !_engine.playing.value ||
        _engine.buffering.value) {
      return;
    }
    _reportInFlight = true;
    try {
      final reporter = _reporter;
      if (reporter != null) {
        final position = _engine.position;
        widget.logicalSession?.position = position;
        await reporter.progress(position, _engine.duration);
      }
    } finally {
      _reportInFlight = false;
    }
  }

  Future<void> _enterPlatformFullscreen() async {
    _wasMaximizedBeforeFullscreen = await windowManager.isMaximized();
    try {
      await windowManager.setFullScreen(true);
    } on Object {
      _wasMaximizedBeforeFullscreen = null;
      rethrow;
    }
  }

  Future<void> _leavePlatformFullscreen() async {
    await windowManager.setFullScreen(false);
    final wasMaximized = _wasMaximizedBeforeFullscreen;
    _wasMaximizedBeforeFullscreen = null;
    if (wasMaximized == true && !await windowManager.isMaximized()) {
      await windowManager.maximize();
    }
  }

  Future<void> _stopReportingAndPop() async {
    if (_exitInFlight || _reportingStopped || !Navigator.of(context).canPop()) {
      return;
    }
    _exitInFlight = true;
    _keepAlive?.cancel();
    _keepAlive = null;
    final position = _engine.position;
    widget.logicalSession?.position = position;
    try {
      await _reporter?.stopped(position);
    } finally {
      _exitInFlight = false;
    }
    if (!mounted) return;
    setState(() => _reportingStopped = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activeBinding, widget.activeBinding)) {
      oldWidget.activeBinding?.removeListener(_activeBindingChanged);
      widget.activeBinding?.addListener(_activeBindingChanged);
    }
    if (widget.activeBinding == null) {
      _bind(widget.engine!, widget.surface!);
    } else {
      _activeBindingChanged();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    FocusManager.instance.removeListener(_focusedNodeChanged);
    if (_isFullscreen &&
        widget.onToggleFullscreen == null &&
        widget.fullscreenWindow == null) {
      unawaited(_leavePlatformFullscreen());
    }
    widget.activeBinding?.removeListener(_activeBindingChanged);
    _engine.error.removeListener(_showPlaybackError);
    _engine.playing.removeListener(_reportingStateChanged);
    _engine.buffering.removeListener(_reportingStateChanged);
    _keepAlive?.cancel();
    _chrome.removeListener(_chromeChanged);
    _chrome.dispose();
    _playerFocus.dispose();
    _playFocus.dispose();
    _backFocus.dispose();
    _tracksFocus.dispose();
    _statsFocus.dispose();
    _settingsFocus.dispose();
    if (!_reportingStopped) {
      final position = _engine.position;
      widget.logicalSession?.position = position;
      unawaited(_reporter?.stopped(position));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
        canPop: !_isFullscreen && (_reporter == null || _reportingStopped),
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_isFullscreen) {
            unawaited(_toggleFullscreen());
          } else {
            unawaited(_stopReportingAndPop());
          }
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            focusNode: _playerFocus,
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              final inputMode = _inputModeFor(event);
              final commandOrigin = _commandOriginFor(inputMode);
              if (key == LogicalKeyboardKey.escape) {
                unawaited(_handleEscape());
                return KeyEventResult.handled;
              }
              if (_playerFocus.hasPrimaryFocus &&
                  (key == LogicalKeyboardKey.arrowLeft ||
                      key == LogicalKeyboardKey.arrowRight)) {
                unawaited(_seekBy(Duration(
                  seconds: key == LogicalKeyboardKey.arrowLeft
                      ? -_seekIntervalSeconds
                      : _seekIntervalSeconds,
                ), origin: commandOrigin));
                _showControls(mode: inputMode);
                return KeyEventResult.handled;
              }
              final wake = key == LogicalKeyboardKey.arrowUp ||
                  key == LogicalKeyboardKey.arrowDown ||
                  key == LogicalKeyboardKey.arrowLeft ||
                  key == LogicalKeyboardKey.arrowRight ||
                  key == LogicalKeyboardKey.select ||
                  key == LogicalKeyboardKey.enter ||
                  key == LogicalKeyboardKey.numpadEnter;
              if (!_controlsVisible && wake) {
                _showControls(focusPlay: true, mode: inputMode);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.mediaPlayPause) {
                unawaited(
                  _togglePlayback(origin: PlaybackCommandOrigin.systemMedia),
                );
                _showControls(mode: inputMode);
                return KeyEventResult.handled;
              }
              final keyboard = HardwareKeyboard.instance;
              if (keyboard.isControlPressed ||
                  keyboard.isMetaPressed ||
                  keyboard.isAltPressed) {
                return KeyEventResult.ignored;
              }
              if (key == LogicalKeyboardKey.keyK) {
                unawaited(_togglePlayback(origin: commandOrigin));
                _showControls(mode: inputMode);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.keyJ) {
                unawaited(
                  _seekBy(
                    Duration(seconds: -_seekIntervalSeconds),
                    origin: commandOrigin,
                  ),
                );
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.keyL) {
                unawaited(
                  _seekBy(
                    Duration(seconds: _seekIntervalSeconds),
                    origin: commandOrigin,
                  ),
                );
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.keyM) {
                unawaited(_toggleMute());
                _showControls(mode: inputMode);
                return KeyEventResult.handled;
              }
              if (_playerFocus.hasPrimaryFocus &&
                  key == LogicalKeyboardKey.space) {
                unawaited(_togglePlayback(origin: commandOrigin));
                _showControls(mode: inputMode);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Listener(
                onPointerDown: _onPointerDown,
                onPointerSignal: _onPointerSignal,
                child: MouseRegion(
                  onHover: (_) => _showControls(),
                  onExit: (_) => _hideOnPointerExit(),
                  child: Stack(children: <Widget>[
                    Positioned.fill(child: _surface.build(context)),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          _showControls();
                          unawaited(_togglePlayback());
                        },
                        onDoubleTap: () {
                          if (_doubleClickFullscreen) {
                            unawaited(_toggleFullscreen());
                          }
                        },
                      ),
                    ),
                    if (widget.logicalSession != null ||
                        Navigator.of(context).canPop())
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: SafeArea(
                          bottom: false,
                          child: MouseRegion(
                            onEnter: (_) => _setPointerOverControls(true),
                            onHover: (_) => _showControls(),
                            onExit: (_) => _setPointerOverControls(false),
                            child: AnimatedOpacity(
                              opacity: _controlsVisible ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: ExcludeFocus(
                                excluding: !_controlsVisible,
                                child: ExcludeSemantics(
                                  excluding: !_controlsVisible,
                                  child: IgnorePointer(
                                    ignoring: !_controlsVisible,
                                    child: _PlayerTopBar(
                                      backFocus: _backFocus,
                                      canPop: Navigator.of(context).canPop(),
                                      session: widget.logicalSession,
                                      onBack: () => unawaited(
                                          Navigator.of(context).maybePop()),
                                      onActivity: _showControls,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: MouseRegion(
                            onEnter: (_) => _setPointerOverControls(true),
                            onHover: (_) => _showControls(),
                            onExit: (_) => _setPointerOverControls(false),
                            child: SafeArea(
                                top: false,
                                child: AnimatedOpacity(
                                    opacity: _controlsVisible ? 1 : 0,
                                    duration: const Duration(milliseconds: 180),
                                    child: ExcludeFocus(
                                        excluding: !_controlsVisible,
                                        child: ExcludeSemantics(
                                            excluding: !_controlsVisible,
                                            child: IgnorePointer(
                                                ignoring: !_controlsVisible,
                                                child: _Hud(
                                                    engine: _engine,
                                                    seekIntervalSeconds:
                                                        _seekIntervalSeconds,
                                                    showEndTime: _showEndTime,
                                                    isFullscreen: _isFullscreen,
                                                    supportsFullscreen:
                                                        _supportsFullscreen,
                                                    logicalSession:
                                                        widget.logicalSession,
                                                    activeBinding:
                                                        widget.activeBinding,
                                                    backFocus: _backFocus,
                                                    playFocus: _playFocus,
                                                    tracksFocus: _tracksFocus,
                                                    statsFocus: _statsFocus,
                                                    settingsFocus:
                                                        _settingsFocus,
                                                    onSeek: _seekBy,
                                                    onTogglePlayback: () =>
                                                        unawaited(
                                                            _togglePlayback()),
                                                    onToggleMute: () => unawaited(
                                                        _toggleMute()),
                                                    onSetVolume: (value) =>
                                                        unawaited(
                                                            _setVolume(value)),
                                                    onSeekTo: (position) =>
                                                        unawaited(
                                                            _seekTo(position)),
                                                    onScrubbing: _setScrubbing,
                                                    skipBusy: _skipBusy,
                                                    showSkip: _controlsVisible,
                                                    onSkip: (marker) => unawaited(
                                                        _skipMarker(marker)),
                                                    onActivity: _showControls,
                                                    onToggleFullscreen: () =>
                                                        unawaited(
                                                            _toggleFullscreen()),
                                                    onOpenSettings: () =>
                                                        unawaited(_openPlaybackSettings()),
                                                    onOpenMore: () => unawaited(_openPlayerMoreActions()),
                                                    onSheetOpen: _setSheetOpen,
                                                    onRenegotiateSubtitle: widget.onRenegotiateSubtitle)))))))),
                    if (_controlsVisible)
                      Positioned(
                          top: 20,
                          right: 20,
                          child: MouseRegion(
                              onEnter: (_) => _setPointerOverControls(true),
                              onHover: (_) => _showControls(),
                              onExit: (_) => _setPointerOverControls(false),
                              child: _StatusBar(engine: _engine))),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _SkipMarkerButton extends StatelessWidget {
  const _SkipMarkerButton({
    required this.binding,
    required this.session,
    required this.busy,
    required this.onSkip,
  });
  final ValueListenable<PlaybackRuntimeViewBinding> binding;
  final LogicalPlaybackSession session;
  final bool busy;
  final ValueChanged<PlaybackMarker> onSkip;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PlaybackMetadata>(
        valueListenable: session.metadataListenable,
        builder: (_, metadata, __) =>
            ValueListenableBuilder<PlaybackRuntimeViewBinding>(
          valueListenable: binding,
          builder: (_, binding, __) {
            final engine = binding.engine;
            if (engine == null) return const SizedBox.shrink();
            return ValueListenableBuilder<Duration>(
              valueListenable: engine.positionListenable,
              builder: (_, position, __) {
                PlaybackMarker? marker;
                for (final value in metadata.markers) {
                  if (value.skipAction != null &&
                      position >= value.start &&
                      position < value.end) {
                    marker = value;
                    break;
                  }
                }
                final action = marker?.skipAction;
                if (marker == null || action == null) {
                  return const SizedBox.shrink();
                }
                final actionableMarker = marker;
                return Semantics(
                  button: true,
                  label: action.label,
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => onSkip(actionableMarker),
                    icon: const Icon(Icons.skip_next),
                    label: Text(action.label),
                  ),
                );
              },
            );
          },
        ),
      );
}

class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar(
      {required this.backFocus,
      required this.canPop,
      required this.session,
      required this.onBack,
      required this.onActivity});
  final FocusNode backFocus;
  final bool canPop;
  final LogicalPlaybackSession? session;
  final VoidCallback onBack;
  final VoidCallback onActivity;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final title = session?.metadata.title;
    return DecoratedBox(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xB8000000), Colors.transparent])),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 20, 20),
        child: Row(children: <Widget>[
          if (canPop)
            FocusTraversalOrder(
              order: const NumericFocusOrder(0),
              child: Focus(
                onFocusChange: (focused) {
                  if (focused) onActivity();
                },
                child: IconButton(
                    focusNode: backFocus,
                    tooltip: 'Back',
                    onPressed: () {
                      onActivity();
                      onBack();
                    },
                    icon: Icon(Icons.arrow_back, color: theme.textPrimary)),
              ),
            ),
          if (title != null && title.trim().isNotEmpty)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          shadows: const <Shadow>[
                            Shadow(color: Colors.black, blurRadius: 8)
                          ])),
                  if (session?.activePlan.source.runTimeTicks case final ticks?)
                    Text(
                      _time(Duration(microseconds: ticks ~/ 10)),
                      style:
                          TextStyle(color: theme.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
          Text(
            MaterialLocalizations.of(context).formatTimeOfDay(
              TimeOfDay.fromDateTime(DateTime.now()),
            ),
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud(
      {required this.engine,
      required this.seekIntervalSeconds,
      required this.showEndTime,
      required this.isFullscreen,
      required this.supportsFullscreen,
      this.logicalSession,
      this.activeBinding,
      required this.backFocus,
      required this.playFocus,
      required this.tracksFocus,
      required this.statsFocus,
      required this.settingsFocus,
      required this.onSeek,
      required this.onTogglePlayback,
      required this.onToggleMute,
      required this.onSetVolume,
      required this.onSeekTo,
      required this.onScrubbing,
      required this.skipBusy,
      required this.showSkip,
      required this.onSkip,
      required this.onActivity,
      required this.onToggleFullscreen,
      required this.onOpenSettings,
      required this.onOpenMore,
      required this.onSheetOpen,
      this.onRenegotiateSubtitle});
  final PlaybackEngine engine;
  final int seekIntervalSeconds;
  final bool showEndTime;
  final bool isFullscreen;
  final bool supportsFullscreen;
  final LogicalPlaybackSession? logicalSession;
  final ValueListenable<PlaybackRuntimeViewBinding>? activeBinding;
  final FocusNode backFocus;
  final FocusNode playFocus;
  final FocusNode tracksFocus;
  final FocusNode statsFocus;
  final FocusNode settingsFocus;
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onSetVolume;
  final ValueChanged<Duration> onSeekTo;
  final ValueChanged<bool> onScrubbing;
  final bool skipBusy;
  final bool showSkip;
  final ValueChanged<PlaybackMarker> onSkip;
  final VoidCallback onActivity;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMore;
  final ValueChanged<bool> onSheetOpen;
  final SubtitleRenegotiator? onRenegotiateSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.56),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          _PlaybackTimeline(
              engine: engine,
              theme: theme,
              onSeekTo: onSeekTo,
              onActivity: onActivity,
              onScrubbing: onScrubbing),
          if (showSkip && activeBinding != null && logicalSession != null)
            FocusTraversalOrder(
                order: const NumericFocusOrder(0.75),
                child: _SkipMarkerButton(
                    binding: activeBinding!,
                    session: logicalSession!,
                    busy: skipBusy,
                    onSkip: onSkip)),
          const SizedBox(height: 2),
          LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final transport = <Widget>[
              _OsdButton(
                  order: 1,
                  tooltip: 'Rewind $seekIntervalSeconds seconds',
                  icon: seekIntervalSeconds == 10
                      ? Icons.replay_10
                      : Icons.replay,
                  onFocus: onActivity,
                  onPressed: () {
                    onActivity();
                    unawaited(onSeek(Duration(seconds: -seekIntervalSeconds)));
                  }),
              ValueListenableBuilder<bool>(
                  valueListenable: engine.playing,
                  builder: (_, isPlaying, __) => _OsdButton(
                      order: 2,
                      focusNode: playFocus,
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      icon: isPlaying ? Icons.pause : Icons.play_arrow,
                      iconSize: 28,
                      onFocus: onActivity,
                      onPressed: () {
                        onActivity();
                        onTogglePlayback();
                      })),
              _OsdButton(
                  order: 3,
                  tooltip: 'Forward $seekIntervalSeconds seconds',
                  icon: seekIntervalSeconds == 10
                      ? Icons.forward_10
                      : Icons.forward,
                  onFocus: onActivity,
                  onPressed: () {
                    onActivity();
                    unawaited(onSeek(Duration(seconds: seekIntervalSeconds)));
                  }),
            ];
            final endTime = _EstimatedEndTime(
              engine: engine,
              playbackRate: activeBinding?.value.advanced?.rate,
              visible: showEndTime,
            );
            Widget volume(double sliderWidth) => _VolumeControl(
                engine: engine,
                onActivity: onActivity,
                onScrubbing: onScrubbing,
                sliderWidth: sliderWidth,
                onToggleMute: onToggleMute,
                onSetVolume: onSetVolume);
            final fullscreenButton = supportsFullscreen
                ? _OsdButton(
                    order: 8,
                    tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                    icon:
                        isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    onFocus: onActivity,
                    onPressed: () {
                      onActivity();
                      onToggleFullscreen();
                    })
                : null;
            final moreButton = _OsdButton(
              order: 7,
              focusNode: compact ? null : settingsFocus,
              tooltip: compact ? 'More player actions' : 'Playback settings',
              icon: compact ? Icons.more_horiz : Icons.settings_outlined,
              onFocus: onActivity,
              onPressed: compact ? onOpenMore : onOpenSettings,
            );
            if (compact) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: transport),
                Row(children: [
                  endTime,
                  const Spacer(),
                  volume(56),
                  moreButton,
                  if (fullscreenButton != null) fullscreenButton,
                ]),
              ]);
            }
            return Row(
              children: <Widget>[
                ...transport,
                const Spacer(),
                endTime,
                const SizedBox(width: 8),
                volume(110),
                if (!compact && activeBinding != null)
                  ValueListenableBuilder<PlaybackRuntimeViewBinding>(
                    valueListenable: activeBinding!,
                    builder: (_, binding, __) {
                      final capabilities = binding.capabilities;
                      final available =
                          (binding.tracks?.audioTracks.length ?? 0) > 1 ||
                              (binding.tracks?.subtitleTracks.isNotEmpty ??
                                  false) ||
                              capabilities.subtitleTrackSwitching ==
                                  CapabilitySupport.supported;
                      if (!available) return const SizedBox.shrink();
                      return _OsdButton(
                          order: 4,
                          focusNode: tracksFocus,
                          tooltip: 'Audio and subtitles',
                          icon: Icons.tune,
                          onFocus: onActivity,
                          onPressed: () async {
                            onActivity();
                            onSheetOpen(true);
                            try {
                              await TrackSelectorSheet.show(context,
                                  controls: activeBinding!,
                                  onRenegotiateSubtitle: onRenegotiateSubtitle);
                            } finally {
                              if (context.mounted) {
                                onSheetOpen(false);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!context.mounted) return;
                                  if (tracksFocus.context != null) {
                                    tracksFocus.requestFocus();
                                  } else if (playFocus.context != null) {
                                    playFocus.requestFocus();
                                  }
                                });
                              }
                            }
                          });
                    },
                  ),
                if (!compact && activeBinding != null && logicalSession != null)
                  ValueListenableBuilder<PlaybackRuntimeViewBinding>(
                    valueListenable: activeBinding!,
                    builder: (_, binding, __) {
                      if (binding.plan == null) return const SizedBox.shrink();
                      return _OsdButton(
                          order: 5,
                          focusNode: statsFocus,
                          tooltip: 'Playback info',
                          icon: Icons.info_outline,
                          onFocus: onActivity,
                          onPressed: () async {
                            onActivity();
                            onSheetOpen(true);
                            try {
                              await showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => ValueListenableBuilder<
                                    PlaybackRuntimeViewBinding>(
                                  valueListenable: activeBinding!,
                                  builder: (_, current, __) =>
                                      CompatibilityPanel(
                                    snapshot: current.plan == null
                                        ? null
                                        : PlaybackDiagnosticsSnapshot.fromPlan(
                                            plan: current.plan!,
                                            runtimeId: current.runtimeId,
                                            selectedAudioStreamIndex:
                                                logicalSession!.selectedAudio,
                                            selectedSubtitleStreamIndex:
                                                logicalSession!
                                                    .selectedSubtitle,
                                          ),
                                    runtimeDiagnostics:
                                        current.capabilities.diagnostics,
                                  ),
                                ),
                              );
                            } finally {
                              if (context.mounted) {
                                onSheetOpen(false);
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (!context.mounted) return;
                                  if (activeBinding!.value.plan != null &&
                                      statsFocus.context != null) {
                                    statsFocus.requestFocus();
                                  } else if (playFocus.context != null) {
                                    playFocus.requestFocus();
                                  }
                                });
                              }
                            }
                          });
                    },
                  ),
                moreButton,
                if (fullscreenButton != null) fullscreenButton,
              ],
            );
          }),
        ]),
      ),
    );
  }
}

class _PlaybackTimeline extends StatefulWidget {
  const _PlaybackTimeline(
      {required this.engine,
      required this.theme,
      required this.onSeekTo,
      required this.onActivity,
      required this.onScrubbing});
  final PlaybackEngine engine;
  final RodPlayerTheme theme;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onActivity;
  final ValueChanged<bool> onScrubbing;

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
        valueListenable: widget.engine.positionListenable,
        builder: (_, position, __) => ValueListenableBuilder<Duration>(
          valueListenable: widget.engine.durationListenable,
          builder: (_, duration, __) {
            final knownDuration = duration > Duration.zero;
            final max =
                knownDuration ? duration.inMilliseconds.toDouble() : 0.0;
            final value = max == 0
                ? 0.0
                : (_dragValue ?? position.inMilliseconds.toDouble())
                    .clamp(0.0, max)
                    .toDouble();
            return Row(children: <Widget>[
              SizedBox(
                width: 66,
                child: Text(
                  _time(Duration(milliseconds: value.round())),
                  textAlign: TextAlign.left,
                  style:
                      TextStyle(color: widget.theme.textPrimary, fontSize: 13),
                ),
              ),
              Expanded(
                child: knownDuration
                    ? FocusTraversalOrder(
                        order: const NumericFocusOrder(0.5),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4.5,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 20),
                          ),
                          child: Semantics(
                            label: 'Playback position',
                            value:
                                '${_time(Duration(milliseconds: value.round()))} of ${_time(duration)}',
                            slider: true,
                            child: Slider(
                              min: 0,
                              max: max,
                              value: value,
                              onChangeStart: (_) {
                                widget.onScrubbing(true);
                                setState(() => _dragValue = value);
                              },
                              onChanged: (next) {
                                widget.onActivity();
                                setState(() => _dragValue = next);
                              },
                              onChangeEnd: (next) {
                                setState(() => _dragValue = null);
                                widget.onScrubbing(false);
                                widget.onSeekTo(
                                    Duration(milliseconds: next.round()));
                              },
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(height: 44),
              ),
              SizedBox(
                width: 66,
                child: Text(
                  knownDuration ? _time(duration) : '--:--',
                  textAlign: TextAlign.right,
                  style:
                      TextStyle(color: widget.theme.textPrimary, fontSize: 13),
                ),
              ),
            ]);
          },
        ),
      );
}

class _EstimatedEndTime extends StatelessWidget {
  const _EstimatedEndTime({
    required this.engine,
    required this.visible,
    this.playbackRate,
  });

  final PlaybackEngine engine;
  final bool visible;
  final ValueListenable<double>? playbackRate;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
        valueListenable: engine.positionListenable,
        builder: (context, position, _) => ValueListenableBuilder<Duration>(
          valueListenable: engine.durationListenable,
          builder: (context, duration, _) {
            final rate = playbackRate;
            if (rate == null) {
              return _endTimeLabel(context, position, duration, 1);
            }
            return ValueListenableBuilder<double>(
              valueListenable: rate,
              builder: (context, value, _) =>
                  _endTimeLabel(context, position, duration, value),
            );
          },
        ),
      );

  Widget _endTimeLabel(
      BuildContext context, Duration position, Duration duration, double rate) {
    if (!visible ||
        duration <= position ||
        position < Duration.zero ||
        !rate.isFinite ||
        rate <= 0) {
      return const SizedBox.shrink();
    }
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final remainingMicros = (duration - position).inMicroseconds / rate;
    final finish =
        DateTime.now().add(Duration(microseconds: remainingMicros.round()));
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(finish));
    return Text('Ends $time',
        style: TextStyle(color: theme.textSecondary, fontSize: 12));
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl(
      {required this.engine,
      required this.onActivity,
      required this.onScrubbing,
      required this.sliderWidth,
      required this.onToggleMute,
      required this.onSetVolume});
  final PlaybackEngine engine;
  final VoidCallback onActivity;
  final ValueChanged<bool> onScrubbing;
  final double sliderWidth;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onSetVolume;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: engine.volume,
        builder: (_, volume, __) =>
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          _OsdButton(
              order: 3.5,
              tooltip: volume <= 0 ? 'Unmute' : 'Mute',
              icon: volume <= 0 ? Icons.volume_off : Icons.volume_up,
              onFocus: onActivity,
              onPressed: () {
                onActivity();
                onToggleMute();
              }),
          FocusTraversalOrder(
              order: const NumericFocusOrder(3.6),
              child: SizedBox(
                  width: sliderWidth,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                        value: volume.clamp(0, 100).toDouble(),
                        min: 0,
                        max: 100,
                        semanticFormatterCallback: (value) =>
                            'Volume ${value.round()} percent',
                        onChangeStart: (_) {
                          onScrubbing(true);
                          onActivity();
                        },
                        onChanged: (value) {
                          onActivity();
                          onSetVolume(value);
                        },
                        onChangeEnd: (_) => onScrubbing(false)),
                  ))),
        ]),
      );
}

String _time(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
}

class _OsdButton extends StatelessWidget {
  const _OsdButton(
      {required this.order,
      required this.tooltip,
      required this.icon,
      required this.onPressed,
      this.iconSize = 24,
      this.focusNode,
      this.onFocus});
  final double order;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (hasFocus) onFocus?.call();
        },
        child: Builder(
            builder: (context) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                      color: Focus.of(context).hasFocus
                          ? Colors.black.withValues(alpha: 0.42)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Focus.of(context).hasFocus
                              ? theme.accentBright
                              : Colors.transparent,
                          width: 1.5)),
                  child: Semantics(
                      button: true,
                      label: tooltip,
                      child: IconButton(
                          focusNode: focusNode,
                          tooltip: tooltip,
                          color: theme.artworkTextPrimary,
                          icon: Icon(icon, size: iconSize),
                          visualDensity: VisualDensity.compact,
                          constraints:
                              const BoxConstraints(minWidth: 48, minHeight: 48),
                          onPressed: onPressed)),
                )),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.engine});
  final PlaybackEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return StreamBuilder<String>(
        stream: engine.statuses,
        builder: (_, snapshot) {
          final message = snapshot.data;
          if (message == null || message.isEmpty) {
            return const SizedBox.shrink();
          }
          return DecoratedBox(
              decoration: BoxDecoration(
                  color: theme.obsidianRaised.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(theme.radiusMedium),
                  border: Border.all(
                      color: theme.accentBright.withValues(alpha: 0.8)),
                  boxShadow: theme.accentGlow),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Icon(Icons.info_outline,
                        color: theme.accentBright, size: 18),
                    const SizedBox(width: 10),
                    Flexible(
                        child: Text(message,
                            style: TextStyle(color: theme.accentBright),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis))
                  ])));
        });
  }
}
