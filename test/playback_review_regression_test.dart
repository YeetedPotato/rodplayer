import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_backend_registry.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/playback_source_switch_coordinator.dart';
import 'package:rodplayer/core/player/playback_subtitle_switch_coordinator.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/player/track_selector_sheet.dart';
import 'fakes/test_playback_engine.dart';
import 'test_support.dart';

const _subtitle = RodPlayerTrack(
    engineTrackId: 'subtitle-9',
    serverStreamIndex: 9,
    label: 'French',
    language: 'fra');
const _audio = RodPlayerTrack(
    engineTrackId: 'audio-9', serverStreamIndex: 9, label: 'Commentary');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (position, playing) in [
    (Duration.zero, true),
    (const Duration(seconds: 73), true),
    (Duration.zero, false),
    (const Duration(seconds: 73), false),
  ]) {
    testWidgets('PlayerRoute paused load; initial=$position playing=$playing',
        (tester) async {
      final runtime = _Runtime();
      final client = _client(playback: true);
      addTearDown(client.close);
      const capabilities = MethodChannel('rodplayer/playback_capabilities');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(capabilities, (_) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(capabilities, null));
      await tester.pumpWidget(MaterialApp(
          home: PlayerRoute(
        client: client,
        itemId: 'ITEM',
        startPosition: position,
        initiallyPlaying: playing,
        runtimeSetFactory: () async => PlatformPlaybackRuntimeSet(
            registry: PlaybackRuntimeRegistry(runtimes: [runtime]),
            backendRegistry: const PlaybackBackendRegistry()),
      )));
      await tester.pumpAndSettle();
      expect(find.text('surface-A'), findsOneWidget);
      final engine = runtime.created.single.engine as _Engine;
      expect(engine.loadedPaused, isTrue);
      expect(engine.loadedPlan!.playbackUri.toString(),
          'https://jellyfin.invalid/authoritative.mkv?api_key=test-token');
      expect(engine.actions,
          ['load', if (position > Duration.zero) 'seek', if (playing) 'play']);
      expect(engine.position, position);
      expect(engine.playing.value, playing);
      expect(engine.playedAfterCommit, playing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(engine.disposed, isTrue);
    });
  }

  testWidgets(
      'production subtitle command + sheet acknowledges committed replacement',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final subtitles = harness.subtitles(({
      required itemId,
      required selectedMediaSourceId,
      audioStreamIndex,
      subtitleStreamIndex,
    }) async {
      expect(selectedMediaSourceId, 'A');
      expect(audioStreamIndex, 3);
      expect(subtitleStreamIndex, 9);
      return _decision(_plan('A', subtitle: 9));
    });
    final statuses = <PlaybackCommandStatus>[];
    final commands = PlaybackCommandController.forCoordinator(
        harness.coordinator,
        renegotiateSubtitle: subtitles.select);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => TrackSelectorSheet.show(context,
                        controls: harness.coordinator.activeBinding,
                        commandController: commands),
                    child: const Text('Tracks'))))));
    await tester.tap(find.text('Tracks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('French'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to change subtitles'), findsNothing);
    expect(harness.coordinator.session.selectedSubtitle, 9);
    expect((harness.runtime.created.first.engine as _Engine).disposed, isTrue);
    expect(harness.coordinator.activeBinding.value.plan!.playbackUri,
        _plan('A').playbackUri);
    final selected = find.ancestor(
        of: find.text('French'),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected == true));
    expect(selected, findsOneWidget);
    final result = await commands.dispatchCurrent(
        command: const SelectSubtitleCommand(_subtitle),
        origin: PlaybackCommandOrigin.localUi);
    statuses.add(result.status);
    expect(statuses, [PlaybackCommandStatus.appliedReplacement]);
    expect(result.wasApplied, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  test('held subtitle A cannot supersede newer production source B', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final gate = Completer<PlaybackPlanDecision>();
    final entered = Completer<void>();
    final subtitles = harness.subtitles((
        {required itemId,
        required selectedMediaSourceId,
        audioStreamIndex,
        subtitleStreamIndex}) {
      entered.complete();
      return gate.future;
    });
    final commands = PlaybackCommandController.forCoordinator(
        harness.coordinator,
        renegotiateSubtitle: subtitles.select);
    final pending = commands.dispatchCurrent(
        command: const SelectSubtitleCommand(_subtitle),
        origin: PlaybackCommandOrigin.localUi);
    await entered.future;
    final switcher = harness.switcher();
    expect(await switcher.select(_source('B')),
        PlaybackSourceSwitchStatus.committed);
    final b = harness.coordinator.active;
    final position = b!.engine.position;
    final oldEngine = harness.runtime.created.first.engine as _Engine;
    final oldActions = List<String>.of(oldEngine.actions);
    expect(harness.coordinator.isTransitioning, isFalse,
        reason: 'obsolete subtitle negotiation must not block B');
    expect(
        (await commands.dispatchCurrent(
                command: const PauseCommand(),
                origin: PlaybackCommandOrigin.localUi))
            .status,
        PlaybackCommandStatus.executed);
    expect(
        (await commands.dispatchCurrent(
                command: SeekAbsoluteCommand(position),
                origin: PlaybackCommandOrigin.localUi))
            .status,
        PlaybackCommandStatus.executed);
    final bActions = (b.engine as _Engine).actions;
    expect(bActions.sublist(bActions.length - 2), ['pause', 'seek']);
    expect(oldEngine.actions, oldActions);
    gate.complete(_decision(_plan('A', subtitle: 9)));
    expect((await pending).status, PlaybackCommandStatus.staleSession);
    expect(harness.coordinator.active, same(b));
    expect(harness.session.activePlan.mediaSourceId, 'B');
    expect(harness.session.selectedSubtitle, 7);
    expect(harness.session.position, position);
    expect(harness.runtime.created.length, 2);
    expect(b.engine.playing.value, isFalse,
        reason: 'paused source intent is preserved');
    switcher.dispose();
  });

  test('failed source B releases blocking while stale subtitle A is held',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    await harness.coordinator.active!.engine.play();
    final a = harness.coordinator.active!;
    final gate = Completer<PlaybackPlanDecision>();
    final entered = Completer<void>();
    final subtitles = harness.subtitles(({
      required itemId,
      required selectedMediaSourceId,
      audioStreamIndex,
      subtitleStreamIndex,
    }) {
      entered.complete();
      return gate.future;
    });
    final commands = PlaybackCommandController.forCoordinator(
        harness.coordinator, renegotiateSubtitle: subtitles.select);
    final pending = commands.dispatchCurrent(
        command: const SelectSubtitleCommand(_subtitle),
        origin: PlaybackCommandOrigin.localUi);
    await entered.future;
    final switcher = harness.switcher(negotiate: ({
      required itemId,
      required mediaSourceId,
      audioStreamIndex,
      subtitleStreamIndex,
    }) async {
      throw StateError('Source negotiation unavailable');
    });
    addTearDown(switcher.dispose);
    await expectLater(switcher.select(_source('B')), throwsStateError);
    expect(harness.coordinator.active, same(a));
    expect(a.engine.playing.value, isTrue);
    expect(harness.coordinator.isTransitioning, isFalse);
    expect(
        (await commands.dispatchCurrent(
                command: const PauseCommand(),
                origin: PlaybackCommandOrigin.localUi))
            .status,
        PlaybackCommandStatus.executed);
    gate.complete(_decision(_plan('A', subtitle: 9)));
    expect((await pending).status, PlaybackCommandStatus.staleSession);
    expect(harness.session.selectedSubtitle, 7);
    expect(harness.coordinator.isTransitioning, isFalse);
  });

  test('A-B-C leases only block for C and stale releases are idempotent',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final a = harness.coordinator.beginTransition();
    final b = harness.coordinator.beginTransition();
    final c = harness.coordinator.beginTransition();
    expect(a.isCurrent, isFalse);
    expect(b.isCurrent, isFalse);
    expect(c.isCurrent, isTrue);
    b();
    b();
    a();
    a();
    expect(c.isCurrent, isTrue);
    expect(harness.coordinator.isTransitioning, isTrue);
    await harness.coordinator.activateFirst([_plan('C')], transition: c);
    c();
    expect(harness.coordinator.isTransitioning, isFalse);
    final d = harness.coordinator.beginTransition();
    a();
    b();
    c();
    expect(d.isCurrent, isTrue);
    expect(harness.coordinator.isTransitioning, isTrue);
    d();
    expect(harness.coordinator.isTransitioning, isFalse);
  });

  test('activation without a lease supersedes negotiation blocking', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final stale = harness.coordinator.beginTransition();
    await harness.coordinator.activate(_plan('B'));
    expect(stale.isCurrent, isFalse);
    expect(harness.coordinator.isTransitioning, isFalse);
    stale();
    stale();
    expect(harness.coordinator.isTransitioning, isFalse);
  });

  test('held subtitle A and source B releases cannot clear newer held source C',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final aGate = Completer<PlaybackPlanDecision>();
    final aEntered = Completer<void>();
    final subtitles = harness.subtitles(({
      required itemId,
      required selectedMediaSourceId,
      audioStreamIndex,
      subtitleStreamIndex,
    }) {
      aEntered.complete();
      return aGate.future;
    });
    final commands = PlaybackCommandController.forCoordinator(
        harness.coordinator, renegotiateSubtitle: subtitles.select);
    final a = commands.dispatchCurrent(
        command: const SelectSubtitleCommand(_subtitle),
        origin: PlaybackCommandOrigin.localUi);
    await aEntered.future;
    final gates = {
      'B': Completer<PlaybackPlanDecision>(),
      'C': Completer<PlaybackPlanDecision>(),
    };
    final entered = {'B': Completer<void>(), 'C': Completer<void>()};
    final switcher = harness.switcher(negotiate: ({
      required itemId,
      required mediaSourceId,
      audioStreamIndex,
      subtitleStreamIndex,
    }) {
      entered[mediaSourceId]!.complete();
      return gates[mediaSourceId]!.future;
    });
    addTearDown(switcher.dispose);
    final b = switcher.select(_source('B'));
    await entered['B']!.future;
    final c = switcher.select(_source('C'));
    await entered['C']!.future;
    gates['B']!.complete(_decision(_plan('B')));
    expect(await b, PlaybackSourceSwitchStatus.superseded);
    aGate.complete(_decision(_plan('A', subtitle: 9)));
    expect((await a).status, PlaybackCommandStatus.staleSession);
    expect(harness.coordinator.isTransitioning, isTrue);
    expect(harness.session.activePlan.mediaSourceId, 'A');
    expect(
        (await commands.dispatchCurrent(command: const PauseCommand(),
            origin: PlaybackCommandOrigin.localUi)).status,
        PlaybackCommandStatus.transitionInProgress);
    gates['C']!.complete(_decision(_plan('C')));
    expect(await c, PlaybackSourceSwitchStatus.committed);
    expect(harness.session.activePlan.mediaSourceId, 'C');
    expect(harness.coordinator.isTransitioning, isFalse);
    expect(
        (await commands.dispatchCurrent(command: const PauseCommand(),
            origin: PlaybackCommandOrigin.localUi)).status,
        PlaybackCommandStatus.executed);
    expect(harness.runtime.created.length, 2);
  });

  test('stale nonlocal subtitle delegate never calls renegotiation', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final old = harness.runtime.created.first;
    final tracks = harness.runtime.delegates.first;
    tracks.gate = Completer<void>();
    var calls = 0;
    final commands = PlaybackCommandController.forCoordinator(
        harness.coordinator, renegotiateSubtitle: (_) async {
      calls++;
      return null;
    });
    final pending = commands.dispatchCurrent(
        command: const SelectSubtitleCommand(_subtitle),
        origin: PlaybackCommandOrigin.localUi);
    await tracks.entered.future;
    await harness.coordinator.activate(_plan('B'));
    tracks.gate!.complete();
    expect((await pending).status, PlaybackCommandStatus.staleSession);
    expect(calls, 0);
    expect((old.engine as _Engine).disposed, isTrue);
  });

  for (final audio in [true, false]) {
    test(
        'same-plan retired ${audio ? 'audio' : 'subtitle'} completion cannot write B',
        () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      await harness.start();
      final a = harness.coordinator.active! as _Session;
      a.disposeGate = Completer<void>();
      final tracks = harness.runtime.delegates.first..local = true;
      tracks.gate = Completer<void>();
      final commands =
          PlaybackCommandController.forCoordinator(harness.coordinator);
      final pending = commands.dispatchCurrent(
          command: audio
              ? const SelectAudioCommand(_audio)
              : const SelectSubtitleCommand(_subtitle),
          origin: PlaybackCommandOrigin.localUi);
      await tracks.entered.future;
      final published = Completer<void>();
      final observer = Completer<void>();
      final replacement =
          harness.coordinator.activate(a.plan, onCommit: (_, b) async {
        published.complete();
        await observer.future;
      });
      await published.future;
      expect(harness.coordinator.active, isNot(same(a)));
      expect(a.hasLogicalWriteAuthority, isFalse);
      expect((a.engine as _Engine).disposed, isFalse);
      tracks.gate!.complete();
      expect((await pending).status, PlaybackCommandStatus.staleSession);
      expect(harness.session.selectedAudio, 3);
      expect(harness.session.selectedSubtitle, 7);
      a.disposeGate!.complete();
      await replacement;
      observer.complete();
    });
  }

  test('prepared same-plan candidate has no logical track authority', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final plan = harness.session.activePlan;
    await harness.coordinator.activate(plan, prepare: (candidate) async {
      harness.runtime.delegates.last.local = true;
      expect(candidate.hasLogicalWriteAuthority, isFalse);
      await candidate.tracks!.selectAudio(_audio);
      await candidate.tracks!.selectSubtitle(_subtitle);
      expect(harness.session.selectedAudio, 3);
      expect(harness.session.selectedSubtitle, 7);
    });
    expect(harness.coordinator.active!.hasLogicalWriteAuthority, isTrue);
  });

  test('hung observer does not own retirement or queued activation', () {
    fakeAsync((clock) {
      final harness = _Harness();
      final observer = Completer<void>();
      harness.start();
      clock.flushMicrotasks();
      var completed = false;
      harness.coordinator
          .activate(_plan('B'), onCommit: (_, __) => observer.future)
          .then((_) => completed = true);
      clock.flushMicrotasks();
      expect(completed, isTrue);
      expect(
          (harness.runtime.created.first.engine as _Engine).disposed, isTrue);
      harness.coordinator.activate(_plan('C'));
      clock.flushMicrotasks();
      expect(harness.session.activePlan.mediaSourceId, 'C');
      harness.dispose();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(harness.coordinator.active, isNull);
    });
  });

  test('after-commit observer can await a newer activation without deadlock',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.start();
    final finished = Completer<void>();
    final b = harness.coordinator.activate(_plan('B'), onCommit: (_, __) async {
      await harness.coordinator.activate(_plan('C'));
      finished.complete();
    });
    await expectLater(b, throwsA(isA<PlaybackActivationSupersededException>()));
    await finished.future;
    expect(harness.session.activePlan.mediaSourceId, 'C');
    expect((harness.runtime.created.first.engine as _Engine).disposed, isTrue);
  });
}

