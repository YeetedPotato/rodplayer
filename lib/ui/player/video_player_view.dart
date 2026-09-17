import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_diagnostics.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/track_selector_sheet.dart';
import 'package:rodplayer/ui/widgets/compatibility_panel.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    this.engine,
    this.surface,
    this.activeBinding,
    required this.client,
    this.itemId,
    this.logicalSession,
    this.onRenegotiateSubtitle,
  }) : assert(activeBinding != null || (engine != null && surface != null));

  final PlaybackEngine? engine;
  final PlaybackVideoSurface? surface;
  final ValueListenable<PlaybackRuntimeViewBinding>? activeBinding;
  final JellyfinApiClient client;
  final String? itemId;
  final LogicalPlaybackSession? logicalSession;
  final SubtitleRenegotiator? onRenegotiateSubtitle;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  Timer? _keepAlive;
  Timer? _controlsTimer;
  final FocusNode _playerFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player-play');
  final FocusNode _subtitleFocus = FocusNode(debugLabel: 'player-subtitles');
  final FocusNode _statsFocus = FocusNode(debugLabel: 'player-stats');
  bool _disposed = false;
  bool _reportInFlight = false;
  bool _controlsVisible = true;
  bool _sheetOpen = false;
  PlaybackReporter? _reporter;
  late PlaybackEngine _engine;
  late PlaybackVideoSurface _surface;
  var _bound = false;

  @override
  void initState() {
    super.initState();
    widget.activeBinding?.addListener(_activeBindingChanged);
    _bind(_bindingEngine, _bindingSurface);
    final logicalSession = widget.logicalSession;
    if (logicalSession != null) {
      _reporter = PlaybackReporter(client: widget.client, session: logicalSession);
      unawaited(_reporter!.started());
    }
    _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_report()));
    _syncControls();
  }

  PlaybackEngine get _bindingEngine => widget.activeBinding?.value.engine ?? widget.engine!;
  PlaybackVideoSurface get _bindingSurface => widget.activeBinding?.value.surface ?? widget.surface!;

  void _activeBindingChanged() {
    final binding = widget.activeBinding?.value;
    if (_disposed || binding?.engine == null || binding?.surface == null) return;
    _bind(binding!.engine!, binding.surface!);
  }

  void _bind(PlaybackEngine engine, PlaybackVideoSurface surface) {
    if (_bound && identical(_engine, engine)) return;
    if (_bound) {
      _engine.error.removeListener(_showPlaybackError);
      _engine.playing.removeListener(_reportingStateChanged);
      _engine.buffering.removeListener(_reportingStateChanged);
    }
    _engine = engine;
    _surface = surface;
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
      _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_report()));
    }
    _syncControls();
  }

  void _syncControls() {
    _controlsTimer?.cancel();
    if (_disposed || _sheetOpen || !_engine.playing.value || _engine.buffering.value) {
      if (mounted && !_controlsVisible) setState(() => _controlsVisible = true);
      return;
    }
    _controlsTimer = Timer(const Duration(seconds: 3), _hideControls);
  }

  void _hideControls() {
    if (_disposed || _sheetOpen || !_engine.playing.value || _engine.buffering.value) return;
    if (mounted) {
      setState(() => _controlsVisible = false);
      _playerFocus.requestFocus();
    }
  }

  void _showControls({bool focusPlay = false}) {
    _controlsTimer?.cancel();
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
    _syncControls();
    if (focusPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _controlsVisible && _playFocus.context != null) _playFocus.requestFocus();
      });
    }
  }

  void _setSheetOpen(bool value) {
    _sheetOpen = value;
    if (value) {
      _controlsTimer?.cancel();
    } else {
      _showControls();
    }
  }

  Future<void> _seekBy(Duration delta) async {
    final position = _engine.position + delta;
    final duration = _engine.duration;
    final target = position < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && position > duration
            ? duration
            : position;
    await _engine.seek(target);
    _showControls();
  }

  void _showPlaybackError() {
    final message = _engine.error.value;
    if (!mounted || message == null || message.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Playback error: $message', style: TextStyle(color: theme.textPrimary)), backgroundColor: theme.obsidianRaised, behavior: SnackBarBehavior.floating, action: SnackBarAction(label: 'RETRY', textColor: theme.goldBright, onPressed: () => unawaited(_engine.retry()))));
    });
  }

  Future<void> _report() async {
    if (_disposed || _reportInFlight || !_engine.playing.value || _engine.buffering.value) return;
    _reportInFlight = true;
    try {
      final reporter = _reporter;
      if (reporter != null) await reporter.progress(_engine.position, _engine.duration);
    } finally {
      _reportInFlight = false;
    }
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
    widget.activeBinding?.removeListener(_activeBindingChanged);
    _engine.error.removeListener(_showPlaybackError);
    _engine.playing.removeListener(_reportingStateChanged);
    _engine.buffering.removeListener(_reportingStateChanged);
    _keepAlive?.cancel();
    _controlsTimer?.cancel();
    _playerFocus.dispose();
    _playFocus.dispose();
    _subtitleFocus.dispose();
    _statsFocus.dispose();
    unawaited(_reporter?.stopped(_engine.position));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: true,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            focusNode: _playerFocus,
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              final wake = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
              if (!_controlsVisible && wake) {
                _showControls(focusPlay: true);
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.mediaPlayPause || key == LogicalKeyboardKey.keyK) {
                unawaited(_engine.playOrPause());
                _showControls();
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.keyJ) {
                unawaited(_seekBy(const Duration(seconds: -10)));
                return KeyEventResult.handled;
              }
              if (key == LogicalKeyboardKey.keyL) {
                unawaited(_seekBy(const Duration(seconds: 10)));
                return KeyEventResult.handled;
              }
              if (_playerFocus.hasPrimaryFocus && key == LogicalKeyboardKey.space) {
                unawaited(_engine.playOrPause());
                _showControls();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(children: <Widget>[
                Center(child: _surface.build(context)),
                Positioned.fill(child: MouseRegion(onHover: (_) => _showControls(), child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () { if (_controlsVisible && _engine.playing.value && !_engine.buffering.value) { _hideControls(); } else { _showControls(); } }))),
                Positioned(left: 16, right: 16, bottom: 24, child: SafeArea(top: false, child: AnimatedOpacity(opacity: _controlsVisible ? 1 : 0, duration: const Duration(milliseconds: 180), child: ExcludeFocus(excluding: !_controlsVisible, child: ExcludeSemantics(excluding: !_controlsVisible, child: IgnorePointer(ignoring: !_controlsVisible, child: _Hud(engine: _engine, logicalSession: widget.logicalSession, activeBinding: widget.activeBinding, playFocus: _playFocus, subtitleFocus: _subtitleFocus, statsFocus: _statsFocus, onSeek: _seekBy, onActivity: _showControls, onSheetOpen: _setSheetOpen, onRenegotiateSubtitle: widget.onRenegotiateSubtitle))))))),
                if (widget.activeBinding != null && widget.logicalSession != null) Positioned(right: 20, bottom: 80, child: _SkipMarkerButton(binding: widget.activeBinding!, session: widget.logicalSession!)),
                Positioned(top: 20, right: 20, child: _StatusBar(engine: _engine)),
              ]),
            ),
          ),
        ),
      );
}

