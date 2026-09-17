import 'package:media_kit/media_kit.dart';
import 'package:rodplayer/core/api/models/media_stream.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/track_controller.dart';

/// media_kit-specific track selection. mpv track objects never cross the
/// generic [RodPlayerTrack] boundary.
class MediaKitTrackSelectionController implements TrackSelectionController {
  MediaKitTrackSelectionController(this.player, {required this.plan});

  factory MediaKitTrackSelectionController.forPlan(Player player, PlaybackPlan plan) => MediaKitTrackSelectionController(player, plan: plan);

  final Player player;
  final PlaybackPlan plan;

  @override
  final TrackSelectionCapabilities capabilities = const TrackSelectionCapabilities(
    audioSelection: CapabilitySupport.supported,
    subtitleSelection: CapabilitySupport.supported,
  );

  TrackServerIndexMappings get _mappings => TrackServerIndexMappings.fromPlan(
        plan: plan,
        audioTracks: player.state.tracks.audio.map((track) => EngineTrackMetadata(id: track.id, language: track.language, title: track.title)).toList(growable: false),
        subtitleTracks: player.state.tracks.subtitle.map((track) => EngineTrackMetadata(id: track.id, language: track.language, title: track.title)).toList(growable: false),
      );

  @override
  List<RodPlayerTrack> get audioTracks {
    final mappings = _mappings;
    return player.state.tracks.audio.map((track) => _audioDescriptor(track, mappings.audioIndexFor(track.id))).toList(growable: false);
  }

  @override
  List<RodPlayerTrack> get subtitleTracks {
    final mappings = _mappings;
    return player.state.tracks.subtitle.map((track) => _subtitleDescriptor(track, mappings.subtitleIndexFor(track.id))).toList(growable: false);
  }

  @override
  RodPlayerTrack? get selectedAudio {
    final track = player.state.track.audio;
    if (track.id.isEmpty) return null;
    return _audioDescriptor(track, _mappings.audioIndexFor(track.id));
  }

  @override
  RodPlayerTrack? get selectedSubtitle {
    final track = player.state.track.subtitle;
    if (track.id.isEmpty) return null;
    return _subtitleDescriptor(track, _mappings.subtitleIndexFor(track.id));
  }

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async {
    final native = _audioTracksById[track.engineTrackId];
    if (native == null) return TrackSwitchResult(mode: TrackSwitchMode.serverRenegotiation, serverStreamIndex: track.serverStreamIndex);
    final index = _mappings.audioIndexFor(native.id);
    await player.setAudioTrack(native);
    return TrackSwitchResult(mode: TrackSwitchMode.local, serverStreamIndex: index);
  }

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async {
    if (track == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
      return const TrackSwitchResult(mode: TrackSwitchMode.local);
    }
    final native = _subtitleTracksById[track.engineTrackId];
    if (native == null) return TrackSwitchResult(mode: TrackSwitchMode.serverRenegotiation, serverStreamIndex: track.serverStreamIndex);
    final index = _mappings.subtitleIndexFor(native.id);
    await player.setSubtitleTrack(native);
    return TrackSwitchResult(mode: TrackSwitchMode.local, serverStreamIndex: index);
  }

  Map<String, AudioTrack> get _audioTracksById => <String, AudioTrack>{
        for (final track in player.state.tracks.audio) track.id: track,
      };

  Map<String, SubtitleTrack> get _subtitleTracksById => <String, SubtitleTrack>{
        for (final track in player.state.tracks.subtitle) track.id: track,
      };

  RodPlayerTrack _audioDescriptor(AudioTrack track, int? serverIndex) {
    final stream = _audioStream(serverIndex);
    final title = _asNullable(track.title);
    final language = _asNullable(track.language);
    return RodPlayerTrack(
      engineTrackId: track.id,
      serverStreamIndex: serverIndex,
      label: _label(title ?? stream?.displayTitle ?? stream?.title, language ?? stream?.language),
      language: language ?? stream?.language,
      title: title ?? stream?.title,
      codec: stream?.codec,
      isDefault: stream?.isDefault,
      channels: stream?.channels,
    );
  }

  RodPlayerTrack _subtitleDescriptor(SubtitleTrack track, int? serverIndex) {
    final stream = _subtitleStream(serverIndex);
    final title = _asNullable(track.title);
    final language = _asNullable(track.language);
    return RodPlayerTrack(
      engineTrackId: track.id,
      serverStreamIndex: serverIndex,
      label: _label(title ?? stream?.displayTitle ?? stream?.title, language ?? stream?.language),
      language: language ?? stream?.language,
      title: title ?? stream?.title,
      codec: stream?.codec,
      isDefault: stream?.isDefault,
      isForced: stream?.isForced,
      isExternal: stream?.isExternal,
      isTextSubtitle: stream?.isTextSubtitleStream,
    );
  }

  MediaStream? _audioStream(int? index) => _streamFor(plan.source.audioStreams, index);
  MediaStream? _subtitleStream(int? index) => _streamFor(plan.source.subtitleStreams, index);

  MediaStream? _streamFor(Iterable<MediaStream> streams, int? index) {
    for (final stream in streams) {
      if (stream.index == index) return stream;
    }
    return null;
  }

  String _label(String? title, String? language) {
    final values = <String?>[title, language].whereType<String>().where((value) => value.trim().isNotEmpty).toList(growable: false);
    return values.isEmpty ? 'Unknown track' : values.join(' • ');
  }

  String? _asNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
