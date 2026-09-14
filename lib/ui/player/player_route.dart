import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:uuid/uuid.dart';

class PlayerRoute extends StatefulWidget {
  const PlayerRoute({required this.client, required this.itemId, super.key});

  final JellyfinApiClient client;
  final String itemId;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  late final MediaKitPlaybackEngine engine = MediaKitPlaybackEngine();
  late final Future<_PreparedPlayback> _prepared = _prepare();

  Future<_PreparedPlayback> _prepare() async {
    final plan = await PlaybackNegotiator(client: widget.client).negotiate(itemId: widget.itemId);
    await engine.load(plan);
    return _PreparedPlayback(
      plan: plan,
      session: LogicalPlaybackSession(id: const Uuid().v4(), itemId: widget.itemId, activePlan: plan),
    );
  }

  @override
  void dispose() {
    unawaited(engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PreparedPlayback>(
        future: _prepared,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(backgroundColor: Colors.black, body: Center(child: Text('Unable to start playback: ${snapshot.error}')));
          }
          final prepared = snapshot.data!;
          return VideoPlayerView(
            engine: engine,
            client: widget.client,
            itemId: widget.itemId,
            logicalSession: prepared.session,
          );
        },
      );
}

class _PreparedPlayback {
  const _PreparedPlayback({required this.plan, required this.session});
  final PlaybackPlan plan;
  final LogicalPlaybackSession session;
}
