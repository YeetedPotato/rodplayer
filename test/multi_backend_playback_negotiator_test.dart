import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/api/models/playback_info_request.dart';
import 'package:rodplayer/core/api/models/playback_info_response.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  test('only available routable backends produce PlaybackInfo requests', () async {
    final requester = _Requester(<String, PlaybackInfoResponse>{
      'media_kit': _response('direct', PlayMethod.directPlay),
      'available_native': _response('native', PlayMethod.directPlay),
    });
    final decision = await _negotiate(requester, backends: <PlaybackBackendDescriptor>[
      _backend('media_kit', priority: 0),
      _backend('future', availability: BackendAvailability.unavailable, priority: 1),
      _backend('available_native', priority: 2),
    ], runtimes: const <PlaybackBackendRuntime>[_Runtime('media_kit'), _Runtime('available_native')]);

    expect(requester.requestedBackendIds, <String>['media_kit', 'available_native']);
    expect(decision.rejectedCandidates.map((c) => c.backend.id), isNot(contains('future')));
  });

  test('unavailable future backends are skipped', () async {
    final requester = _Requester(<String, PlaybackInfoResponse>{'media_kit': _response('direct', PlayMethod.directPlay)});

    await _negotiate(requester, backends: <PlaybackBackendDescriptor>[
      _backend('media_kit'),
      _backend('future', availability: BackendAvailability.unavailable, priority: -1),
    ]);

    expect(requester.requestedBackendIds, <String>['media_kit']);
  });

  test('direct play beats equivalent direct stream', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{
      'media_kit': PlaybackInfoResponse(mediaSources: <MediaSourceInfo>[
        _source('stream', PlayMethod.directStream),
        _source('direct', PlayMethod.directPlay),
      ], raw: const <String, dynamic>{}),
    }));

    expect(decision.plan.mediaSourceId, 'direct');
  });

  test('video-copy audio-transcode beats video transcode', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    final copyVideo = scorer.score(_plan('a', PlayMethod.transcode, videoCopied: true, audioCopied: false), profile);
    final videoTranscode = scorer.score(_plan('b', PlayMethod.transcode, videoCopied: false, audioCopied: true), profile);

    expect(copyVideo.total, greaterThan(videoTranscode.total));
  });

  test('subtitle external/native beats burn-in', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    expect(scorer.score(_plan('external', PlayMethod.directPlay, subtitle: SubtitleOperation.external), profile).total, greaterThan(scorer.score(_plan('burn', PlayMethod.directPlay, subtitle: SubtitleOperation.burnIn), profile).total));
  });

  test('HDR-preserving plan beats HDR to SDR', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    expect(scorer.score(_plan('hdr', PlayMethod.directPlay, hdr: HdrHandling.preserve), profile).total, greaterThan(scorer.score(_plan('sdr', PlayMethod.directPlay, hdr: HdrHandling.toneMapToSdr), profile).total));
  });

  test('deterministic ties use backend id then source id', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{
      'b_backend': _response('b-source', PlayMethod.directPlay),
      'a_backend': _response('a-source', PlayMethod.directPlay),
    }), backends: <PlaybackBackendDescriptor>[
      _backend('b_backend', priority: 1),
      _backend('a_backend', priority: 1),
    ], runtimes: const <PlaybackBackendRuntime>[_Runtime('a_backend'), _Runtime('b_backend')]);

    expect(decision.selectedBackendId, 'a_backend');
  });

  test('stable backend priority tie-break wins before backend id', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{
      'a_backend': _response('a-source', PlayMethod.directPlay),
      'b_backend': _response('b-source', PlayMethod.directPlay),
    }), backends: <PlaybackBackendDescriptor>[
      _backend('a_backend', priority: 5),
      _backend('b_backend', priority: 1),
    ], runtimes: const <PlaybackBackendRuntime>[_Runtime('a_backend'), _Runtime('b_backend')]);

    expect(decision.selectedBackendId, 'b_backend');
  });

  test('server PlaybackInfo decision remains authoritative', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{'media_kit': _response('stream', PlayMethod.directStream)}));

    expect(decision.plan.playMethod, PlayMethod.directStream);
    expect(decision.plan.playbackUri.path, '/Videos/stream/stream.mkv');
  });

  test('no hand-built transcode URLs', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{'media_kit': _response('transcoded', PlayMethod.transcode)}));

    expect(decision.plan.playbackUri.path, '/server-built/transcoded.m3u8');
  });

  test('media kit only compatibility remains selected', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{'media_kit': _response('direct', PlayMethod.directPlay)}));

    expect(decision.selectedBackendId, 'media_kit');
    expect(decision.plan.engineId, 'media_kit');
  });

  test('logical session remains separate from server PlaySessionId', () {
    final first = _plan('one', PlayMethod.directPlay, playSessionId: 'server-one');
    final second = _plan('two', PlayMethod.directPlay, playSessionId: 'server-two');
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: first);

    session.activatePlan(second);

    expect(session.id, 'logical');
    expect(session.activeServerSession.playSessionId, 'server-two');
  });

  test('track switch mode normalization preserves server renegotiation', () async {
    final controller = _FakeTrackSelectionController(mode: TrackSwitchMode.serverRenegotiation);

    final result = await controller.selectAudio(const RodPlayerTrack(engineTrackId: 'a', label: 'Audio', serverStreamIndex: 1));

    expect(result.mode, TrackSwitchMode.serverRenegotiation);
  });

  test('unknown capability does not get treated as supported', () {
    final score = const PlaybackPlanScorer().score(_plan('direct', PlayMethod.directPlay), _profile(_backend('unknown', hardwareDecode: CapabilitySupport.unknown)));

    expect(score.components['hardwareDecode'], 0);
  });

  test('effective profile controls hardware and passthrough scoring', () {
    final rawSupported = _backend('raw', hardwareDecode: CapabilitySupport.supported, passthrough: CapabilitySupport.supported);
    final effectiveUnknown = _profile(_backend('raw', hardwareDecode: CapabilitySupport.unknown, passthrough: CapabilitySupport.unsupported));
    final score = const PlaybackPlanScorer().score(_plan('direct', PlayMethod.directPlay), effectiveUnknown);

    expect(rawSupported.capabilities.hardwareDecode, CapabilitySupport.supported);
    expect(score.components['hardwareDecode'], 0);
    expect(score.components['audioPreservation'], 0);
  });

  test('direct play beats video-copy audio-transcode', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    expect(scorer.score(_plan('direct', PlayMethod.directPlay), profile).total, greaterThan(scorer.score(_plan('copy-audio-transcode', PlayMethod.transcode, videoCopied: true, audioCopied: false), profile).total));
  });

  test('video-copy audio-transcode beats container-only direct stream', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    expect(scorer.score(_plan('copy-audio-transcode', PlayMethod.transcode, videoCopied: true, audioCopied: false), profile).total, greaterThan(scorer.score(_plan('container-stream', PlayMethod.directStream), profile).total));
  });

  test('container-only direct stream beats video transcode', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    expect(scorer.score(_plan('container-stream', PlayMethod.directStream), profile).total, greaterThan(scorer.score(_plan('video-transcode', PlayMethod.transcode, videoCopied: false, audioCopied: true), profile).total));
  });

  test('video-transcode audio-copy beats full transcode', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));

    expect(scorer.score(_plan('video-transcode', PlayMethod.transcode, videoCopied: false, audioCopied: true), profile).total, greaterThan(scorer.score(_plan('full-transcode', PlayMethod.transcode, videoCopied: false, audioCopied: false), profile).total));
  });

  test('preservation tier enforces locked destructive order', () {
    final scorer = const PlaybackPlanScorer();
    final profile = _profile(_backend('media_kit'));
    final scores = <int>[
      scorer.score(_plan('direct', PlayMethod.directPlay), profile).total,
      scorer.score(_plan('copy-audio-transcode', PlayMethod.transcode, videoCopied: true, audioCopied: false), profile).total,
      scorer.score(_plan('container-stream', PlayMethod.directStream), profile).total,
      scorer.score(_plan('video-transcode', PlayMethod.transcode, videoCopied: false, audioCopied: true), profile).total,
      scorer.score(_plan('full-transcode', PlayMethod.transcode, videoCopied: false, audioCopied: false), profile).total,
    ];

    for (var i = 0; i < scores.length - 1; i += 1) {
      expect(scores[i], greaterThan(scores[i + 1]));
    }
  });

  test('fallback prefers direct play support over transcode URL', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{
      'media_kit': PlaybackInfoResponse(mediaSources: <MediaSourceInfo>[
        _sourceWithFlags('flags', supportsDirectPlay: true, supportsDirectStream: true, supportsTranscoding: true, transcodingUrl: '/server-built/flags.m3u8'),
      ], raw: const <String, dynamic>{}),
    }));

    expect(decision.plan.playMethod, PlayMethod.directPlay);
  });

  test('fallback prefers direct stream support before transcode URL', () async {
    final decision = await _negotiate(_Requester(<String, PlaybackInfoResponse>{
      'media_kit': PlaybackInfoResponse(mediaSources: <MediaSourceInfo>[
        _sourceWithFlags('flags', supportsDirectPlay: false, supportsDirectStream: true, supportsTranscoding: true, directStreamUrl: '/Videos/flags/stream.mkv', transcodingUrl: '/server-built/flags.m3u8'),
      ], raw: const <String, dynamic>{}),
    }));

    expect(decision.plan.playMethod, PlayMethod.directStream);
    expect(decision.plan.playbackUri.path, '/Videos/flags/stream.mkv');
  });
}

