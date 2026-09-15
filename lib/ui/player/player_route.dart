import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/player_controller.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
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
  final PlaybackRuntimeRegistry _runtimeRegistry = PlaybackRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[MediaKitPlaybackRuntime()]);
  late final Future<_PreparedPlayback> _prepared = _prepare();
  PlaybackRuntimeCoordinator? _coordinator;

  Future<_PreparedPlayback> _prepare() async {
    final plan = await PlaybackNegotiator(client: widget.client).negotiate(itemId: widget.itemId);
    final logicalSession = LogicalPlaybackSession(id: const Uuid().v4(), itemId: widget.itemId, activePlan: plan);
    final coordinator = PlaybackRuntimeCoordinator(registry: _runtimeRegistry, session: logicalSession);
    _coordinator = coordinator;
    final runtimeSession = await coordinator.activate(plan);
    return _PreparedPlayback(plan: plan, session: logicalSession, runtimeSession: runtimeSession);
  }

  @override
  void dispose() {
    unawaited(_coordinator?.dispose() ?? Future<void>.value());
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
            engine: prepared.runtimeSession.engine,
            surface: prepared.runtimeSession.surface!,
            client: widget.client,
            itemId: widget.itemId,
            logicalSession: prepared.session,
          );
        },
      );
}

class _PreparedPlayback {
  const _PreparedPlayback({required this.plan, required this.session, required this.runtimeSession});
  final PlaybackPlan plan;
  final LogicalPlaybackSession session;
  final PlaybackRuntimeSession runtimeSession;
}