class _Harness {
  final runtime = _Runtime();
  late final session = LogicalPlaybackSession(
      id: 'logical', itemId: 'ITEM', activePlan: _plan('A'));
  late final coordinator = PlaybackRuntimeCoordinator(
      registry: PlaybackRuntimeRegistry(runtimes: [runtime]), session: session);
  final client = _client();
  late final reporter = PlaybackReporter(client: client, session: session);
  Future<void> start() async {
    await coordinator.activate(session.activePlan);
    (coordinator.active!.engine as _Engine).position =
        const Duration(seconds: 41);
  }

  PlaybackSubtitleSwitchCoordinator subtitles(SubtitleNegotiation negotiate) =>
      PlaybackSubtitleSwitchCoordinator(
          coordinator: coordinator,
          negotiate: negotiate,
          invalidateRecovery: () {});
  PlaybackSourceSwitchCoordinator switcher({PlaybackSourceNegotiation? negotiate}) => PlaybackSourceSwitchCoordinator(
      session: session,
      runtimeCoordinator: coordinator,
      reporter: reporter,
      invalidateRecovery: () {},
      onCommitted: (_, __) async {},
      negotiate: negotiate ?? (
              {required itemId,
              required mediaSourceId,
              audioStreamIndex,
              subtitleStreamIndex}) async =>
          _decision(_plan(mediaSourceId)));
  Future<void> dispose() async {
    await coordinator.dispose();
    client.close();
  }
}

