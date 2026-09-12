import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.engine,
    required this.client,
    this.itemId,
  });

  final RodPlayerEngine engine;
  final RemuxClient client;
  final String? itemId;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  Timer? _keepAlive;

  @override
  void initState() {
    super.initState();
    widget.engine.error.addListener(_showPlaybackError);
    _keepAlive = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(_report()),
    );
  }

  void _showPlaybackError() {
    final message = widget.engine.error.value;
    if (!mounted || message == null || message.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Playback error: $message', style: TextStyle(color: theme.textPrimary)),
            backgroundColor: theme.obsidianRaised,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(theme.radiusMedium),
              side: BorderSide(color: theme.goldBright.withValues(alpha: 0.38)),
            ),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: theme.goldBright,
              onPressed: () => unawaited(widget.engine.retry()),
            ),
          ),
        );
    });
  }

  Future<void> _report() async {
    final id = widget.itemId;
    if (id == null) return;
    final p = widget.engine.player.state;
    await widget.client.reportProgress(
      itemId: id,
      position: p.position,
      duration: p.duration,
      isPaused: !p.playing,
    );
  }

  @override
  void dispose() {
    widget.engine.error.removeListener(_showPlaybackError);
    _keepAlive?.cancel();
    unawaited(_report());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event.logicalKey.keyLabel == 'Media Play Pause') {
            widget.engine.player.playOrPause();
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: Video(
                  controller: widget.engine.controller,
                  controls: AdaptiveVideoControls,
                ),
              ),
              Positioned(
                top: 20,
                left: 20,
                child: _Hud(engine: widget.engine),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.engine});

  final RodPlayerEngine engine;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: engine.player.stream.playing,
      builder: (_, snap) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            color: Colors.white,
            icon: Icon(
              snap.data == true ? Icons.pause : Icons.play_arrow,
            ),
            onPressed: engine.player.playOrPause,
          ),
        );
      },
    );
  }
}
