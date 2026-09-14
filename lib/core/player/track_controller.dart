import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';

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
  MediaKitTrackSelectionController(this.player);

  final Player player;

  @override
  List<RodPlayerTrack> get audioTracks => player.state.tracks.audio.map((track) => RodPlayerTrack(engineTrackId: track.id, serverStreamIndex: _serverIndex(track.id), label: _label(track.title, track.language), raw: track)).toList(growable: false);

  @override
  List<RodPlayerTrack> get subtitleTracks => player.state.tracks.subtitle.map((track) => RodPlayerTrack(engineTrackId: track.id, serverStreamIndex: _serverIndex(track.id), label: _label(track.title, track.language), raw: track)).toList(growable: false);

  @override
  RodPlayerTrack? get selectedAudio {
    final selected = player.state.track.audio;
    return selected.id.isEmpty
        ? null
        : RodPlayerTrack(
            engineTrackId: selected.id,
            serverStreamIndex: _serverIndex(selected.id),
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
            serverStreamIndex: _serverIndex(selected.id),
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

  int? _serverIndex(String id) => int.tryParse(id);

  String _label(String? title, String? language) {
    final parts = <String?>[title, language].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? 'Unknown track' : parts.join(' • ');
  }
}
