import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/runtime_playback_recovery.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_source_switch_coordinator.dart';
import 'package:rodplayer/core/player/playback_subtitle_switch_coordinator.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';
import 'package:rodplayer/platform/playback/runtime_playback_probes.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:uuid/uuid.dart';

class PlayerRoute extends StatefulWidget {
  const PlayerRoute({
    required this.client,
    required this.itemId,
    this.selectedMediaSourceId,
    this.startPosition = Duration.zero,
    this.initiallyPlaying = true,
    this.onUserDataChanged,
    this.runtimeSetFactory,
    super.key,
  });

  final JellyfinApiClient client;
  final String itemId;
  final String? selectedMediaSourceId;
  final Duration startPosition;
  final bool initiallyPlaying;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final Future<PlatformPlaybackRuntimeSet> Function()? runtimeSetFactory;

  @override
  State<PlayerRoute> createState() => _PlayerRouteState();
}

class _PlayerRouteState extends State<PlayerRoute> {
  late final Future<_PreparedPlayback> _prepared = _prepare();
  PlaybackRuntimeCoordinator? _coordinator;
  RuntimePlaybackRecovery? _recovery;
  PlaybackSourceSwitchCoordinator? _sourceSwitchCoordinator;
  String? _selectedMediaSourceId;
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    _selectedMediaSourceId = widget.selectedMediaSourceId;
  }

  Future<_PreparedPlayback> _prepare() async {
    final runtimes =
        await (widget.runtimeSetFactory ?? createPlatformPlaybackRuntimes)();
    if (_disposed) {
      throw StateError('Player route was disposed during preparation');
    }
    final negotiator = PlaybackNegotiator(
      client: widget.client,
      environmentProvider: createDefaultRuntimePlaybackEnvironmentProvider(
        identity: widget.client.identity,
        playbackBackendRegistry: runtimes.backendRegistry,
      ),
      runtimeRegistry: runtimes.registry,
    );
    final decision = await negotiator.negotiateDecision(
        itemId: widget.itemId, selectedMediaSourceId: _selectedMediaSourceId);
    if (_disposed) {
      throw StateError('Player route was disposed during preparation');
    }
    final plan = decision.plan;
    final logicalSession = LogicalPlaybackSession(
        id: const Uuid().v4(),
        itemId: widget.itemId,
        activePlan: plan,
        position: widget.startPosition);
    final coordinator = PlaybackRuntimeCoordinator(
        registry: runtimes.registry, session: logicalSession);
    _coordinator = coordinator;
    if (_disposed) {
      await coordinator.dispose();
      throw StateError('Player route was disposed during preparation');
    }
    final runtimeSession = await coordinator.activateCandidates(
      decision.orderedUsableCandidates,
      prepare: (candidate) async {
        if (candidate.engine.playing.value) await candidate.engine.pause();
        await preparePlaybackStartPosition(
          candidate: candidate,
          session: logicalSession,
          startPosition: widget.startPosition,
          startPlayingAfterSeek: false,
        );
      },
    );
    if (_disposed) {
      await coordinator.dispose();
      throw StateError('Player route was disposed during preparation');
    }
    if (!identical(coordinator.active, runtimeSession)) {
      throw PlaybackActivationSupersededException();
    }
    if (widget.initiallyPlaying) await runtimeSession.engine.play();
    if (_disposed) {
      await coordinator.dispose();
      throw StateError('Player route was disposed during preparation');
    }
    unawaited(_loadOptionalMetadata(logicalSession, coordinator));
    final recovery = RuntimePlaybackRecovery(
        coordinator: coordinator,
        session: logicalSession,
        negotiator: negotiator,
        selectedMediaSourceId: _selectedMediaSourceId);
    _recovery = recovery;
    final reporter =
        PlaybackReporter(client: widget.client, session: logicalSession);
    final commandController = PlaybackCommandController.forCoordinator(
      coordinator,
      renegotiateSubtitle: (track) => _renegotiateSubtitle(
        track: track,
        coordinator: coordinator,
        session: logicalSession,
        negotiator: negotiator,
      ),
    );
    final sourceSwitchCoordinator = PlaybackSourceSwitchCoordinator(
      session: logicalSession,
      runtimeCoordinator: coordinator,
      negotiate: (
              {required itemId,
              required mediaSourceId,
              audioStreamIndex,
              subtitleStreamIndex}) =>
          negotiator.negotiateDecision(
        itemId: itemId,
        selectedMediaSourceId: mediaSourceId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      ),
      reporter: reporter,
      invalidateRecovery: recovery.invalidate,
      onCommitted: (handoff, replacement) async {
        if (_disposed || !mounted || !identical(_coordinator, coordinator)) {
          return;
        }
        _selectedMediaSourceId = replacement.plan.mediaSourceId;
        recovery.updateSelectedMediaSourceId(replacement.plan.mediaSourceId);
      },
    );
    _sourceSwitchCoordinator = sourceSwitchCoordinator;
    return _PreparedPlayback(
      plan: runtimeSession.plan,
      session: logicalSession,
      runtimeSession: runtimeSession,
      coordinator: coordinator,
      reporter: reporter,
      commandController: commandController,
      recover: recovery.recover,
      loadMediaSources: () =>
          negotiator.listMediaSources(itemId: widget.itemId),
      selectMediaSource: (source) async {
        await sourceSwitchCoordinator.select(source);
      },
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

  Future<PlaybackRuntimeSession?> _renegotiateSubtitle({
    required RodPlayerTrack track,
    required PlaybackRuntimeCoordinator coordinator,
    required LogicalPlaybackSession session,
    required PlaybackNegotiator negotiator,
  }) async {
    if (_disposed) return null;
    return PlaybackSubtitleSwitchCoordinator(
      coordinator: coordinator,
      invalidateRecovery: () => _recovery?.invalidate(),
      negotiate: (
              {required itemId,
              required selectedMediaSourceId,
              audioStreamIndex,
              subtitleStreamIndex}) =>
          negotiator.negotiateDecision(
              itemId: itemId,
              selectedMediaSourceId: selectedMediaSourceId,
              audioStreamIndex: audioStreamIndex,
              subtitleStreamIndex: subtitleStreamIndex),
    ).select(track);
  }

  Future<void> _loadOptionalMetadata(LogicalPlaybackSession session,
      PlaybackRuntimeCoordinator coordinator) async {
    try {
      final item = await widget.client.getItem(widget.itemId);
      if (!_disposed && mounted && identical(_coordinator, coordinator)) {
        session.updateMetadata(session.metadata.mergeLibraryItem(item));
        coordinator.synchronizeActiveMetadata();
      }
    } on Object {
      // Item metadata is optional and must never interrupt playback.
    }
    if (session.activePlan.source.hasSegments != true) return;
    try {
      final segments =
          await widget.client.getMediaSegments(itemId: session.itemId);
      if (_disposed ||
          !mounted ||
          !identical(_coordinator, coordinator) ||
          segments == null) {
        return;
      }
      session.updateMetadata(session.metadata
          .withMediaSegments(segments.map((segment) => segment.marker)));
      coordinator.synchronizeActiveMetadata();
    } on Object {
      // Segment metadata is optional and must never interrupt playback.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sourceSwitchCoordinator?.dispose();
    _recovery?.dispose();
    unawaited(_coordinator?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PreparedPlayback>(
        future: _prepared,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                    child:
                        Text('Unable to start playback: ${snapshot.error}')));
          }
          final prepared = snapshot.data!;
          return VideoPlayerView(
            engine: prepared.runtimeSession.engine,
            surface: prepared.runtimeSession.surface!,
            client: widget.client,
            itemId: widget.itemId,
            onUserDataChanged: widget.onUserDataChanged,
            logicalSession: prepared.session,
            reporter: prepared.reporter,
            activeBinding: prepared.coordinator.activeBinding,
            commandController: prepared.commandController,
            onRenegotiateSubtitle: prepared.renegotiateSubtitle,
            onPlaybackError: prepared.recover,
            loadMediaSources: prepared.loadMediaSources,
            onSelectMediaSource: prepared.selectMediaSource,
          );
        },
      );
}

class _PreparedPlayback {
  const _PreparedPlayback(
      {required this.plan,
      required this.session,
      required this.runtimeSession,
      required this.coordinator,
      required this.reporter,
      required this.commandController,
      required this.renegotiateSubtitle,
      required this.recover,
      required this.loadMediaSources,
      required this.selectMediaSource});
  final PlaybackPlan plan;
  final LogicalPlaybackSession session;
  final PlaybackRuntimeSession runtimeSession;
  final PlaybackRuntimeCoordinator coordinator;
  final PlaybackSessionReporter reporter;
  final PlaybackCommandController commandController;
  final Future<PlaybackRuntimeSession?> Function(RodPlayerTrack track)
      renegotiateSubtitle;
  final Future<void> Function() recover;
  final Future<List<MediaSourceInfo>> Function() loadMediaSources;
  final Future<void> Function(MediaSourceInfo source) selectMediaSource;
}
