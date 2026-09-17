import 'package:rodplayer/core/api/models/media_stream.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

enum TrackSwitchMode { local, externalAttach, serverRenegotiation }

class TrackSelectionCapabilities {
  const TrackSelectionCapabilities({
    this.audioSelection = CapabilitySupport.unsupported,
    this.subtitleSelection = CapabilitySupport.unsupported,
  });

  const TrackSelectionCapabilities.unavailable()
      : audioSelection = CapabilitySupport.unsupported,
        subtitleSelection = CapabilitySupport.unsupported;

  final CapabilitySupport audioSelection;
  final CapabilitySupport subtitleSelection;
}

/// Backend-neutral track descriptor. Native backend objects stay private to the
/// backend-specific selection controller.
class RodPlayerTrack {
  const RodPlayerTrack({
    required this.engineTrackId,
    required this.label,
    this.serverStreamIndex,
    this.language,
    this.title,
    this.codec,
    this.isDefault,
    this.isForced,
    this.isExternal,
    this.isTextSubtitle,
    this.channels,
  });

  final String engineTrackId;
  final String label;
  final int? serverStreamIndex;
  final String? language;
  final String? title;
  final String? codec;
  final bool? isDefault;
  final bool? isForced;
  final bool? isExternal;
  final bool? isTextSubtitle;
  final int? channels;

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

/// Stable engine-visible metadata used only to correlate a backend track with
/// a Jellyfin stream. Missing or ambiguous evidence remains unmapped.
class EngineTrackMetadata {
  const EngineTrackMetadata({required this.id, this.language, this.title, this.codec});

  final String id;
  final String? language;
  final String? title;
  final String? codec;
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
    required List<EngineTrackMetadata> audioTracks,
    required List<EngineTrackMetadata> subtitleTracks,
  }) =>
      TrackServerIndexMappings(
        audioServerIndexesByEngineTrackId: _mapEngineTracks(audioTracks, plan.source.audioStreams),
        subtitleServerIndexesByEngineTrackId: _mapEngineTracks(subtitleTracks, plan.source.subtitleStreams),
      );

  int? audioIndexFor(String engineTrackId) => audioServerIndexesByEngineTrackId[engineTrackId];
  int? subtitleIndexFor(String engineTrackId) => subtitleServerIndexesByEngineTrackId[engineTrackId];
}

Map<String, int> _mapEngineTracks(List<EngineTrackMetadata> engineTracks, List<MediaStream> serverStreams) {
  final mapped = <String, int>{};
  for (final engine in engineTracks) {
    if (engine.id.isEmpty) continue;
    final candidates = serverStreams.where((stream) => _matches(engine, stream)).toList(growable: false);
    if (candidates.length == 1 && candidates.single.index != null) {
      mapped[engine.id] = candidates.single.index!;
    }
  }
  return Map<String, int>.unmodifiable(mapped);
}

bool _matches(EngineTrackMetadata engine, MediaStream stream) {
  final language = _normalized(engine.language);
  final title = _normalized(engine.title);
  final codec = _normalized(engine.codec);
  if (language == null && title == null && codec == null) return false;
  if (language != null && language != _normalized(stream.language)) return false;
  if (codec != null && codec != _normalized(stream.codec)) return false;
  if (title != null && title != _normalized(stream.title) && title != _normalized(stream.displayTitle)) return false;
  return true;
}

String? _normalized(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

abstract class TrackSelectionController {
  TrackSelectionCapabilities get capabilities => const TrackSelectionCapabilities.unavailable();
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
  TrackSelectionCapabilities get capabilities => delegate.capabilities;
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
