import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/jellyfin_device_profile_mapper.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/api/models/playback_info_response.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

abstract interface class PlaybackInfoRequester {
  String? get userId;
  Future<PlaybackInfoResponse> getPlaybackInfo(PlaybackInfoRequest request);
  Future<PlaybackInfoResponse> getPlaybackInfoForBackend(PlaybackBackendDescriptor backend, PlaybackInfoRequest request);
  Uri buildDirectPlayUri({required String itemId, required String mediaSourceId, String? playSessionId, int? audioStreamIndex, int? subtitleStreamIndex});
  Uri? resolvePlaybackUri(String uriText);
}

class JellyfinPlaybackInfoRequester implements PlaybackInfoRequester {
  const JellyfinPlaybackInfoRequester(this.client);

  final JellyfinApiClient client;

  @override
  String? get userId => client.userId;

  @override
  Future<PlaybackInfoResponse> getPlaybackInfo(PlaybackInfoRequest request) => client.getPlaybackInfo(request);

  @override
  Future<PlaybackInfoResponse> getPlaybackInfoForBackend(PlaybackBackendDescriptor backend, PlaybackInfoRequest request) => getPlaybackInfo(request);

  @override
  Uri buildDirectPlayUri({required String itemId, required String mediaSourceId, String? playSessionId, int? audioStreamIndex, int? subtitleStreamIndex}) => client.buildDirectPlayUri(
        itemId: itemId,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );

  @override
  Uri? resolvePlaybackUri(String uriText) => client.resolvePlaybackUri(uriText);
}

class PlaybackBackendCandidate {
  const PlaybackBackendCandidate({
    required this.backend,
    this.effectiveProfile,
    this.response,
    this.source,
    this.plan,
    this.score,
    this.rejectionReason,
  });

  final PlaybackBackendDescriptor backend;
  final EffectivePlaybackProfile? effectiveProfile;
  final PlaybackInfoResponse? response;
  final MediaSourceInfo? source;
  final PlaybackPlan? plan;
  final PlaybackPlanScore? score;
  final String? rejectionReason;

  bool get isUsable => plan != null && score != null && rejectionReason == null;
}

class PlaybackPlanScore {
  const PlaybackPlanScore({required this.total, required this.components});

  final int total;
  final Map<String, int> components;
}

class PlaybackPlanDecision {
  const PlaybackPlanDecision({
    required this.selected,
    required this.candidates,
  });

  final PlaybackBackendCandidate selected;
  final List<PlaybackBackendCandidate> candidates;

  PlaybackPlan get plan => selected.plan!;
  String get selectedBackendId => selected.backend.id;
  PlaybackPlanScore get score => selected.score!;
  List<PlaybackBackendCandidate> get rejectedCandidates => candidates.where((candidate) => !candidate.isUsable).toList(growable: false);
}

class PlaybackPlanScorer {
  const PlaybackPlanScorer();

  PlaybackPlanScore score(PlaybackPlan plan, PlaybackBackendDescriptor backend) {
    final c = <String, int>{};
    c['delivery'] = switch (plan.deliveryMode ?? _deliveryMode(plan.playMethod)) {
      PlaybackDeliveryMode.directPlay => 1000,
      PlaybackDeliveryMode.directStream => 800,
      PlaybackDeliveryMode.transcode => 500,
    };
    c['video'] = switch (plan.videoOperation) {
      VideoOperation.copy => 200,
      VideoOperation.transcode => -300,
      VideoOperation.none => 0,
      VideoOperation.unknown => 0,
    };
    c['audio'] = switch (plan.audioOperation) {
      AudioOperation.copy => 100,
      AudioOperation.transcode => -80,
      AudioOperation.none => 0,
      AudioOperation.unknown => 0,
    };
    c['subtitle'] = switch (plan.subtitleOperation) {
      SubtitleOperation.native => 50,
      SubtitleOperation.external => 45,
      SubtitleOperation.burnIn => -100,
      SubtitleOperation.none => 0,
      SubtitleOperation.unknown => 0,
    };
    c['hdr'] = switch (plan.hdrHandling) {
      HdrHandling.preserve => 80,
      HdrHandling.toneMapToSdr => -80,
      HdrHandling.none => 0,
      HdrHandling.unknown => 0,
    };
    c['container'] = plan.containerChanged ? -30 : 0;
    c['hardwareDecode'] = switch (backend.capabilities.hardwareDecode) {
      CapabilitySupport.supported => 20,
      CapabilitySupport.unsupported => -20,
      CapabilitySupport.unknown => 0,
    };
    c['audioPreservation'] = backend.capabilities.passthrough == CapabilitySupport.supported ? 20 : 0;
    return PlaybackPlanScore(total: c.values.fold<int>(0, (sum, value) => sum + value), components: Map<String, int>.unmodifiable(c));
  }
}