class _SkipMarkerButton extends StatefulWidget {
  const _SkipMarkerButton({required this.binding, required this.session});
  final ValueListenable<PlaybackRuntimeViewBinding> binding;
  final LogicalPlaybackSession session;

  @override
  State<_SkipMarkerButton> createState() => _SkipMarkerButtonState();
}

class _SkipMarkerButtonState extends State<_SkipMarkerButton> {
  var _busy = false;

  Future<void> _skip(PlaybackMarker marker) async {
    if (_busy) return;
    final engine = widget.binding.value.engine;
    if (engine == null) return;
    setState(() => _busy = true);
    try {
      await engine.seek(marker.end);
      widget.session.position = marker.end;
    } on Object {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to skip this segment')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PlaybackMetadata>(
        valueListenable: widget.session.metadataListenable,
        builder: (_, metadata, __) => ValueListenableBuilder<PlaybackRuntimeViewBinding>(
          valueListenable: widget.binding,
          builder: (_, binding, __) {
            final engine = binding.engine;
            if (engine == null) return const SizedBox.shrink();
            return ValueListenableBuilder<Duration>(
              valueListenable: engine.positionListenable,
              builder: (_, position, __) {
                PlaybackMarker? marker;
                for (final value in metadata.markers) {
                  if (value.skipAction != null && position >= value.start && position < value.end) {
                    marker = value;
                    break;
                  }
                }
                final action = marker?.skipAction;
                if (marker == null || action == null) return const SizedBox.shrink();
                final actionableMarker = marker;
                return Semantics(
                  button: true,
                  label: action.label,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => unawaited(_skip(actionableMarker)),
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

class _Hud extends StatelessWidget {
  const _Hud({required this.engine, this.logicalSession, this.activeBinding, required this.playFocus, required this.subtitleFocus, required this.statsFocus, required this.onSeek, required this.onActivity, required this.onSheetOpen, this.onRenegotiateSubtitle});
  final PlaybackEngine engine;
  final LogicalPlaybackSession? logicalSession;
  final ValueListenable<PlaybackRuntimeViewBinding>? activeBinding;
  final FocusNode playFocus;
  final FocusNode subtitleFocus;
  final FocusNode statsFocus;
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onActivity;
  final ValueChanged<bool> onSheetOpen;
  final SubtitleRenegotiator? onRenegotiateSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final plan = logicalSession?.activePlan;
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.obsidianGlassStrong, borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.borderColor(0.25)), boxShadow: theme.glassShadow),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ValueListenableBuilder<Duration>(valueListenable: engine.positionListenable, builder: (_, position, __) => ValueListenableBuilder<Duration>(valueListenable: engine.durationListenable, builder: (_, duration, __) {
            final knownDuration = duration > Duration.zero;
            final fraction = knownDuration ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble() : null;
            return Semantics(label: knownDuration ? 'Playback ${_time(position)} of ${_time(duration)}' : 'Playback ${_time(position)}', child: Column(children: <Widget>[
              if (knownDuration) LinearProgressIndicator(value: fraction, minHeight: 4),
              Align(alignment: Alignment.centerRight, child: Text(knownDuration ? '${_time(position)} / ${_time(duration)}' : _time(position), style: TextStyle(color: theme.textSecondary, fontSize: 12))),
            ]));
          })),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: <Widget>[
            _OsdButton(order: 1, tooltip: 'Rewind 10 seconds', icon: Icons.replay_10, onFocus: onActivity, onPressed: () { onActivity(); unawaited(onSeek(const Duration(seconds: -10))); }),
            ValueListenableBuilder<bool>(valueListenable: engine.playing, builder: (_, isPlaying, __) => _OsdButton(order: 2, focusNode: playFocus, tooltip: isPlaying ? 'Pause' : 'Play', icon: isPlaying ? Icons.pause : Icons.play_arrow, onFocus: onActivity, onPressed: () { onActivity(); unawaited(engine.playOrPause()); })),
            _OsdButton(order: 3, tooltip: 'Forward 10 seconds', icon: Icons.forward_10, onFocus: onActivity, onPressed: () { onActivity(); unawaited(onSeek(const Duration(seconds: 10))); }),
      if (activeBinding != null)
        ValueListenableBuilder<PlaybackRuntimeViewBinding>(
          valueListenable: activeBinding!,
          builder: (_, binding, __) {
            final capabilities = binding.capabilities;
            final available = capabilities.subtitleTrackSwitching != CapabilitySupport.unsupported || capabilities.subtitleDelay != CapabilitySupport.unsupported || capabilities.subtitleStyling != CapabilitySupport.unsupported;
            if (!available) return const SizedBox.shrink();
            return _OsdButton(order: 4, focusNode: subtitleFocus, tooltip: 'Subtitle settings', icon: Icons.closed_caption_outlined, onFocus: onActivity, onPressed: () async { onActivity(); onSheetOpen(true); try { await TrackSelectorSheet.show(context, controls: activeBinding!, onRenegotiateSubtitle: onRenegotiateSubtitle); } finally { if (context.mounted) { onSheetOpen(false); WidgetsBinding.instance.addPostFrameCallback((_) { if (!context.mounted) return; final current = activeBinding!.value.capabilities; final availableNow = current.subtitleTrackSwitching != CapabilitySupport.unsupported || current.subtitleDelay != CapabilitySupport.unsupported || current.subtitleStyling != CapabilitySupport.unsupported; if (availableNow && subtitleFocus.context != null) { subtitleFocus.requestFocus(); } else if (playFocus.context != null) { playFocus.requestFocus(); } }); } } });
          },
        ),
      if (activeBinding != null && logicalSession != null)
        ValueListenableBuilder<PlaybackRuntimeViewBinding>(
          valueListenable: activeBinding!,
          builder: (_, binding, __) {
            if (binding.plan == null) return const SizedBox.shrink();
            return _OsdButton(order: 5, focusNode: statsFocus, tooltip: 'Stats for Nerds', icon: Icons.info_outline, onFocus: onActivity, onPressed: () async {
              onActivity();
              onSheetOpen(true);
              try { await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ValueListenableBuilder<PlaybackRuntimeViewBinding>(
                        valueListenable: activeBinding!,
                        builder: (_, current, __) => CompatibilityPanel(
                          snapshot: current.plan == null
                              ? null
                              : PlaybackDiagnosticsSnapshot.fromPlan(
                                  plan: current.plan!,
                                  runtimeId: current.runtimeId,
                                  selectedAudioStreamIndex: logicalSession!.selectedAudio,
                                  selectedSubtitleStreamIndex: logicalSession!.selectedSubtitle,
                                ),
                          runtimeDiagnostics: current.capabilities.diagnostics,
                        ),
                      ),
                    ); } finally { if (context.mounted) { onSheetOpen(false); WidgetsBinding.instance.addPostFrameCallback((_) { if (!context.mounted) return; if (activeBinding!.value.plan != null && statsFocus.context != null) { statsFocus.requestFocus(); } else if (playFocus.context != null) { playFocus.requestFocus(); } }); } }
            });
          },
        ),
      if (plan != null) DecoratedBox(decoration: BoxDecoration(color: theme.obsidianRaised, borderRadius: BorderRadius.circular(theme.radiusSmall)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), child: Text(plan.playMethod.jellyfinName, style: TextStyle(color: theme.goldBright, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))),
          ]),
        ]),
      ),
    );
  }

  String _time(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '${value.inMinutes}:$seconds';
  }
}

