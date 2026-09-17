import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player/playback_engine.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/track_selector_sheet.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.engine, required this.surface, required this.client, this.itemId, this.logicalSession, this.activeControls, this.onRenegotiateSubtitle});
  final PlaybackEngine engine;
  final PlaybackVideoSurface surface;
  final JellyfinApiClient client;
  final String? itemId;
  final LogicalPlaybackSession? logicalSession;
  final ValueListenable<PlaybackRuntimeControlsSnapshot>? activeControls;
  final SubtitleRenegotiator? onRenegotiateSubtitle;
  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  Timer? _keepAlive;
  bool _disposed = false;
  bool _reportInFlight = false;
  PlaybackReporter? _reporter;

  @override
  void initState() {
    super.initState();
    widget.engine.error.addListener(_showPlaybackError);
    widget.engine.playing.addListener(_reportingStateChanged);
    widget.engine.buffering.addListener(_reportingStateChanged);
    final logicalSession = widget.logicalSession;
    if (logicalSession != null) {
      _reporter = PlaybackReporter(client: widget.client, session: logicalSession);
      unawaited(_reporter!.started());
    }
    _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_report()));
  }

  void _reportingStateChanged() {
    if (!_disposed && !widget.engine.playing.value && !widget.engine.buffering.value) {
      _keepAlive?.cancel();
      _keepAlive = null;
    } else if (!_disposed && _keepAlive == null) {
      _keepAlive = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_report()));
    }
  }

  void _showPlaybackError() {
    final message = widget.engine.error.value;
    if (!mounted || message == null || message.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Playback error: $message', style: TextStyle(color: theme.textPrimary)),
          backgroundColor: theme.obsidianRaised,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radiusMedium),
            side: BorderSide(color: theme.goldBright.withValues(alpha: 0.38)),
          ),
          action: SnackBarAction(label: 'RETRY', textColor: theme.goldBright, onPressed: () => unawaited(widget.engine.retry())),
        ));
    });
  }

  Future<void> _report() async {
    if (_disposed || _reportInFlight) return;
    if (!widget.engine.playing.value || widget.engine.buffering.value) return;
    _reportInFlight = true;
    try {
      final id = widget.itemId;
      final reporter = _reporter;
      if (reporter != null) {
        await reporter.progress(widget.engine.position, widget.engine.duration);
      } else if (id != null) {
        // Legacy fallback for tests/routes that do not yet create a plan.
      }
    } finally {
      _reportInFlight = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.engine.error.removeListener(_showPlaybackError);
    _keepAlive?.cancel();
    _keepAlive = null;
    widget.engine.playing.removeListener(_reportingStateChanged);
    widget.engine.buffering.removeListener(_reportingStateChanged);
    unawaited(_reporter?.stopped(widget.engine.position));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: true,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
                unawaited(widget.engine.playOrPause());
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(children: [
                Center(child: widget.surface.build(context)),
                Positioned(top: 20, left: 20, child: _Hud(engine: widget.engine, logicalSession: widget.logicalSession, activeControls: widget.activeControls, onRenegotiateSubtitle: widget.onRenegotiateSubtitle)),
                Positioned(left: 20, right: 20, bottom: 24, child: _StatusBar(engine: widget.engine)),
              ]),
            ),
          ),
        ),
      );
}

class _Hud extends StatelessWidget {
  const _Hud({required this.engine, this.logicalSession, this.activeControls, this.onRenegotiateSubtitle});
  final PlaybackEngine engine;
  final LogicalPlaybackSession? logicalSession;
  final ValueListenable<PlaybackRuntimeControlsSnapshot>? activeControls;
  final SubtitleRenegotiator? onRenegotiateSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final plan = logicalSession?.activePlan;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ValueListenableBuilder<bool>(
        valueListenable: engine.playing,
        builder: (_, isPlaying, __) => Focus(
          child: DecoratedBox(
            decoration: BoxDecoration(color: theme.obsidianRaised, borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright, width: 2), boxShadow: theme.goldGlow),
            child: IconButton(color: theme.goldBright, icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow), onPressed: () => unawaited(engine.playOrPause())),
          ),
        ),
      ),
      if (activeControls != null)
        ValueListenableBuilder<PlaybackRuntimeControlsSnapshot>(
          valueListenable: activeControls!,
          builder: (_, controls, __) {
            final capabilities = controls.capabilities;
            final available = capabilities.subtitleTrackSwitching != CapabilitySupport.unsupported || capabilities.subtitleDelay != CapabilitySupport.unsupported || capabilities.subtitleStyling != CapabilitySupport.unsupported;
            if (!available) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(left: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(color: theme.obsidianRaised, borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright, width: 2), boxShadow: theme.goldGlow),
                child: IconButton(
                  tooltip: 'Subtitle settings',
                  semanticLabel: 'Subtitle settings',
                  color: theme.goldBright,
                  icon: const Icon(Icons.closed_caption_outlined),
                  onPressed: () => TrackSelectorSheet.show(context, controls: activeControls!, onRenegotiateSubtitle: onRenegotiateSubtitle),
                ),
              ),
            );
          },
        ),
      if (plan != null)
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(color: theme.obsidianRaised.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright.withValues(alpha: 0.55))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(plan.playMethod.jellyfinName, style: TextStyle(color: theme.goldBright, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
    ]);
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.engine});
  final PlaybackEngine engine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return StreamBuilder<String>(
      stream: engine.statuses,
      builder: (_, snapshot) {
        final message = snapshot.data;
        if (message == null || message.isEmpty) return const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(color: theme.obsidianRaised.withValues(alpha: 0.94), borderRadius: BorderRadius.circular(theme.radiusMedium), border: Border.all(color: theme.goldBright.withValues(alpha: 0.8)), boxShadow: theme.goldGlow),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.info_outline, color: theme.goldBright, size: 18),
              const SizedBox(width: 10),
              Flexible(child: Text(message, style: TextStyle(color: theme.goldBright), maxLines: 2, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        );
      },
    );
  }
}
