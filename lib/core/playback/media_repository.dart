import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';

class MediaRepository {
  MediaRepository({PlaybackBackendCapabilities? backend})
      : backend = backend ?? const ConservativePlaybackEnvironmentProvider().loadBackend(),
        _engine = PlaybackDecisionEngine(backend ?? const ConservativePlaybackEnvironmentProvider().loadBackend());

  final PlaybackBackendCapabilities backend;
  final PlaybackDecisionEngine _engine;

  PlaybackDecision selectStream(Map<String, dynamic> playbackInfo) {
    final sources = playbackInfo['MediaSources'];
    if (sources is! List) return _engine.decide(playbackInfo);

    PlaybackDecision? fallback;
    for (final value in sources) {
      if (value is! Map) continue;
      final decision = _engine.decide(Map<String, dynamic>.from(value));
      if (decision.method == PlayMethod.directPlay && decision.url != null) return decision;
      fallback ??= decision;
      if (decision.url != null && decision.method != PlayMethod.directPlay) fallback = decision;
    }
    return fallback ?? const PlaybackDecision(method: PlayMethod.transcode, reason: 'Jellyfin returned no playable media sources');
  }

  Uri? streamUri(Map<String, dynamic> playbackInfo) => selectStream(playbackInfo).url;
}

extension on ConservativePlaybackEnvironmentProvider {
  PlaybackBackendCapabilities loadBackend() => const PlaybackBackendCapabilities(
        id: 'media_kit',
        name: 'media_kit',
        containers: <String>['mp4', 'mkv', 'mov', 'webm', 'ts', 'm2ts'],
        videoCodecs: <String>['h264', 'hevc', 'vp9', 'av1'],
        audioCodecs: <String>['aac', 'ac3', 'eac3', 'flac', 'opus', 'vorbis', 'mp3'],
        subtitleCodecs: <String>['srt', 'ass', 'ssa', 'subrip', 'webvtt', 'pgssub'],
      );
}