class _Runtime implements PlaybackBackendRuntime {
  final created = <_Session>[];
  final delegates = <_Tracks>[];
  @override
  String get backendId => 'media_kit';
  @override
  bool get isAvailable => true;
  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    final engine = _Engine();
    await engine.load(plan);
    final tracks = _Tracks(selected: plan.selectedSubtitleStreamIndex == 9);
    delegates.add(tracks);
    final session = _Session(plan: plan, engine: engine, tracks: tracks);
    engine.runtime = session;
    created.add(session);
    return session;
  }
}

class _Session extends PlaybackRuntimeSession {
  _Session({required super.plan, required super.engine, required super.tracks})
      : super(runtimeId: 'media_kit', surface: _Surface(plan.mediaSourceId));
  Completer<void>? disposeGate;
  @override
  Future<void> dispose() async {
    await disposeGate?.future;
    await super.dispose();
  }
}

class _Engine extends TestPlaybackEngine {
  final actions = <String>[];
  bool loadedPaused = false;
  bool playedAfterCommit = false;
  PlaybackRuntimeSession? runtime;
  @override
  Future<void> load(PlaybackPlan plan) async {
    actions.add('load');
    await super.load(plan);
    loadedPaused = !playing.value;
  }

  @override
  Future<void> play() async {
    actions.add('play');
    playedAfterCommit = runtime!.hasLogicalWriteAuthority;
    await super.play();
  }

