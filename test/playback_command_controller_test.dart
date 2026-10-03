import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_command_controller.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/playback_runtime_coordinator.dart';
import 'package:rodplayer/core/player/track_controller.dart';

import 'fakes/test_playback_engine.dart';

void main() {
  group('PlaybackCommandController', () {
    late _Runtime runtime;
    late PlaybackRuntimeCoordinator coordinator;
    late PlaybackCommandController controller;

    setUp(() {
      runtime = _Runtime();
      coordinator = PlaybackRuntimeCoordinator(
        registry: PlaybackRuntimeRegistry(
          runtimes: <PlaybackBackendRuntime>[runtime],
        ),
        session: LogicalPlaybackSession(
          id: 'logical-1',
          itemId: 'item-1',
          activePlan: _plan('initial'),
        ),
      );
      controller = PlaybackCommandController.forCoordinator(coordinator);
    });

    tearDown(() async => coordinator.dispose());

    Future<PlaybackCommandResult> dispatch(
      PlaybackCommand command,
      PlaybackCommandTargetId id,
    ) =>
        controller.dispatch(
          PlaybackCommandRequest(
            command: command,
            origin: PlaybackCommandOrigin.localUi,
            target: id,
          ),
        );

    test('routes play, pause, and toggle to the current runtime', () async {
      await coordinator.activate(_plan('A'));
      final target = controller.currentTarget()!;

      expect(
        (await dispatch(PlayCommand(), target.id)).status,
        PlaybackCommandStatus.executed,
      );
      expect(runtime.engines.last.playing.value, isTrue);
      expect(
        (await dispatch(PauseCommand(), target.id)).status,
        PlaybackCommandStatus.executed,
      );
      expect(runtime.engines.last.playing.value, isFalse);
      await dispatch(TogglePlayPauseCommand(), target.id);
      expect(runtime.engines.last.playing.value, isTrue);
    });

    test('one hundred sequential local toggles do not lose command ownership',
        () async {
      await coordinator.activate(_plan('A'));
      for (var index = 0; index < 100; index++) {
        final result = await controller.dispatchCurrent(
          command: const TogglePlayPauseCommand(),
          origin: PlaybackCommandOrigin.localUi,
        );
        expect(result.status, PlaybackCommandStatus.executed);
      }
      expect(runtime.engines.last.playing.value, isFalse);
      expect(controller.currentTarget()?.id.runtimeGeneration, 1);
    });

    test(
      'applies absolute and relative seeks through engine authority',
      () async {
        await coordinator.activate(_plan('A'));
        final engine = runtime.engines.last
          ..position = const Duration(seconds: 40);
        final id = controller.currentTarget()!.id;

        expect(
          (await dispatch(
            const SeekAbsoluteCommand(Duration(seconds: 90)),
            id,
          ))
              .status,
          PlaybackCommandStatus.executed,
        );
        expect(engine.position, const Duration(seconds: 90));
        expect(
          (await dispatch(
            const SeekRelativeCommand(Duration(seconds: -15)),
            id,
          ))
              .status,
          PlaybackCommandStatus.executed,
        );
        expect(engine.position, const Duration(seconds: 75));
        expect(
          (await dispatch(
            const SeekRelativeCommand(Duration(seconds: -100)),
            id,
          ))
              .status,
          PlaybackCommandStatus.executed,
        );
        expect(engine.position, Duration.zero);
        expect(
          (await dispatch(
            const SeekAbsoluteCommand(Duration(seconds: -1)),
            id,
          ))
              .status,
          PlaybackCommandStatus.invalidArgument,
        );
      },
    );

    test(
      'preserves existing 0–100 volume units and rejects invalid values',
      () async {
        await coordinator.activate(_plan('A'));
        final engine = runtime.engines.last;
        final id = controller.currentTarget()!.id;
        expect(
          (await dispatch(const SetVolumeCommand(42), id)).status,
          PlaybackCommandStatus.executed,
        );
        expect(engine.volume.value, 42);
        expect(
          (await dispatch(const SetVolumeCommand(101), id)).status,
          PlaybackCommandStatus.invalidArgument,
        );
      },
    );

    test(
      'does not infer playback-rate support from backend presence',
      () async {
        await coordinator.activate(_plan('A'));
        final id = controller.currentTarget()!.id;
        expect(
          (await dispatch(const SetPlaybackRateCommand(1.25), id)).status,
          PlaybackCommandStatus.unsupportedCapability,
        );
      },
    );

    test('returns no-active-session without touching an engine', () async {
      final result = await dispatch(
        const PlayCommand(),
        const PlaybackCommandTargetId(
          logicalSessionId: 'logical-1',
          runtimeGeneration: 0,
        ),
      );
      expect(result.status, PlaybackCommandStatus.ignoredNoActiveSession);
    });

    test(
      'rejects a captured target after runtime/source replacement',
      () async {
        await coordinator.activate(_plan('A'));
        final oldTarget = controller.currentTarget()!;
        await coordinator.activate(_plan('B'));

        final result = await dispatch(PlayCommand(), oldTarget.id);
        expect(result.status, PlaybackCommandStatus.staleSession);
        expect(runtime.engines.last.playing.value, isFalse);
      },
    );

    test('in-flight command reports stale when replacement commits first',
        () async {
      await coordinator.activate(_plan('A'));
      final old = runtime.engines.last;
      final gate = Completer<void>();
      old.playGate = gate;
      final pending =
          dispatch(const PlayCommand(), controller.currentTarget()!.id);
      await Future<void>.delayed(Duration.zero);
      await coordinator.activate(_plan('B'));
      final replacement = runtime.engines.last;
      gate.complete();
      expect((await pending).status, PlaybackCommandStatus.staleSession);
      expect(replacement.playing.value, isFalse);
    });

    test(
      'failed runtime activation preserves command ownership of active runtime',
      () async {
        await coordinator.activate(_plan('A'));
        final old = controller.currentTarget()!;
        runtime.failOpenFor = 'B';
        await expectLater(coordinator.activate(_plan('B')), throwsA(anything));
        expect(controller.currentTarget()?.id, old.id);
        expect(
          (await dispatch(const PlayCommand(), old.id)).status,
          PlaybackCommandStatus.executed,
        );
      },
    );

    test(
      'denies future remote origins centrally and preserves origin',
      () async {
        await coordinator.activate(_plan('A'));
        final id = controller.currentTarget()!.id;
        final result = await controller.dispatch(
          PlaybackCommandRequest(
            command: const PlayCommand(),
            origin: PlaybackCommandOrigin.companionRemote,
            target: id,
          ),
        );
        expect(result.status, PlaybackCommandStatus.unauthorizedOrigin);
        expect(result.origin, PlaybackCommandOrigin.companionRemote);
        expect(runtime.engines.last.playing.value, isFalse);
      },
    );

    test('remote authority can be explicitly composed outside player widgets',
        () async {
      await coordinator.activate(_plan('A'));
      final authorizedController = PlaybackCommandController.forCoordinator(
        coordinator,
        authority: AllowedPlaybackOriginsPolicy(
          allowedOrigins: const <PlaybackCommandOrigin>{
            PlaybackCommandOrigin.companionRemote,
          },
        ),
      );
      final result = await authorizedController.dispatchCurrent(
        command: const PlayCommand(),
        origin: PlaybackCommandOrigin.companionRemote,
      );
      expect(result.status, PlaybackCommandStatus.executed);
      expect(runtime.engines.last.playing.value, isTrue);
    });

    test('rejects unsupported track operations predictably', () async {
      await coordinator.activate(_plan('A'));
      final id = controller.currentTarget()!.id;
      final result = await dispatch(const SelectSubtitleCommand(null), id);
      expect(result.status, PlaybackCommandStatus.unsupportedCapability);
    });

    test('serializes track replacement commands for one runtime', () async {
      final tracks = _Tracks();
      runtime.tracks = tracks;
      await coordinator.activate(_plan('A'));
      final id = controller.currentTarget()!.id;
      final audio = dispatch(
        SelectAudioCommand(tracks.audioTracks.single),
        id,
      );
      await Future<void>.delayed(Duration.zero);
      final subtitles = List<Future<PlaybackCommandResult>>.generate(
        31,
        (_) => dispatch(const SelectSubtitleCommand(null), id),
      );
      await Future<void>.delayed(Duration.zero);

      expect(tracks.calls, <String>['audio']);
      expect(
        (await dispatch(const SelectSubtitleCommand(null), id)).status,
        PlaybackCommandStatus.commandQueueFull,
      );
      tracks.audioGate.complete();
      expect((await audio).status, PlaybackCommandStatus.executed);
      expect(
        (await Future.wait(subtitles)).every(
          (result) => result.status == PlaybackCommandStatus.executed,
        ),
        isTrue,
      );
      expect(tracks.calls, <String>['audio', ...List.filled(31, 'subtitle')]);
      expect(tracks.maximumConcurrent, 1);
    });

    test('track intent matches truthful metadata without storing engine IDs',
        () {
      const intent = PlaybackTrackIntent(
        language: 'en',
        kind: PlaybackTrackKind.subtitle,
        subtitle: TrackSubtitleIntent.sdh,
        commentary: false,
        isDefault: false,
      );
      final match = RodPlayerTrack(
        engineTrackId: 'runtime-specific-82',
        label: 'English SDH',
        language: 'EN',
        title: 'English SDH',
        isDefault: false,
        isForced: false,
      );
      expect(intent.matches(match), isTrue);
      expect(
          intent.matches(const RodPlayerTrack(
            engineTrackId: 'other-runtime-id',
            label: 'English forced',
            language: 'en',
            isDefault: false,
            isForced: true,
          )),
          isFalse);
      expect(intent.normalizedLanguage, 'en');
      expect(intent.subtitle, TrackSubtitleIntent.sdh);
      expect(intent.commentary, isFalse);
      expect(intent.isDefault, isFalse);
      expect(
          intent,
          const PlaybackTrackIntent(
            language: ' EN ',
            kind: PlaybackTrackKind.subtitle,
            subtitle: TrackSubtitleIntent.sdh,
            commentary: false,
            isDefault: false,
          ));
    });

    test('reports runtime failures as a safe typed result', () async {
      await coordinator.activate(_plan('A'));
      runtime.engines.last.failPlay = true;
      final result = await dispatch(
        PlayCommand(),
        controller.currentTarget()!.id,
      );
      expect(result.status, PlaybackCommandStatus.failedRuntimeOperation);
    });
  });
}

