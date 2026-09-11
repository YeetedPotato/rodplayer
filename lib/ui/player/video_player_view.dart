import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/api/remux_client.dart';
import '../../core/player/player_controller.dart';

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
    _keepAlive = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _report(),
    );
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
    _keepAlive?.cancel();
    _report();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
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