class _OsdButton extends StatelessWidget {
  const _OsdButton({required this.order, required this.tooltip, required this.icon, required this.onPressed, this.focusNode, this.onFocus});
  final double order;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) { if (hasFocus) onFocus?.call(); },
      child: Builder(builder: (context) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(color: theme.obsidianRaised, borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: Focus.of(context).hasFocus ? theme.goldBright : theme.goldBright.withValues(alpha: 0.45), width: Focus.of(context).hasFocus ? 3 : 2), boxShadow: Focus.of(context).hasFocus ? theme.goldGlow : null),
        child: Semantics(button: true, label: tooltip, child: IconButton(focusNode: focusNode, tooltip: tooltip, color: theme.goldBright, icon: Icon(icon), onPressed: onPressed)),
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
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return StreamBuilder<String>(stream: engine.statuses, builder: (_, snapshot) {
      final message = snapshot.data;
      if (message == null || message.isEmpty) return const SizedBox.shrink();
      return DecoratedBox(decoration: BoxDecoration(color: theme.obsidianRaised.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright.withValues(alpha: 0.8)), boxShadow: theme.goldGlow), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Icon(Icons.info_outline, color: theme.goldBright, size: 18), const SizedBox(width: 10), Flexible(child: Text(message, style: TextStyle(color: theme.goldBright), maxLines: 2, overflow: TextOverflow.ellipsis))])));
    });
  }
}