PlaybackPlan _plan(String sourceId) => PlaybackPlan(
      itemId: 'item-1',
      mediaSourceId: sourceId,
      playSessionId: 'play-$sourceId',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://media/$sourceId'),
      engineId: 'test',
      source: MediaSourceInfo.fromJson(<String, dynamic>{
        'Id': sourceId,
        'MediaStreams': <dynamic>[],
      }),
    );

final class _Runtime implements PlaybackBackendRuntime {
  final List<_Engine> engines = <_Engine>[];
  TrackSelectionController? tracks;
  String? failOpenFor;
  @override
  String get backendId => 'test';
  @override
  bool get isAvailable => true;

  @override
  Future<PlaybackRuntimeSession> open(PlaybackPlan plan) async {
    if (plan.mediaSourceId == failOpenFor) {
      throw StateError('runtime open failed');
    }
    final engine = _Engine();
    engines.add(engine);
    await engine.load(plan);
    return PlaybackRuntimeSession(
      runtimeId: 'test',
      plan: plan,
      engine: engine,
      tracks: tracks,
    );
  }
}

final class _Tracks implements TrackSelectionController {
  final Completer<void> audioGate = Completer<void>();
  final List<String> calls = <String>[];
  var _active = 0;
  var maximumConcurrent = 0;

