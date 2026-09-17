import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';

import 'fakes/test_playback_engine.dart';
import 'test_support.dart';

void main() {
  testWidgets('VideoPlayerView uses generic engine and fake surface for media key play pause', (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: _NoopClient());
    await engine.play();
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
        itemId: 'item',
      ),
    ));
    await tester.pump();
    expect(find.text('surface'), findsOneWidget);
    final playerContext = tester.element(find.byType(Scaffold));
    Focus.of(playerContext).requestFocus();
    await tester.pump();
    expect(Focus.of(playerContext).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(engine.playing.value, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(engine.playing.value, isFalse);
  });

  testWidgets('VideoPlayerView rebinds its surface and media controls with the active runtime', (tester) async {
    final first = TestPlaybackEngine();
    final second = TestPlaybackEngine();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(PlaybackRuntimeViewBinding(engine: first, surface: const _NamedSurface('first')));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: _NoopClient());

    await tester.pumpWidget(MaterialApp(home: VideoPlayerView(activeBinding: binding, client: client, itemId: 'item')));
    expect(find.text('first'), findsOneWidget);
    binding.value = PlaybackRuntimeViewBinding(engine: second, surface: const _NamedSurface('second'));
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    final playerContext = tester.element(find.byType(Scaffold));
    Focus.of(playerContext).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(first.playing.value, isFalse);
    expect(second.playing.value, isTrue);
  });

  testWidgets('Stats for Nerds follows the active runtime binding', (tester) async {
    final first = TestPlaybackEngine();
    final second = TestPlaybackEngine();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final firstPlan = _plan(backend: 'backend-a', source: 'source-a', container: 'mkv', codec: 'hevc');
    final secondPlan = _plan(backend: 'backend-b', source: 'source-b', container: 'mp4', codec: 'h264');
    final session = _session(plan: firstPlan);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(
        engine: first,
        surface: const _NamedSurface('first'),
        plan: firstPlan,
        runtimeId: 'runtime-a',
      ),
    );
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      client: _NoopClient(),
    );

    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        activeBinding: binding,
        client: client,
        itemId: 'item',
        logicalSession: session,
      ),
    ));
    expect(find.byTooltip('Stats for Nerds'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Stats for Nerds'), findsOneWidget);
    await tester.tap(find.byTooltip('Stats for Nerds'));
    await tester.pumpAndSettle();
    expect(find.text('backend-a'), findsOneWidget);
    expect(find.text('runtime-a'), findsOneWidget);
    expect(find.text('mkv'), findsOneWidget);
    expect(find.text('hevc'), findsOneWidget);

    binding.value = PlaybackRuntimeViewBinding(
      engine: second,
      surface: const _NamedSurface('second'),
      plan: secondPlan,
      runtimeId: 'runtime-b',
    );
    await tester.pump();
    expect(find.text('backend-b'), findsOneWidget);
    expect(find.text('runtime-b'), findsOneWidget);
    expect(find.text('mp4'), findsOneWidget);
    expect(find.text('h264'), findsOneWidget);
    expect(find.text('backend-a'), findsNothing);
    expect(find.text('runtime-a'), findsNothing);
    expect(find.text('mkv'), findsNothing);
    expect(find.text('hevc'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    binding.value = const PlaybackRuntimeViewBinding.unavailable();
    await tester.pump();
    expect(find.text('Playback diagnostics unavailable'), findsOneWidget);
    expect(find.text('backend-b'), findsNothing);
  });

  testWidgets('skip marker visibility uses exact start inclusive end exclusive boundaries', (tester) async {
    final engine = _RecordingEngine();
    addTearDown(engine.dispose);
    final session = _session(markers: const <PlaybackMarker>[_introMarker]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(engine: engine, surface: const _FakeSurface()),
    );
    addTearDown(binding.dispose);

    engine.position = const Duration(milliseconds: 999);
    await _pumpSkipPlayer(tester, binding, session);
    expect(find.text('Skip Intro'), findsNothing);

    engine.position = const Duration(seconds: 1);
    await tester.pump();
    expect(find.text('Skip Intro'), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Skip Intro'), findsOneWidget);

    engine.position = const Duration(seconds: 2);
    await tester.pump();
    expect(find.text('Skip Intro'), findsOneWidget);

    engine.position = const Duration(seconds: 3);
    await tester.pump();
    expect(find.text('Skip Intro'), findsNothing);

    session.updateMetadata(
      PlaybackMetadata(
        markers: const <PlaybackMarker>[
          PlaybackMarker(
            kind: 'Recap',
            start: Duration(seconds: 1),
            end: Duration(seconds: 3),
          ),
        ],
      ),
    );
    engine.position = const Duration(seconds: 2);
    await tester.pump();
    expect(find.text('Skip Intro'), findsNothing);
    expect(find.text('Skip Outro'), findsNothing);
  });

  testWidgets('skip marker seeks exactly to marker end and updates logical position after success', (tester) async {
    final engine = _RecordingEngine();
    addTearDown(engine.dispose);
    final session = _session(markers: const <PlaybackMarker>[_introMarker])
      ..position = const Duration(milliseconds: 250);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(engine: engine, surface: const _FakeSurface()),
    );
    addTearDown(binding.dispose);
    engine.position = const Duration(seconds: 2);

    await _pumpSkipPlayer(tester, binding, session);
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();

    expect(engine.seekCalls, <Duration>[const Duration(seconds: 3)]);
    expect(session.position, const Duration(seconds: 3));
  });

  testWidgets('failed skip does not fake logical position and shows feedback', (tester) async {
    final engine = _RecordingEngine();
    addTearDown(engine.dispose);
    engine.seekHandler = (_) async => throw StateError('seek failed');
    final session = _session(markers: const <PlaybackMarker>[_introMarker])
      ..position = const Duration(milliseconds: 250);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(engine: engine, surface: const _FakeSurface()),
    );
    addTearDown(binding.dispose);
    engine.position = const Duration(seconds: 2);

    await _pumpSkipPlayer(tester, binding, session);
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();

    expect(engine.seekCalls, <Duration>[const Duration(seconds: 3)]);
    expect(session.position, const Duration(milliseconds: 250));
    expect(find.text('Unable to skip this segment'), findsOneWidget);
    expect(find.text('Skip Intro'), findsOneWidget);
  });

  testWidgets('skip marker ignores duplicate activation while seek is pending', (tester) async {
    final gate = Completer<void>();
    final engine = _RecordingEngine();
    addTearDown(engine.dispose);
    engine.seekHandler = (_) => gate.future;
    final session = _session(markers: const <PlaybackMarker>[_introMarker])
      ..position = const Duration(milliseconds: 250);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(engine: engine, surface: const _FakeSurface()),
   );
    addTearDown(binding.dispose);
    engine.position = const Duration(seconds: 2);

    await _pumpSkipPlayer(tester, binding, session);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();

    expect(engine.seekCalls, <Duration>[const Duration(seconds: 3)]);
    expect(session.position, const Duration(milliseconds: 250));

    gate.complete();
    await tester.pump();

    expect(session.position, const Duration(seconds: 3));
  });

  testWidgets('skip marker reacts when server metadata arrives asynchronously', (tester) async {
    final engine = _RecordingEngine();
    addTearDown(engine.dispose);
    final session = _session();
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(engine: engine, surface: const _FakeSurface()),
   );
    addTearDown(binding.dispose);
    engine.position = const Duration(seconds: 2);

    await _pumpSkipPlayer(tester, binding, session);
    expect(find.text('Skip Intro'), findsNothing);

    session.updateMetadata(
      PlaybackMetadata(markers: const <PlaybackMarker>[_introMarker]),
    );
    await tester.pump();

    expect(find.text('Skip Intro'), findsOneWidget);
  });

  testWidgets('skip marker follows active runtime replacement and never seeks stale engine', (tester) async {
    final first = _RecordingEngine(id: 'first');
    final second = _RecordingEngine(id: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.position = const Duration(seconds: 2);
    second.position = const Duration(seconds: 2);
    final session = _session(markers: const <PlaybackMarker>[_introMarker]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(engine: first, surface: const _NamedSurface('first')),
   );
    addTearDown(binding.dispose);

    await _pumpSkipPlayer(tester, binding, session);
    expect(find.text('first'), findsOneWidget);

    binding.value = PlaybackRuntimeViewBinding(
      engine: second,
      surface: const _NamedSurface('second'),
    );
    await tester.pump();
    expect(find.text('second'), findsOneWidget);

    await tester.tap(find.text('Skip Intro'));
    await tester.pump();

    expect(first.seekCalls, isEmpty);
    expect(second.seekCalls, <Duration>[const Duration(seconds: 3)]);
    expect(session.position, const Duration(seconds: 3));
  });
}