abstract interface class PlaybackBackendRuntime {
  String get backendId;
}

class PlaybackBackendRuntimeRegistry {
  const PlaybackBackendRuntimeRegistry({this.runtimes = const <PlaybackBackendRuntime>[]});

  final List<PlaybackBackendRuntime> runtimes;

  PlaybackBackendRuntime? resolve(String backendId) {
    for (final runtime in runtimes) {
      if (runtime.backendId == backendId) return runtime;
    }
    return null;
  }

  bool canRoute(String backendId) => backendId == PlaybackBackendIds.mediaKit || resolve(backendId) != null;
}

class MediaKitPlaybackBackendRuntime implements PlaybackBackendRuntime {
  const MediaKitPlaybackBackendRuntime();

  @override
  String get backendId => PlaybackBackendIds.mediaKit;
}

class MultiBackendPlaybackNegotiator {
  MultiBackendPlaybackNegotiator({
    required this.requester,
    this.profileMapper = const JellyfinDeviceProfileMapper(),
    this.scorer = const PlaybackPlanScorer(),
    this.runtimeRegistry = const PlaybackBackendRuntimeRegistry(runtimes: <PlaybackBackendRuntime>[MediaKitPlaybackBackendRuntime()]),
  });

  final PlaybackInfoRequester requester;
  final JellyfinDeviceProfileMapper profileMapper;
  final PlaybackPlanScorer scorer;
  final PlaybackBackendRuntimeRegistry runtimeRegistry;