  @override
  Future<void> seek(Duration position) async {
    actions.add('seek');
    await super.seek(position);
  }

  @override
  Future<void> pause() async {
    actions.add('pause');
    await super.pause();
  }
}

class _Surface implements PlaybackVideoSurface {
  _Surface(this.source);
  final String source;
  @override
  Widget build(BuildContext context) => Text('surface-$source');
}

class _Tracks extends TrackSelectionController {
  _Tracks({this.selected = false});
  bool selected;
  bool local = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  @override
  TrackSelectionCapabilities get capabilities =>
      const TrackSelectionCapabilities(
          audioSelection: CapabilitySupport.supported,
          subtitleSelection: CapabilitySupport.supported);
  @override
  List<RodPlayerTrack> get audioTracks => [_audio];
  @override
  List<RodPlayerTrack> get subtitleTracks => [_subtitle];
  @override
  RodPlayerTrack? get selectedAudio => null;
  @override
  RodPlayerTrack? get selectedSubtitle => selected ? _subtitle : null;
  Future<TrackSwitchResult> result() async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    return TrackSwitchResult(
        mode:
            local ? TrackSwitchMode.local : TrackSwitchMode.serverRenegotiation,
        serverStreamIndex: 9);
  }

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) => result();
  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) => result();
}

MediaSourceInfo _source(String id) =>
    MediaSourceInfo.fromJson({'Id': id, 'MediaStreams': []});
