import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/jellyfin_device_profile_mapper.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/runtime_playback_environment.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';

class PlaybackNegotiator {
  PlaybackNegotiator({
    required this.client,
    PlaybackEnvironmentProvider? environmentProvider,
    JellyfinDeviceProfileMapper? profileMapper,
    PlaybackRuntimeRegistry? runtimeRegistry,
    // TODO(phase-2): app composition should inject the platform runtime provider
    // from lib/platform/playback so display probes do not create a core->platform dependency.
  })  : environmentProvider = environmentProvider ?? RuntimePlaybackEnvironmentProvider(identityProbe: PersistentDeviceIdentityProbe(identity: client.identity)),
        profileMapper = profileMapper ?? const JellyfinDeviceProfileMapper(),
        runtimeRegistry = runtimeRegistry ?? const PlaybackRuntimeRegistry();

  final JellyfinApiClient client;
  final PlaybackEnvironmentProvider environmentProvider;
  final JellyfinDeviceProfileMapper profileMapper;
  final PlaybackRuntimeRegistry runtimeRegistry;

  Future<PlaybackPlan> negotiate({
    required String itemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async => (await negotiateDecision(itemId: itemId, audioStreamIndex: audioStreamIndex, subtitleStreamIndex: subtitleStreamIndex)).plan;

  Future<PlaybackPlanDecision> negotiateDecision({
    required String itemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final environment = await environmentProvider.load();
    return MultiBackendPlaybackNegotiator(
      requester: JellyfinPlaybackInfoRequester(client),
      profileMapper: profileMapper,
      runtimeRegistry: runtimeRegistry,
    ).negotiate(
      environment: environment,
      itemId: itemId,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
    );
  }
}