const _introMarker = PlaybackMarker(
  kind: 'Intro',
  start: Duration(seconds: 1),
  end: Duration(seconds: 3),
);

LogicalPlaybackSession _session({
  Iterable<PlaybackMarker> markers = const <PlaybackMarker>[],
  PlaybackPlan? plan,
}) {
  final activePlan = plan ?? _plan();
  return LogicalPlaybackSession(
    id: 'logical',
    itemId: 'item',
    activePlan: activePlan,
    metadata: PlaybackMetadata(markers: markers),
  );
}

PlaybackPlan _plan({
  String backend = 'test',
  String source = 'source',
  String? container,
  String? codec,
}) => PlaybackPlan(
    itemId: 'item',
    mediaSourceId: source,
    playSessionId: 'play-session',
    playMethod: PlayMethod.directPlay,
    playbackUri: Uri.parse('https://media.example.com/Videos/item/stream'),
    engineId: backend,
    source: MediaSourceInfo.fromJson(<String, dynamic>{
      'Id': source,
      if (container != null) 'Container': container,
      'MediaStreams': <dynamic>[
        if (codec != null) <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': codec},
      ],
    }),
  );

Future<void> _pumpSkipPlayer(
  WidgetTester tester,
  ValueNotifier<PlaybackRuntimeViewBinding> binding,
  LogicalPlaybackSession session,
) async {
  final client = JellyfinApiClient(
    baseUrl: 'https://media.example.com',
    identity: testIdentity,
    client: _NoopClient(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: VideoPlayerView(
        activeBinding: binding,
        client: client,
        itemId: 'item',
        logicalSession: session,
      ),
    ),
  );
  await tester.pump();
}

class _RecordingEngine extends TestPlaybackEngine {
  _RecordingEngine({super.id});

  final List<Duration> seekCalls = <Duration>[];
  Future<void> Function(Duration)? seekHandler;

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    final handler = seekHandler;
    if (handler != null) {
      await handler(position);
      return;
    }
    await super.seek(position);
  }
}

class _FakeSurface implements PlaybackVideoSurface {
  const _FakeSurface();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black, child: Text('surface'));
}

class _NamedSurface implements PlaybackVideoSurface {
  const _NamedSurface(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Text(name);
}

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(Stream<List<int>>.empty(), 204);
}
