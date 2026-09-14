import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/jellyfin_device_profile_mapper.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

class PlaybackNegotiator {
  PlaybackNegotiator({
    required this.client,
    PlaybackEnvironmentProvider? environmentProvider,
    JellyfinDeviceProfileMapper? profileMapper,
  })  : environmentProvider = environmentProvider ?? const ConservativePlaybackEnvironmentProvider(),
        profileMapper = profileMapper ?? const JellyfinDeviceProfileMapper();

  final JellyfinApiClient client;
  final PlaybackEnvironmentProvider environmentProvider;
  final JellyfinDeviceProfileMapper profileMapper;

  Future<PlaybackPlan> negotiate({
    required String itemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final environment = await environmentProvider.load();
    final backend = environment.primaryBackend;
    final response = await client.getPlaybackInfo(PlaybackInfoRequest(
      itemId: itemId,
      userId: client.userId,
      deviceProfile: profileMapper.map(environment, backend),
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      maxStreamingBitrate: environment.network.maxStreamingBitrate,
    ));
    for (final source in response.mediaSources) {
      final plan = _planFor(itemId: itemId, playSessionId: response.playSessionId, source: source, engineId: backend.id);
      if (plan != null) return plan;
    }
    throw ServerConnectionException('Server returned no playable media source');
  }

  PlaybackPlan? _planFor({required String itemId, required String? playSessionId, required MediaSourceInfo source, required String engineId}) {
    final method = source.playMethod ?? _methodFromSource(source);
    final uriText = switch (method) {
      PlayMethod.directPlay => source.directStreamUrl ?? source.path,
      PlayMethod.directStream => source.directStreamUrl ?? source.transcodingUrl,
      PlayMethod.transcode => source.transcodingUrl,
    };
    if (uriText == null || uriText.isEmpty) return null;
    return PlaybackPlan(
      itemId: itemId,
      mediaSourceId: source.id.isEmpty ? itemId : source.id,
      playSessionId: playSessionId,
      playMethod: method,
      playbackUri: client.resolvePlaybackUri(uriText),
      engineId: engineId,
      source: source,
      selectedAudioStreamIndex: source.defaultAudioStreamIndex,
      selectedSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
      transcodeReasons: source.transcodingReasons,
      videoCopied: source.videoCopied ?? false,
      audioCopied: source.audioCopied ?? false,
      containerChanged: source.containerChanged ?? false,
    );
  }

  PlayMethod _methodFromSource(MediaSourceInfo source) {
    if (source.transcodingUrl != null && source.transcodingUrl!.isNotEmpty) return PlayMethod.transcode;
    if (source.supportsDirectStream == true || source.directStreamUrl != null) return PlayMethod.directStream;
    return PlayMethod.directPlay;
  }
}