Future<PlaybackPlanDecision> _negotiate(
  _Requester requester, {
  List<PlaybackBackendDescriptor>? backends,
  List<PlaybackBackendRuntime> runtimes = const <PlaybackBackendRuntime>[_Runtime('media_kit')],
}) {
  final environment = _environment(backends ?? <PlaybackBackendDescriptor>[_backend('media_kit')]);
  return MultiBackendPlaybackNegotiator(requester: requester, runtimeRegistry: PlaybackRuntimeRegistry(runtimes: runtimes)).negotiate(environment: environment, itemId: 'item');
}

PlaybackEnvironment _environment(List<PlaybackBackendDescriptor> backends) {
  final profiles = <EffectivePlaybackProfile>[
    for (final backend in backends)
      EffectivePlaybackProfile(
        backendId: backend.id,
        capabilities: backend.capabilities,
        deviceProfile: _deviceProfile(),
      ),
  ];
  return PlaybackEnvironment(
    identity: const DeviceIdentity(installationId: 'id', clientName: 'RodPlayer', appVersion: 'test', platformFamily: PlatformFamily.unknown, deviceName: 'Test'),
    device: const DeviceCapabilities(platformLabel: 'Test'),
    compute: const ComputeCapabilities(),
    display: const DisplayCapabilities(),
    audio: const AudioCapabilities(),
    network: const NetworkCapabilities(),
    backends: backends,
    effectiveProfiles: profiles,
  );
}

