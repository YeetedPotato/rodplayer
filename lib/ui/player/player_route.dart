import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';

class PlayerRoute extends StatefulWidget {
  const PlayerRoute({required this.client, required this.itemId, super.key});

  final RemuxClient client;
  final String itemId;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  late final RemuxEngine engine = RemuxEngine();

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => VideoPlayerView(
        engine: engine,
        client: widget.client,
        itemId: widget.itemId,
      );
}
