import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/multi_backend_playback_negotiator.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_source_switch_coordinator.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';

import 'fakes/test_playback_engine.dart';
import 'test_support.dart';

const _position = Duration(microseconds: 545933000);

void main() {
  test('source notification failure retains matching binding plan and reporting identity', () async {
    final harness = _SwitchHarness()..commitError = StateError('notification');
    addTearDown(harness.dispose);
    await harness.start();
    await harness.reporter.started(_position);
    expect(
      await harness.switcher.select(_source('B')),
      PlaybackSourceSwitchStatus.committed,
    );
    await harness.reporter.synchronize(_position);
    expect(
      harness.coordinator.activeBinding.value.plan,
      same(harness.session.activePlan),
    );
    expect(harness.session.activePlan.mediaSourceId, 'B');
    expect(
      harness.coordinator.activeBinding.value.engine,
      same(harness.coordinator.active!.engine),
    );
    expect(harness.initialEngine.disposed, isTrue);
    expect(harness.coordinator.diagnostics?.observerFailure, isA<StateError>());
    expect(harness.reports.last['body']['PlaySessionId'], 'NEW-SESSION');
    expect(harness.reports.last['body']['MediaSourceId'], 'B');
  });

  test(
    'seek and pause are rejected throughout pending source negotiation',
    () async {
      final harness = _SwitchHarness();
      addTearDown(harness.dispose);
      await harness.start();
      harness.initialEngine.playing.value = true;
      final gate = Completer<PlaybackPlanDecision>();
      harness.negotiationGates['B'] = gate;
      final entered = Completer<void>();
      harness.negotiationEntered = entered;
      final commands = PlaybackCommandController.forCoordinator(
        harness.coordinator,
      );
      final b = harness.switcher.select(_source('B'));
      await entered.future;
      for (final command in <PlaybackCommand>[
        const SeekAbsoluteCommand(Duration(seconds: 9)),
        const PauseCommand(),
      ]) {
        final result = await commands.dispatchCurrent(
          command: command,
          origin: PlaybackCommandOrigin.localUi,
        );
        expect(result.status, PlaybackCommandStatus.transitionInProgress);
      }
      expect(harness.initialEngine.position, _position);
      // C supersedes B; no user command changes the preserved handoff.
      harness.negotiationEntered = null;
      await harness.switcher.select(_source('C'));
      gate.complete(_decision(_plan('B', 'NEW-SESSION')));
      expect(await b, PlaybackSourceSwitchStatus.superseded);
      expect(harness.coordinator.active!.engine.position, _position);
      expect(harness.coordinator.active!.engine.playing.value, isTrue);
      expect(
        (await commands.dispatchCurrent(
          command: const PauseCommand(),
          origin: PlaybackCommandOrigin.localUi,
        )).status,
        PlaybackCommandStatus.executed,
      );
    },
  );
  test(
    'SOURCE SWITCH SUCCESS E2E preserves position and reporting ownership',
    () async {
      final harness = _SwitchHarness();
      addTearDown(harness.dispose);
      await harness.start();
      harness.initialEngine
        ..position = _position
        ..playing.value = true;
      await harness.reporter.started(_position);

      final status = await harness.switcher.select(_source('B'));
      await harness.reporter.synchronize(_position);

      expect(status, PlaybackSourceSwitchStatus.committed);
      expect(harness.requests.single, <String, Object?>{
        'itemId': 'ITEM',
        'mediaSourceId': 'B',
        'audioStreamIndex': 3,
        'subtitleStreamIndex': 7,
      });
      expect(harness.switcherHandoffPosition, _position);
      expect(harness.runtime.opened.last.mediaSourceId, 'B');
      expect(harness.runtime.opened.last.playSessionId, 'NEW-SESSION');
      expect(harness.session.activePlan.mediaSourceId, 'B');
      expect(harness.session.activePlan.playSessionId, 'NEW-SESSION');
      expect(harness.session.activePlan.playSessionId, isNot('OLD-SESSION'));
      expect(
        (harness.coordinator.activeBinding.value.surface as _SourceSurface)
            .source,
        'B',
      );
      expect(harness.session.selectedAudio, 3);
      expect(harness.session.selectedSubtitle, 7);
      expect(harness.reports.first['body']['PositionTicks'], 5459330000);
      final replacement =
          harness.coordinator.active!.engine as TestPlaybackEngine;
      expect(replacement.position, _position);
      expect(replacement.playing.value, isTrue);
      expect(harness.initialEngine.disposed, isTrue);

      final stopOld = harness.reports.where(
        (entry) =>
            entry['path'] == '/Sessions/Playing/Stopped' &&
            entry['body']['PlaySessionId'] == 'OLD-SESSION',
      );
      expect(stopOld, hasLength(1));
      expect(stopOld.single['body'], containsPair('ItemId', 'ITEM'));
      expect(stopOld.single['body'], containsPair('MediaSourceId', 'A'));
      final startNew = harness.reports.where(
        (entry) =>
            entry['path'] == '/Sessions/Playing' &&
            entry['body']['PlaySessionId'] == 'NEW-SESSION',
      );
      expect(startNew, hasLength(1));
      expect(startNew.single['body'], containsPair('ItemId', 'ITEM'));
      expect(startNew.single['body'], containsPair('MediaSourceId', 'B'));
      expect(
        startNew.single['body'],
        containsPair('PositionTicks', 5459330000),
      );
      expect(startNew.single['body'], containsPair('AudioStreamIndex', 3));
      expect(startNew.single['body'], containsPair('SubtitleStreamIndex', 7));
      final oldStopIndex = harness.reports.indexWhere(
        (entry) =>
            entry['path'] == '/Sessions/Playing/Stopped' &&
            entry['body']['PlaySessionId'] == 'OLD-SESSION',
      );
      final newStartIndex = harness.reports.indexWhere(
        (entry) =>
            entry['path'] == '/Sessions/Playing' &&
            entry['body']['PlaySessionId'] == 'NEW-SESSION',
      );
      expect(oldStopIndex, lessThan(newStartIndex));

      // A delayed position callback after the handoff is attributed to the
      // committed target. The reporter's serialized transition has already
      // terminally stopped OLD-SESSION exactly once.
      await harness.reporter.progress(_position, const Duration(minutes: 90));
      final lateProgress = harness.reports.last;
      expect(lateProgress['path'], '/Sessions/Playing/Progress');
      expect(lateProgress['body']['PlaySessionId'], 'NEW-SESSION');
      expect(lateProgress['body']['MediaSourceId'], 'B');
      expect(
        harness.reports.where(
          (entry) =>
              entry['path'] == '/Sessions/Playing/Stopped' &&
              entry['body']['PlaySessionId'] == 'OLD-SESSION',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'SOURCE SWITCH NEGOTIATION FAILURE rolls back without stopping old',
    () async {
      final harness = _SwitchHarness()
        ..negotiationError = StateError('offline');
      addTearDown(harness.dispose);
      await harness.start();
      harness.initialEngine
        ..position = _position
        ..playing.value = true;
      await harness.reporter.started(_position);

      await expectLater(
        harness.switcher.select(_source('B')),
        throwsA(isA<StateError>()),
      );

      expect(harness.coordinator.active!.engine, same(harness.initialEngine));
      expect(
        (harness.coordinator.activeBinding.value.surface as _SourceSurface)
            .source,
        'A',
      );
      expect(harness.session.activePlan.mediaSourceId, 'A');
      expect(harness.session.activePlan.playSessionId, 'OLD-SESSION');
      expect(harness.initialEngine.position, _position);
      expect(harness.initialEngine.playing.value, isTrue);
      expect(harness.runtime.opened.map((plan) => plan.mediaSourceId), <String>[
        'A',
      ]);
      expect(harness.reports, hasLength(1));
      expect(harness.reports.single['body']['PlaySessionId'], 'OLD-SESSION');
    },
  );

  test(
    'SOURCE SWITCH OPEN FAILURE rolls back before reporting commit',
    () async {
      final harness = _SwitchHarness()..failOpenSourceId = 'B';
      addTearDown(harness.dispose);
      await harness.start();
      harness.initialEngine
        ..position = _position
        ..playing.value = true;
      await harness.reporter.started(_position);

      await expectLater(
        harness.switcher.select(_source('B')),
        throwsA(isA<PlaybackActivationException>()),
      );

      expect(harness.runtime.opened.map((plan) => plan.mediaSourceId), <String>[
        'A',
        'B',
      ]);
      expect(harness.coordinator.active!.engine, same(harness.initialEngine));
      expect(
        (harness.coordinator.activeBinding.value.surface as _SourceSurface)
            .source,
        'A',
      );
      expect(harness.session.activePlan.mediaSourceId, 'A');
      expect(harness.session.activePlan.playSessionId, 'OLD-SESSION');
      expect(harness.initialEngine.position, _position);
      expect(harness.initialEngine.playing.value, isTrue);
      expect(harness.reports, hasLength(1));
      expect(harness.reports.single['body']['PlaySessionId'], 'OLD-SESSION');
    },
  );

  test(
    'SOURCE SWITCH SUPERSEDED GENERATION prevents B from committing',
    () async {
      final gate = Completer<PlaybackPlanDecision>();
      final harness = _SwitchHarness()..negotiationGates['B'] = gate;
      addTearDown(harness.dispose);
      await harness.start();
      harness.initialEngine
        ..position = _position
        ..playing.value = true;
      await harness.reporter.started(_position);

      final bFuture = harness.switcher.select(_source('B'));
      await _until(() => harness.requests.length == 1);
      final cFuture = harness.switcher.select(_source('C'));
      await cFuture;
      gate.completeError(StateError('stale B negotiation failure'));
      final bStatus = await bFuture;
      await harness.reporter.synchronize(_position);

      expect(bStatus, PlaybackSourceSwitchStatus.superseded);
      expect(harness.coordinator.active?.plan.mediaSourceId, 'C');
      expect(harness.coordinator.active?.plan.playSessionId, 'NEW-C');
      expect(
        (harness.coordinator.activeBinding.value.surface as _SourceSurface)
            .source,
        'C',
      );
      expect(harness.runtime.opened.map((plan) => plan.mediaSourceId), <String>[
        'A',
        'C',
      ]);
      expect(harness.committedSources, <String>['C']);
      expect(
        harness.reports.where(
          (entry) =>
              entry['path'] == '/Sessions/Playing' &&
              entry['body']['PlaySessionId'] == 'NEW-B',
        ),
        isEmpty,
      );
    },
  );
}

class _SwitchHarness {
  final reports = <Map<String, dynamic>>[];
  final requests = <Map<String, Object?>>[];
  final committedSources = <String>[];
  final negotiationGates = <String, Completer<PlaybackPlanDecision>>{};
  Object? negotiationError;
  Object? commitError;
  Completer<void>? negotiationEntered;
  String? failOpenSourceId;
  late final client = JellyfinApiClient(
    baseUrl: 'https://jellyfin.invalid',
    identity: testIdentity,
    serverId: testServerId,
    userId: 'user',
    accessToken: 'test-token',
    client: MockClient((request) async {
      reports.add(<String, dynamic>{
        'path': request.url.path,
        'body': jsonDecode(request.body) as Map<String, dynamic>,
      });
      return http.Response('', 204);
    }),
  );
  final initialEngine = TestPlaybackEngine(id: 'fake');
  late final session =
      LogicalPlaybackSession(
          id: 'logical',
          itemId: 'ITEM',
          activePlan: _plan('A', 'OLD-SESSION'),
        )
        ..selectedAudio = 3
        ..selectedSubtitle = 7;
  late final runtime = _SwitchRuntime(
    initialEngine: initialEngine,
    shouldFailOpen: (sourceId) => sourceId == failOpenSourceId,
  );
  late final coordinator = PlaybackRuntimeCoordinator(
    registry: PlaybackRuntimeRegistry(
      runtimes: <PlaybackBackendRuntime>[runtime],
    ),
    session: session,
  );
  late final reporter = PlaybackReporter(client: client, session: session);
  late final switcher = PlaybackSourceSwitchCoordinator(
    session: session,
    runtimeCoordinator: coordinator,
    negotiate:
        ({
          required itemId,
          required mediaSourceId,
          audioStreamIndex,
          subtitleStreamIndex,
        }) async {
          requests.add(<String, Object?>{
            'itemId': itemId,
            'mediaSourceId': mediaSourceId,
            'audioStreamIndex': audioStreamIndex,
            'subtitleStreamIndex': subtitleStreamIndex,
          });
          negotiationEntered?.complete();
          final error = negotiationError;
          if (error != null) throw error;
          final gate = negotiationGates[mediaSourceId];
          if (gate != null) return gate.future;
          return _decision(
            _plan(
              mediaSourceId,
              mediaSourceId == 'B' ? 'NEW-SESSION' : 'NEW-$mediaSourceId',
            ),
          );
        },
    reporter: reporter,
    invalidateRecovery: () {},
    onCommitted: (handoff, replacement) async {
      capturedHandoffPositions.add(handoff.position);
      committedSources.add(replacement.plan.mediaSourceId);
      if (commitError != null) throw commitError!;
    },
  );

  final capturedHandoffPositions = <Duration>[];
  Duration? get switcherHandoffPosition =>
      capturedHandoffPositions.isEmpty ? null : capturedHandoffPositions.last;

  Future<void> start() async {
    await coordinator.activate(session.activePlan);
    initialEngine.position = _position;
    initialEngine.playing.value = false;
  }

  Future<void> dispose() async {
    switcher.dispose();
    await reporter.stopped(session.position);
    await coordinator.dispose();
    client.close();
  }
}

class _SwitchRuntime implements PlaybackBackendRuntime {
  _SwitchRuntime({required this.initialEngine, required this.shouldFailOpen});

  final TestPlaybackEngine initialEngine;
  final bool Function(String sourceId) shouldFailOpen;
  final opened = <PlaybackPlan>[];
  var _initialReturned = false;

  @override
  String get backendId => 'fake';

  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    opened.add(plan);
    if (!_initialReturned) {
      _initialReturned = true;
      await initialEngine.load(plan);
      return PlaybackRuntimeSession(
        runtimeId: 'fake',
        plan: plan,
        engine: initialEngine,
        surface: _SourceSurface(plan.mediaSourceId),
      );
    }
    if (shouldFailOpen(plan.mediaSourceId)) {
      throw StateError('backend could not open negotiated source');
    }
    final engine = TestPlaybackEngine(id: 'fake-${plan.mediaSourceId}');
    await engine.load(plan);
    return PlaybackRuntimeSession(
      runtimeId: 'fake',
      plan: plan,
      engine: engine,
      surface: _SourceSurface(plan.mediaSourceId),
    );
  }
}

class _SourceSurface implements PlaybackVideoSurface {
  const _SourceSurface(this.source);
  final String source;

  @override
  Widget build(BuildContext context) => Text('surface-$source');
}

MediaSourceInfo _source(String id) => MediaSourceInfo.fromJson(
  <String, dynamic>{'Id': id, 'MediaStreams': <dynamic>[]},
);

PlaybackPlan _plan(String sourceId, String playSessionId) => PlaybackPlan(
  itemId: 'ITEM',
  mediaSourceId: sourceId,
  playSessionId: playSessionId,
  playMethod: PlayMethod.directPlay,
  playbackUri: Uri.parse('https://jellyfin.invalid/$sourceId'),
  engineId: 'fake',
  selectedAudioStreamIndex: 3,
  selectedSubtitleStreamIndex: 7,
  source: _source(sourceId),
);

PlaybackPlanDecision _decision(PlaybackPlan plan) {
  final backend = PlaybackBackendDescriptor(
    id: 'fake',
    displayName: 'Fake',
    availability: BackendAvailability.available,
    priority: 0,
    capabilities: const PlaybackBackendCapabilities(id: 'fake', name: 'Fake'),
  );
  final candidate = PlaybackBackendCandidate(
    backend: backend,
    plan: plan,
    score: const PlaybackPlanScore(total: 1, components: <String, int>{}),
  );
  return PlaybackPlanDecision(
    selected: candidate,
    candidates: <PlaybackBackendCandidate>[candidate],
  );
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}