PlaybackBackendDescriptor _backend(String id, {BackendAvailability availability = BackendAvailability.available, int priority = 0, CapabilitySupport hardwareDecode = CapabilitySupport.unknown, CapabilitySupport passthrough = CapabilitySupport.unknown}) => PlaybackBackendDescriptor(
      id: id,
      displayName: id,
      availability: availability,
      priority: priority,
      capabilities: PlaybackBackendCapabilities(id: id, name: id, hardwareDecode: hardwareDecode, passthrough: passthrough),
    );

EffectivePlaybackProfile _profile(PlaybackBackendDescriptor backend) => EffectivePlaybackProfile(backendId: backend.id, capabilities: backend.capabilities, deviceProfile: _deviceProfile());

EffectiveDeviceProfile _deviceProfile() => const EffectiveDeviceProfile(
      maxStreamingBitrate: 120000000,
      directPlayRules: <DirectPlayCapabilityRule>[],
      transcodingRules: <TranscodingCapabilityRule>[],
      videoCodecRules: <VideoCodecCapabilityRule>[],
      audioCodecRules: <AudioCodecCapabilityRule>[],
      subtitleRules: <SubtitleCapabilityRule>[],
    );

PlaybackInfoResponse _response(String sourceId, PlayMethod method) => PlaybackInfoResponse(mediaSources: <MediaSourceInfo>[_source(sourceId, method)], playSessionId: 'play-$sourceId', raw: const <String, dynamic>{});

MediaSourceInfo _source(String id, PlayMethod method) => MediaSourceInfo.fromJson(<String, dynamic>{
      'Id': id,
      'PlayMethod': method.name,
      if (method == PlayMethod.directStream) 'DirectStreamUrl': '/Videos/$id/stream.mkv',
      if (method == PlayMethod.transcode) 'TranscodingUrl': '/server-built/$id.m3u8',
      if (method == PlayMethod.transcode) 'VideoStreamCopy': id.contains('copy'),
      if (method == PlayMethod.transcode) 'AudioStreamCopy': id.contains('audio-copy'),
      'MediaStreams': <Map<String, dynamic>>[
        <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'h264'},
        <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Codec': 'aac'},
      ],
    });

