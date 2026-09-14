import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

enum TrackSwitchMode { local, externalAttach, serverRenegotiation }

class RodPlayerTrack {
  const RodPlayerTrack({required this.engineTrackId, required this.label, this.serverStreamIndex, this.raw});

  final String engineTrackId;
  final String label;
  final int? serverStreamIndex;
  final Object? raw;

  @override
  bool operator ==(Object other) => other is RodPlayerTrack && other.engineTrackId == engineTrackId && other.serverStreamIndex == serverStreamIndex;

  @override
  int get hashCode => Object.hash(engineTrackId, serverStreamIndex);
}

class TrackSwitchResult {
  const TrackSwitchResult({required this.mode, this.serverStreamIndex});
  final TrackSwitchMode mode;
  final int? serverStreamIndex;
}

class TrackServerIndexMappings {
  const TrackServerIndexMappings({
    this.audioServerIndexesByEngineTrackId = const <String, int>{},
    this.subtitleServerIndexesByEngineTrackId = const <String, int>{},
  });

  final Map<String, int> audioServerIndexesByEngineTrackId;
  final Map<String, int> subtitleServerIndexesByEngineTrackId;

  factory TrackServerIndexMappings.fromPlan({
    required PlaybackPlan plan,
    required List<String> audioEngineTrackIds,
    required List<String> subtitleEngineTrackIds,
  }) =>
      TrackServerIndexMappings(
        // TODO(phase-2): replace positional correlation with stronger metadata
        // matching when playback backends expose enough stable track metadata.
        audioServerIndexesByEngineTrackId: _mapEngineIdsToServerIndexes(audioEngineTrackIds, plan.source.audioStreams.map((stream) => stream.index).whereType<int>().toList(growable: false)),
        subtitleServerIndexesByEngineTrackId: _mapEngineIdsToServerIndexes(subtitleEngineTrackIds, plan.source.subtitleStreams.map((stream) => stream.index).whereType<int>().toList(growable: false)),
      );

  int? audioIndexFor(String engineTrackId) => audioServerIndexesByEngineTrackId[engineTrackId];
  int? subtitleIndexFor(String engineTrackId) => subtitleServerIndexesByEngineTrackId[engineTrackId];
}

Map<String, int> _mapEngineIdsToServerIndexes(List<String> engineTrackIds, List<int> serverIndexes) {
  final mapped = <String, int>{};
  final count = engineTrackIds.length < serverIndexes.length ? engineTrackIds.length : serverIndexes.length;
  for (var i = 0; i < count; i += 1) {
    mapped[engineTrackIds[i]] = serverIndexes[i];
  }
  return Map<String, int>.unmodifiable(mapped);
}

abstract interface class TrackSelectionController {
  List<RodPlayerTrack> get audioTracks;
  List<RodPlayerTrack> get subtitleTracks;
  RodPlayerTrack? get selectedAudio;
  RodPlayerTrack? get selectedSubtitle;
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track);
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track);
}

class LogicalSessionTrackSelectionController implements TrackSelectionController {
  LogicalSessionTrackSelectionController({required this.delegate, required this.session});

  final TrackSelectionController delegate;
  final LogicalPlaybackSession session;

  @override
  List<RodPlayerTrack> get audioTracks => delegate.audioTracks;
  @override
  List<RodPlayerTrack> get subtitleTracks => delegate.subtitleTracks;
  @override
  RodPlayerTrack? get selectedAudio => delegate.selectedAudio;
  @override
  RodPlayerTrack? get selectedSubtitle => delegate.selectedSubtitle;

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async {
    final result = await delegate.selectAudio(track);
    if (result.mode == TrackSwitchMode.local) session.selectedAudio = result.serverStreamIndex ?? track.serverStreamIndex;
    return result;
  }

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async {
    final result = await delegate.selectSubtitle(track);
    if (result.mode == TrackSwitchMode.local) session.selectedSubtitle = result.serverStreamIndex ?? track?.serverStreamIndex;
    return result;
  }
}

class MediaKitTrackSelectionController implements TrackSelectionController {
  MediaKitTrackSelectionController(
    this.player, {
    this.serverIndexMappings = const TrackServerIndexMappings(),
  });

  factory MediaKitTrackSelectionController.forPlan(Player player, PlaybackPlan plan) => MediaKitTrackSelectionController(
        player,
        serverIndexMappings: TrackServerIndexMappings.fromPlan(
          plan: plan,
          audioEngineTrackIds: player.state.tracks.audio.map((track) => track.id).toList(growable: false),
          subtitleEngineTrackIds: player.state.tracks.subtitle.map((track) => track.id).toList(growable: false),
        ),
      );

  final Player player;
  final TrackServerIndexMappings serverIndexMappings;

  @override
  List<RodPlayerTrack> get audioTracks => player.state.tracks.audio.map((track) => RodPlayerTrack(engineTrackId: track.id, serverStreamIndex: serverIndexMappings.audioIndexFor(track.id), label: _label(track.title, track.language), raw: track)).toList(growable: false);

  @override
  List<RodPlayerTrack> get subtitleTracks => player.state.tracks.subtitle.map((track) => RodPlayerTrack(engineTrackId: track.id, serverStreamIndex: serverIndexMappings.subtitleIndexFor(track.id), label: _label(track.title, track.language), raw: track)).toList(growable: false);

  @override
  RodPlayerTrack? get selectedAudio {
    final selected = player.state.track.audio;
    return selected.id.isEmpty
        ? null
        : RodPlayerTrack(
            engineTrackId: selected.id,
            serverStreamIndex: serverIndexMappings.audioIndexFor(selected.id),
            label: _label(selected.title, selected.language),
            raw: selected,
          );
  }

  @override
  RodPlayerTrack? get selectedSubtitle {
    final selected = player.state.track.subtitle;
    return selected.id.isEmpty
        ? null
        : RodPlayerTrack(
            engineTrackId: selected.id,
            serverStreamIndex: serverIndexMappings.subtitleIndexFor(selected.id),
            label: _label(selected.title, selected.language),
            raw: selected,
          );
  }

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async {
    if (track.raw is! AudioTrack) return TrackSwitchResult(mode: TrackSwitchMode.serverRenegotiation, serverStreamIndex: track.serverStreamIndex);
    await player.setAudioTrack(track.raw! as AudioTrack);
    return TrackSwitchResult(mode: TrackSwitchMode.local, serverStreamIndex: track.serverStreamIndex);
  }

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async {
    if (track != null && track.raw is! SubtitleTrack) return TrackSwitchResult(mode: TrackSwitchMode.serverRenegotiation, serverStreamIndex: track.serverStreamIndex);
    await player.setSubtitleTrack(track == null ? SubtitleTrack.no() : track.raw! as SubtitleTrack);
    return TrackSwitchResult(mode: TrackSwitchMode.local, serverStreamIndex: track?.serverStreamIndex);
  }

  String _label(String? title, String? language) {
    final parts = <String?>[title, language].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? 'Unknown track' : parts.join(' • ');
  }
}