  Future<PlaybackPlanDecision> negotiate({
    required PlaybackEnvironment environment,
    required String itemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final candidates = <PlaybackBackendCandidate>[];
    for (final backend in environment.backends.where((backend) => backend.availability == BackendAvailability.available)) {
      if (!runtimeRegistry.canRoute(backend.id)) {
        candidates.add(PlaybackBackendCandidate(backend: backend, rejectionReason: 'No playback runtime registered'));
        continue;
      }
      candidates.addAll(await _candidatesForBackend(
        environment: environment,
        backend: backend,
        itemId: itemId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      ));
    }
    final usable = candidates.where((candidate) => candidate.isUsable).toList(growable: false)
      ..sort(_compareCandidates);
    if (usable.isEmpty) throw ServerConnectionException('Server returned no playable media source');
    return PlaybackPlanDecision(selected: usable.first, candidates: candidates);
  }

  Future<List<PlaybackBackendCandidate>> _candidatesForBackend({
    required PlaybackEnvironment environment,
    required PlaybackBackendDescriptor backend,
    required String itemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final profile = environment.effectiveProfileFor(backend.id);
    final response = await requester.getPlaybackInfoForBackend(backend, PlaybackInfoRequest(
      itemId: itemId,
      userId: requester.userId,
      deviceProfile: profileMapper.map(environment, backend.capabilities),
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      maxStreamingBitrate: environment.network.maxStreamingBitrate,
    ));
    final candidates = <PlaybackBackendCandidate>[];
    for (final source in response.mediaSources) {
      final plan = _planFor(
        itemId: itemId,
        playSessionId: response.playSessionId,
        source: source,
        engineId: backend.id,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
      candidates.add(PlaybackBackendCandidate(
        backend: backend,
        effectiveProfile: profile,
        response: response,
        source: source,
        plan: plan,
        score: plan == null ? null : scorer.score(plan, backend),
        rejectionReason: plan == null ? 'Server response had no authoritative playback URL' : null,
      ));
    }
    if (candidates.isEmpty) {
      candidates.add(PlaybackBackendCandidate(backend: backend, effectiveProfile: profile, response: response, rejectionReason: 'Server returned no media sources'));
    }
    return candidates;
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
      PlayMethod.directPlay => requester.buildDirectPlayUri(
          itemId: itemId,
          mediaSourceId: source.id.isEmpty ? itemId : source.id,
          playSessionId: playSessionId,
          audioStreamIndex: selectedAudio,
          subtitleStreamIndex: selectedSubtitle,
        ),
      PlayMethod.directStream => _resolvedServerUri(source.directStreamUrl ?? source.transcodingUrl),
      PlayMethod.transcode => _resolvedServerUri(source.transcodingUrl),
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
      videoCopied: source.videoCopied ?? method != PlayMethod.transcode,
      audioCopied: source.audioCopied ?? method != PlayMethod.transcode,
      containerChanged: source.containerChanged ?? false,
      deliveryMode: _deliveryMode(method),
      videoOperation: _videoOperation(method, source),
      audioOperation: _audioOperation(method, source),
      subtitleOperation: _subtitleOperation(source, selectedSubtitle),
      hdrHandling: _hdrHandling(source),
    );
  }

  Uri? _resolvedServerUri(String? uriText) {
    if (uriText == null || uriText.isEmpty) return null;
    return requester.resolvePlaybackUri(uriText);
  }

  PlayMethod _methodFromSource(MediaSourceInfo source) {
    if (source.transcodingUrl != null && source.transcodingUrl!.isNotEmpty) return PlayMethod.transcode;
    if (source.supportsDirectStream == true || source.directStreamUrl != null) return PlayMethod.directStream;
    return PlayMethod.directPlay;
  }
}

int _compareCandidates(PlaybackBackendCandidate a, PlaybackBackendCandidate b) {
  final score = b.score!.total.compareTo(a.score!.total);
  if (score != 0) return score;
  final priority = a.backend.priority.compareTo(b.backend.priority);
  if (priority != 0) return priority;
  final backend = a.backend.id.compareTo(b.backend.id);
  if (backend != 0) return backend;
  return (a.plan?.mediaSourceId ?? '').compareTo(b.plan?.mediaSourceId ?? '');
}

PlaybackDeliveryMode _deliveryMode(PlayMethod method) => switch (method) {
      PlayMethod.directPlay => PlaybackDeliveryMode.directPlay,
      PlayMethod.directStream => PlaybackDeliveryMode.directStream,
      PlayMethod.transcode => PlaybackDeliveryMode.transcode,
    };

VideoOperation _videoOperation(PlayMethod method, MediaSourceInfo source) {
  if (source.videoStreams.isEmpty) return VideoOperation.none;
  if (method == PlayMethod.transcode && source.videoCopied != true) return VideoOperation.transcode;
  return VideoOperation.copy;
}

AudioOperation _audioOperation(PlayMethod method, MediaSourceInfo source) {
  if (source.audioStreams.isEmpty) return AudioOperation.none;
  if (method == PlayMethod.transcode && source.audioCopied != true) return AudioOperation.transcode;
  return AudioOperation.copy;
}

SubtitleOperation _subtitleOperation(MediaSourceInfo source, int? selectedSubtitle) {
  final subtitles = source.subtitleStreams;
  if (selectedSubtitle == null && subtitles.isEmpty) return SubtitleOperation.none;
  final selected = subtitles.where((stream) => stream.index == selectedSubtitle).firstOrNull;
  if (selected == null) return subtitles.isEmpty ? SubtitleOperation.none : SubtitleOperation.unknown;
  if (selected.deliveryUrl != null || selected.isExternal == true) return SubtitleOperation.external;
  if (selected.isTextSubtitleStream == true) return SubtitleOperation.native;
  return SubtitleOperation.burnIn;
}

HdrHandling _hdrHandling(MediaSourceInfo source) {
  final hasHdr = source.videoStreams.any((stream) {
    final range = '${stream.videoRange ?? ''} ${stream.videoRangeType ?? ''} ${stream.profile ?? ''}'.toLowerCase();
    return range.contains('hdr') || range.contains('dolby vision') || range.contains('hlg');
  });
  if (!hasHdr) return HdrHandling.none;
  final reasons = source.transcodingReasons.join(' ').toLowerCase();
  if (reasons.contains('tonemap') || reasons.contains('tone map') || reasons.contains('hdr')) return HdrHandling.toneMapToSdr;
  return HdrHandling.preserve;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
