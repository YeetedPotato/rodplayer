import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/jellyfin_device_profile_mapper.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';

class PlaybackNegotiator {
  PlaybackNegotiator({
    required this.client,
    PlaybackEnvironmentProvider? environmentProvider,
    JellyfinDeviceProfileMapper? profileMapper,
  })  : environmentProvider = environmentProvider ?? RuntimePlaybackEnvironmentProvider(identityProbe: PersistentDeviceIdentityProbe(identity: client.identity)),
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
    final backend = environment.selectPreferredBackend();
    final response = await client.getPlaybackInfo(PlaybackInfoRequest(
      itemId: itemId,
      userId: client.userId,
      deviceProfile: profileMapper.map(environment, backend.capabilities),
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      maxStreamingBitrate: environment.network.maxStreamingBitrate,
    ));
    for (final source in response.mediaSources) {
      final plan = _planFor(
        itemId: itemId,
        playSessionId: response.playSessionId,
        source: source,
        engineId: backend.capabilities.id,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
      if (plan != null) return plan;
    }
    throw ServerConnectionException('Server returned no playable media source');
  }

  PlaybackPlan? _planFor({
    required String itemId,
    required String? playSessionId,
    required MediaSourceInfo source,
    required String engineId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final method = source.playMethod ?? _methodFromSource(source);
    final selectedAudio = audioStreamIndex ?? source.defaultAudioStreamIndex;
    final selectedSubtitle = subtitleStreamIndex ?? source.defaultSubtitleStreamIndex;
    final playbackUri = switch (method) {
      PlayMethod.directPlay => client.buildDirectPlayUri(
          itemId: itemId,
          mediaSourceId: source.id.isEmpty ? itemId : source.id,
          playSessionId: playSessionId,
          audioStreamIndex: selectedAudio,
          subtitleStreamIndex: selectedSubtitle,
        ),
      PlayMethod.directStream => _resolvedTransformedUri(source.directStreamUrl ?? source.transcodingUrl),
      PlayMethod.transcode => _resolvedTransformedUri(source.transcodingUrl),
    };
    if (playbackUri == null) return null;
    return PlaybackPlan(
      itemId: itemId,
      mediaSourceId: source.id.isEmpty ? itemId : source.id,
      playSessionId: playSessionId,
      playMethod: method,
      playbackUri: playbackUri,
      engineId: engineId,
      source: source,
      selectedAudioStreamIndex: selectedAudio,
      selectedSubtitleStreamIndex: selectedSubtitle,
      transcodeReasons: source.transcodingReasons,
      videoCopied: source.videoCopied ?? false,
      audioCopied: source.audioCopied ?? false,
      containerChanged: source.containerChanged ?? false,
    );
  }

  Uri? _resolvedTransformedUri(String? uriText) {
    if (uriText == null || uriText.isEmpty) return null;
    return client.resolvePlaybackUri(uriText);
  }

  PlayMethod _methodFromSource(MediaSourceInfo source) {
    if (source.transcodingUrl != null && source.transcodingUrl!.isNotEmpty) return PlayMethod.transcode;
    if (source.supportsDirectStream == true || source.directStreamUrl != null) return PlayMethod.directStream;
    return PlayMethod.directPlay;
  }
}