MediaSourceInfo _sourceWithFlags(
  String id, {
  required bool supportsDirectPlay,
  required bool supportsDirectStream,
  required bool supportsTranscoding,
  String? directStreamUrl,
  String? transcodingUrl,
}) =>
    MediaSourceInfo.fromJson(<String, dynamic>{
      'Id': id,
      'SupportsDirectPlay': supportsDirectPlay,
      'SupportsDirectStream': supportsDirectStream,
      'SupportsTranscoding': supportsTranscoding,
      if (directStreamUrl != null) 'DirectStreamUrl': directStreamUrl,
      if (transcodingUrl != null) 'TranscodingUrl': transcodingUrl,
      'MediaStreams': <Map<String, dynamic>>[
        <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': 'h264'},
        <String, dynamic>{'Index': 1, 'Type': 'Audio', 'Codec': 'aac'},
      ],
    });

PlaybackPlan _plan(
  String id,
  PlayMethod method, {
  bool videoCopied = true,
  bool audioCopied = true,
  SubtitleOperation subtitle = SubtitleOperation.none,
  HdrHandling hdr = HdrHandling.none,
  String? playSessionId,
}) =>
    PlaybackPlan(
      itemId: 'item',
      mediaSourceId: id,
      playSessionId: playSessionId,
      playMethod: method,
      playbackUri: Uri.parse('https://media/$id'),
      engineId: 'media_kit',
      source: _source(id, method),
      videoCopied: videoCopied,
      audioCopied: audioCopied,
      deliveryMode: switch (method) {
        PlayMethod.directPlay => PlaybackDeliveryMode.directPlay,
        PlayMethod.directStream => PlaybackDeliveryMode.directStream,
        PlayMethod.transcode => PlaybackDeliveryMode.transcode,
      },
      videoOperation: videoCopied ? VideoOperation.copy : VideoOperation.transcode,
      audioOperation: audioCopied ? AudioOperation.copy : AudioOperation.transcode,
      subtitleOperation: subtitle,
      hdrHandling: hdr,
    );

class _Requester implements PlaybackInfoRequester {
  _Requester(this.responsesByBackendId);

  final Map<String, PlaybackInfoResponse> responsesByBackendId;
  final requestedBackendIds = <String>[];

  @override
  String? get userId => 'user';

  @override
  Future<PlaybackInfoResponse> getPlaybackInfo(PlaybackInfoRequest request) async {
    return responsesByBackendId.values.first;
  }

  @override
  Future<PlaybackInfoResponse> getPlaybackInfoForBackend(PlaybackBackendDescriptor backend, PlaybackInfoRequest request) async {
    final backendId = backend.id;
    requestedBackendIds.add(backendId);
    return responsesByBackendId[backendId] ?? _response(backendId, PlayMethod.directPlay);
  }

  @override
  Uri buildDirectPlayUri({required String itemId, required String mediaSourceId, String? playSessionId, int? audioStreamIndex, int? subtitleStreamIndex}) => Uri.parse('https://media.example.com/Videos/$itemId/stream?mediaSourceId=$mediaSourceId');

  @override
  Uri? resolvePlaybackUri(String uriText) => Uri.parse('https://media.example.com$uriText');
}

class _Runtime implements PlaybackBackendRuntime {
  const _Runtime(this.backendId);

  @override
  final String backendId;

  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final engine = TestPlaybackEngine(id: backendId);
    await engine.load(plan);
    return PlaybackRuntimeSession(runtimeId: backendId, plan: plan, engine: engine);
  }
}

class _FakeTrackSelectionController implements TrackSelectionController {
  const _FakeTrackSelectionController({required this.mode});

  final TrackSwitchMode mode;

  @override
  List<RodPlayerTrack> get audioTracks => const <RodPlayerTrack>[];

  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];

  @override
  RodPlayerTrack? get selectedAudio => null;

  @override
  RodPlayerTrack? get selectedSubtitle => null;

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async => TrackSwitchResult(mode: mode, serverStreamIndex: track.serverStreamIndex);

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async => TrackSwitchResult(mode: mode, serverStreamIndex: track?.serverStreamIndex);
}