PlaybackPlan _plan(String source, {int subtitle = 7}) => PlaybackPlan(
    itemId: 'ITEM',
    mediaSourceId: source,
    playSessionId: 'session-$source-$subtitle',
    playMethod: PlayMethod.directStream,
    engineId: 'media_kit',
    playbackUri: Uri.parse('https://jellyfin.invalid/authoritative-$source'),
    selectedAudioStreamIndex: 3,
    selectedSubtitleStreamIndex: subtitle,
    source: _source(source));
PlaybackPlanDecision _decision(PlaybackPlan plan) {
  final candidate = PlaybackBackendCandidate(
      backend: const PlaybackBackendDescriptor(
          id: 'media_kit',
          displayName: 'Test',
          availability: BackendAvailability.available,
          priority: 0,
          capabilities:
              PlaybackBackendCapabilities(id: 'media_kit', name: 'Test')),
      plan: plan,
      score: const PlaybackPlanScore(total: 1, components: {}));
  return PlaybackPlanDecision(selected: candidate, candidates: [candidate]);
}

JellyfinApiClient _client({bool playback = false}) => JellyfinApiClient(
    baseUrl: 'https://jellyfin.invalid',
    identity: testIdentity,
    serverId: testServerId,
    userId: 'user',
    accessToken: 'test-token',
    client: MockClient((request) async {
      if (playback && request.url.path.endsWith('/PlaybackInfo')) {
        return http.Response(
            jsonEncode({
              'PlaySessionId': 'session-A',
              'MediaSources': [
                {
                  'Id': 'A',
                  'DirectStreamUrl':
                      'https://jellyfin.invalid/authoritative.mkv?api_key=test-token',
                  'PlayMethod': 'DirectStream',
                  'MediaStreams': []
                }
              ]
            }),
            200);
      }
      if (request.url.path == '/Users/user/Items/ITEM')
        return http.Response('{"Id":"ITEM","Name":"Movie"}', 200);
      return http.Response('{}', 200);
    }));
