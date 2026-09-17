import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';
import 'package:rodplayer/platform/playback/runtime_playback_probes.dart';
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
  late final Future<_PreparedPlayback> _prepared = _prepare();
  PlaybackRuntimeCoordinator? _coordinator;
  var _disposed = false;

  Future<_PreparedPlayback> _prepare() async {
    final runtimes = await createPlatformPlaybackRuntimes();
    final decision = await PlaybackNegotiator(
      client: widget.client,
      environmentProvider: createDefaultRuntimePlaybackEnvironmentProvider(
        identity: widget.client.identity,
        playbackBackendRegistry: runtimes.backendRegistry,
      ),
      runtimeRegistry: runtimes.registry,
    ).negotiateDecision(itemId: widget.itemId);
    final plan = decision.plan;
    final logicalSession = LogicalPlaybackSession(id: const Uuid().v4(), itemId: widget.itemId, activePlan: plan);
    final coordinator = PlaybackRuntimeCoordinator(registry: runtimes.registry, session: logicalSession);
    _coordinator = coordinator;
    final runtimeSession = await coordinator.activateCandidates(decision.orderedUsableCandidates);
    unawaited(_loadOptionalMetadata(logicalSession, coordinator));
    return _PreparedPlayback(
      plan: runtimeSession.plan,
      session: logicalSession,
      runtimeSession: runtimeSession,
      coordinator: coordinator,
      renegotiateSubtitle: (track) => _renegotiateSubtitle(
        track: track,
        coordinator: coordinator,
        session: logicalSession,
        negotiator: PlaybackNegotiator(
          client: widget.client,
          environmentProvider: createDefaultRuntimePlaybackEnvironmentProvider(
            identity: widget.client.identity,
            playbackBackendRegistry: runtimes.backendRegistry,
          ),
          runtimeRegistry: runtimes.registry,
        ),
      ),
    );
  }

  Future<void> _renegotiateSubtitle({
    required RodPlayerTrack track,
    required PlaybackRuntimeCoordinator coordinator,
    required LogicalPlaybackSession session,
    required PlaybackNegotiator negotiator,
  }) async {
    final subtitleIndex = track.serverStreamIndex;
    if (subtitleIndex == null) throw StateError('The selected subtitle has no server stream index.');
    final current = coordinator.active;
    final position = current?.engine.position ?? session.position;
    final wasPlaying = current?.engine.playing.value ?? false;
    final decision = await negotiator.negotiateDecision(
      itemId: session.itemId,
      audioStreamIndex: session.selectedAudio,
      subtitleStreamIndex: subtitleIndex,
    );
    await coordinator.activateCandidates(
      decision.orderedUsableCandidates,
      prepare: (candidate) async {
        await candidate.engine.seek(position);
        if (wasPlaying) {
          await candidate.engine.play();
        } else {
          await candidate.engine.pause();
        }
      },
    );
    session.position = position;
  }

  Future<void> _loadOptionalMetadata(LogicalPlaybackSession session, PlaybackRuntimeCoordinator coordinator) async {
    try {
      final item = await widget.client.getItem(widget.itemId);
      if (_disposed || !mounted || !identical(_coordinator, coordinator)) return;
      session.updateMetadata(session.metadata.mergeLibraryItem(item));
      coordinator.synchronizeActiveMetadata();
      if (session.activePlan.source.hasSegments == true) {
        final sourceId = session.activePlan.source.id;
        final segments = await widget.client.getMediaSegments(itemId: session.itemId);
        if (_disposed || !mounted || !identical(_coordinator, coordinator) || session.activePlan.source.id != sourceId) return;
        session.updateMetadata(session.metadata.withMediaSegments(segments.map((segment) => segment.marker)));
        coordinator.synchronizeActiveMetadata();
      }
    } on Object {
      // Item metadata is optional and must never interrupt playback.
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
            activeBinding: prepared.coordinator.activeBinding,
            onRenegotiateSubtitle: prepared.renegotiateSubtitle,
          );
        },
      );
}

class _PreparedPlayback {
  const _PreparedPlayback({required this.plan, required this.session, required this.runtimeSession, required this.coordinator, required this.renegotiateSubtitle});
  final PlaybackPlan plan;
  final LogicalPlaybackSession session;
  final PlaybackRuntimeSession runtimeSession;
  final PlaybackRuntimeCoordinator coordinator;
  final Future<void> Function(RodPlayerTrack track) renegotiateSubtitle;
}
