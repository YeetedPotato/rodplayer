import 'package:rodplayer/core/playback/playback_decision.dart';
import 'package:rodplayer/core/playback/platform_capabilities.dart';

/// Selects the server-provided stream that best matches the current device.
///
/// The repository deliberately accepts decoded Jellyfin JSON so the HTTP
/// client and the player remain independent of the playback policy.
class MediaRepository {
  MediaRepository({DeviceCapabilities? capabilities})
      : capabilities = capabilities ??
            DeviceCapabilities.forProfile(DeviceCapabilities.currentProfile()),
        _engine = PlaybackDecisionEngine(
          capabilities ??
              DeviceCapabilities.forProfile(
                DeviceCapabilities.currentProfile(),
              ),
        );

  final DeviceCapabilities capabilities;
  final PlaybackDecisionEngine _engine;

  /// Chooses a stream from a Jellyfin PlaybackInfo response.
  ///
  /// Jellyfin normally returns `MediaSources`; accepting a source list as
  /// well makes this useful with cached responses and keeps parsing local.
  PlaybackDecision selectStream(Map<String, dynamic> playbackInfo) {
    final sources = playbackInfo['MediaSources'];
    if (sources is! List) {
      return _engine.decide(playbackInfo);
    }

    PlaybackDecision? fallback;
    for (final value in sources) {
      if (value is! Map) continue;
      final source = Map<String, dynamic>.from(value);
      final decision = _engine.decide(source);
      if (decision.method == PlayMethod.directPlay && decision.url != null) {
        return decision;
      }
      fallback ??= decision;
      if (decision.method == PlayMethod.directStream && decision.url != null) {
        fallback = decision;
      }
    }
    return fallback ??
        const PlaybackDecision(
          method: PlayMethod.transcode,
          reason: 'Jellyfin returned no playable media sources',
        );
  }

  Uri? streamUri(Map<String, dynamic> playbackInfo) =>
      selectStream(playbackInfo).url;
}
