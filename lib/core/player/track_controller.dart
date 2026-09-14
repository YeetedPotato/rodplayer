import 'package:media_kit/media_kit.dart';

class RodPlayerTrack {
  const RodPlayerTrack({required this.id, required this.label, this.raw});

  final String id;
  final String label;
  final Object? raw;

  @override
  bool operator ==(Object other) => other is RodPlayerTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

abstract interface class TrackSelectionController {
  List<RodPlayerTrack> get audioTracks;
  List<RodPlayerTrack> get subtitleTracks;
  RodPlayerTrack? get selectedAudio;
  RodPlayerTrack? get selectedSubtitle;
  Future<void> selectAudio(RodPlayerTrack track);
  Future<void> selectSubtitle(RodPlayerTrack? track);
}

class MediaKitTrackSelectionController implements TrackSelectionController {
  MediaKitTrackSelectionController(this.player);

  final Player player;

  @override
  List<RodPlayerTrack> get audioTracks => player.state.tracks.audio.map((track) => RodPlayerTrack(id: track.id, label: _label(track.title, track.language), raw: track)).toList(growable: false);

  @override
  List<RodPlayerTrack> get subtitleTracks => player.state.tracks.subtitle.map((track) => RodPlayerTrack(id: track.id, label: _label(track.title, track.language), raw: track)).toList(growable: false);

  @override
  RodPlayerTrack? get selectedAudio {
    final selected = player.state.track.audio;
    if (selected == null) return null;
    return RodPlayerTrack(id: selected.id, label: _label(selected.title, selected.language), raw: selected);
  }

  @override
  RodPlayerTrack? get selectedSubtitle {
    final selected = player.state.track.subtitle;
    if (selected == null) return null;
    return RodPlayerTrack(id: selected.id, label: _label(selected.title, selected.language), raw: selected);
  }

  @override
  Future<void> selectAudio(RodPlayerTrack track) => player.setAudioTrack(track.raw! as AudioTrack);

  @override
  Future<void> selectSubtitle(RodPlayerTrack? track) => player.setSubtitleTrack(track == null ? SubtitleTrack.no() : track.raw! as SubtitleTrack);

  String _label(String? title, String? language) {
    final parts = <String?>[title, language].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? 'Unknown track' : parts.join(' • ');
  }
}