  @override
  TrackSelectionCapabilities get capabilities =>
      const TrackSelectionCapabilities(
        audioSelection: CapabilitySupport.supported,
        subtitleSelection: CapabilitySupport.supported,
      );
  @override
  List<RodPlayerTrack> get audioTracks => const <RodPlayerTrack>[
        RodPlayerTrack(engineTrackId: 'audio-1', label: 'English'),
      ];
  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];
  @override
  RodPlayerTrack? get selectedAudio => null;
  @override
  RodPlayerTrack? get selectedSubtitle => null;

  Future<TrackSwitchResult> _run(String name, {Completer<void>? gate}) async {
    _active += 1;
    if (_active > maximumConcurrent) maximumConcurrent = _active;
    calls.add(name);
    try {
      await gate?.future;
      return const TrackSwitchResult(mode: TrackSwitchMode.local);
    } finally {
      _active -= 1;
    }
  }

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) =>
      _run('audio', gate: audioGate);

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) =>
      _run('subtitle');
}

final class _Engine extends TestPlaybackEngine {
  _Engine() : super(id: 'test');
  bool failPlay = false;
  Completer<void>? playGate;
  @override
  Future<void> play() async {
    if (failPlay) throw StateError('runtime unavailable');
    await playGate?.future;
    await super.play();
  }
}
