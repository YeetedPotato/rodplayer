import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/playback/playback_environment.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
import 'package:rodplayer/core/player/playback_runtime.dart';
import 'package:rodplayer/core/player/track_controller.dart';
import 'package:rodplayer/ui/player/video_player_view.dart';
import 'package:rodplayer/core/player_ui_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/test_playback_engine.dart';
import 'test_support.dart';

void main() {
  testWidgets('player waits for final progress report before route exit',
      (tester) async {
    final requests = <http.Request>[];
    final stopGate = Completer<http.Response>();
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/Sessions/Playing/Stopped') {
          return stopGate.future;
        }
        return http.Response('', 204);
      }),
    );
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final session = _session();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => VideoPlayerView(
                  engine: engine,
                  surface: const _FakeSurface(),
                  client: client,
                  logicalSession: session,
                ),
              ),
            ),
            child: const Text('Open player'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();
    engine.position = const Duration(seconds: 300);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Open player'), findsNothing,
        reason: 'the player route remains mounted until Stopped completes');
    expect(find.byTooltip('Back'), findsOneWidget);
    stopGate.complete(http.Response('', 204));
    await tester.pumpAndSettle();

    expect(find.text('Open player'), findsOneWidget);
    expect(session.position, const Duration(seconds: 300));
    expect(requests.map((request) => request.url.path), <String>[
      '/Sessions/Playing',
      '/Sessions/Playing/Stopped',
    ]);
    final stopped = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(stopped['ItemId'], 'item');
    expect(stopped['PlaySessionId'], 'play-session');
    expect(stopped['MediaSourceId'], 'source');
    expect(stopped['PositionTicks'], 3000000000);
  });

  testWidgets(
      'VideoPlayerView uses generic engine and fake surface for media key play pause',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
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
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason:
            'unknown duration must not look like an indeterminate loading state');
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

  testWidgets(
      'player OSD auto-hides and video click pauses while revealing controls',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    await engine.play();
    engine.duration = const Duration(minutes: 90);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            engine: engine, surface: const _FakeSurface(), client: client)));
    expect(find.byTooltip('Pause'), findsOneWidget);
    final pauseIcon = tester.widget<Icon>(find.byWidgetPredicate(
        (widget) => widget is Icon && widget.icon == Icons.pause));
    expect(pauseIcon.size, 28);
    final timelineSlider = find.byType(Slider).first;
    final timelineTheme = tester.widget<SliderTheme>(find
        .ancestor(of: timelineSlider, matching: find.byType(SliderTheme))
        .first);
    expect(timelineTheme.data.trackHeight, 4.5);
    expect(
      (timelineTheme.data.thumbShape as RoundSliderThumbShape)
          .enabledThumbRadius,
      6,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_osdOpacity(tester), 1);
    expect(engine.playing.value, isFalse);
    await engine.pause();
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
  });

  testWidgets('video clicks toggle the current runtime; OSD clicks stay local',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = _InputCountingEngine(id: 'first');
    final replacement = _InputCountingEngine(id: 'replacement');
    addTearDown(first.dispose);
    addTearDown(replacement.dispose);
    await first.play();
    first.resetCounts();
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(
        engine: first,
        surface: const _NamedSurface('surface-a'),
        tracks: _TwoTrackController(),
      ),
    );
    addTearDown(binding.dispose);
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        activeBinding: binding,
        client: JellyfinApiClient(
            baseUrl: 'https://media.example.com',
            identity: testIdentity,
            serverId: testServerId,
            client: _NoopClient()),
        logicalSession: _session()..position = const Duration(seconds: 545),
        fullscreenWindow: _FakeFullscreenWindow(),
      ),
    ));

    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(first.pauseCalls, 1, reason: 'playing surface click pauses once');
    expect(first.playCalls, 0);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(first.playCalls, 1, reason: 'paused surface click plays once');

    // Interactive OSD targets own the gesture and do not trigger the surface.
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(first.pauseCalls, 2);
    expect(first.playCalls, 1);
    final countsBeforeTimeline = (first.playCalls, first.pauseCalls);
    await tester.tap(find.byType(Slider).first);
    await tester.pump();
    expect((first.playCalls, first.pauseCalls), countsBeforeTimeline,
        reason: 'timeline input must not bubble into surface Play/Pause');
    binding.value = PlaybackRuntimeViewBinding(
      engine: replacement,
      surface: const _NamedSurface('surface-b'),
      tracks: _TwoTrackController(),
    );
    await tester.pump();
    expect(find.text('surface-b'), findsOneWidget);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(replacement.playCalls, 1,
        reason: 'surface clicks follow the committed replacement runtime');
    expect(first.playCalls, 1);

    final window = tester
        .widget<VideoPlayerView>(find.byType(VideoPlayerView))
        .fullscreenWindow! as _FakeFullscreenWindow;
    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    expect(window.fullscreen, isTrue);
    await tester.tap(find.byTooltip('Exit fullscreen'));
    await tester.pump();
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 350));
    expect(replacement.pauseCalls, 1,
        reason: 'surface playback input still works after fullscreen exit');
  });

  testWidgets('double-click toggles fullscreen without toggling playback',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final engine = TestPlaybackEngine();
      addTearDown(engine.dispose);
      var fullscreenChanges = 0;
      final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient(),
      );
      await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
          engine: engine,
          surface: const _FakeSurface(),
          client: client,
          onToggleFullscreen: () async => fullscreenChanges++,
        ),
      ));

      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 300));
      expect(fullscreenChanges, 1);
      expect(engine.playing.value, isFalse,
          reason:
              'double-click must not also dispatch the single-click action');
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fullscreenChanges, 2,
          reason: 'Escape exits fullscreen before popping the player route');
      expect(find.byTooltip('Fullscreen'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'fullscreen button, double-click and Escape use live window state',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final window = _FakeFullscreenWindow();
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: JellyfinApiClient(
            baseUrl: 'https://media.example.com',
            identity: testIdentity,
            serverId: testServerId,
            client: _NoopClient()),
        fullscreenWindow: window,
      ),
    ));

    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    expect(window.fullscreen, isTrue);
    expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
    await tester.tap(find.byTooltip('Exit fullscreen'));
    await tester.pump();
    expect(window.fullscreen, isFalse);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);

    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(window.fullscreen, isTrue);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(200, 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(window.fullscreen, isFalse);

    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    expect(window.fullscreen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(window.fullscreen, isFalse);
    expect(find.byTooltip('Fullscreen'), findsOneWidget);
  });

  testWidgets('fullscreen preserves a maximized window presentation state',
      (tester) async {
    final window = _FakeFullscreenWindow()..maximized = true;
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: JellyfinApiClient(
            baseUrl: 'https://media.example.com',
            identity: testIdentity,
            serverId: testServerId,
            client: _NoopClient()),
        fullscreenWindow: window,
      ),
    ));
    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    expect(window.fullscreen, isTrue);
    expect(window.maximized, isTrue);
    await tester.tap(find.byTooltip('Exit fullscreen'));
    await tester.pump();
    expect(window.fullscreen, isFalse);
    expect(window.maximized, isTrue);
  });

  testWidgets('pointer leaving the player hides controls immediately',
      (tester) async {
    final engine = TestPlaybackEngine();
    await engine.play();
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 200));
    await mouse.moveTo(const Offset(300, 200));
    await tester.pump();
    expect(_osdOpacity(tester), 1);

    await mouse.moveTo(const Offset(900, 700));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
    await mouse.removePointer();
  });

  testWidgets('focused player arrows seek ten seconds and wheel changes volume',
      (tester) async {
    final engine = TestPlaybackEngine();
    engine.position = const Duration(seconds: 30);
    engine.duration = const Duration(minutes: 2);
    engine.volume.value = 50;
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
      ),
    ));
    final playerContext = tester.element(find.byType(Scaffold));
    Focus.of(playerContext).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.position, const Duration(seconds: 40));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(engine.position, const Duration(seconds: 30));

    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(300, 200),
      scrollDelta: const Offset(0, -1),
    ));
    await tester.pump();
    expect(engine.volume.value, 55);
    expect(find.textContaining('Ends '), findsOneWidget);

    await engine.play();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.position, const Duration(seconds: 40),
        reason: 'a hidden OSD does not consume the first global seek key');
    expect(_osdOpacity(tester), 1);
  });

  testWidgets('saved player preferences change seek and wheel behavior',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PlayerUiSettings.seekKey: 15,
      PlayerUiSettings.clickKey: false,
      PlayerUiSettings.wheelKey: false,
    });
    addTearDown(
        () => SharedPreferences.setMockInitialValues(<String, Object>{}));
    final engine = TestPlaybackEngine();
    engine.position = const Duration(seconds: 30);
    engine.duration = const Duration(minutes: 2);
    engine.volume.value = 50;
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
      ),
    ));
    await tester.pumpAndSettle();
    final playerContext = tester.element(find.byType(Scaffold));
    Focus.of(playerContext).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(engine.position, const Duration(seconds: 45));
    await tester.sendEventToBinding(PointerScrollEvent(
      position: const Offset(300, 200),
      scrollDelta: const Offset(0, -1),
    ));
    await tester.pump();
    expect(engine.volume.value, 50);

    await tester.tapAt(const Offset(300, 200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(engine.playing.value, isTrue,
        reason: 'video surface clicks always follow the player command path');
  });

  testWidgets(
      'buffering keeps OSD visible and hidden controls wake on directional input',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    await engine.play();
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            engine: engine, surface: const _FakeSurface(), client: client)));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, 'player-root');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(_osdOpacity(tester), 1);
    expect(tester.binding.focusManager.primaryFocus?.debugLabel, 'player-play');
    engine.buffering.value = true;
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
  });

  testWidgets(
      'player timeline seeks to real duration and volume control uses the engine',
      (tester) async {
    final engine = TestPlaybackEngine();
    engine.position = const Duration(seconds: 20);
    engine.duration = const Duration(seconds: 120);
    engine.volume.value = 57;
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            engine: engine, surface: const _FakeSurface(), client: client)));

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(2));
    expect(sliders.first.max, 120000);
    await tester.drag(find.byType(Slider).first, const Offset(140, 0));
    await tester.pump();
    expect(engine.position, greaterThan(const Duration(seconds: 20)));

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(engine.volume.value, 0);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(engine.volume.value, 57);

    final playerContext = tester.element(find.byType(Scaffold));
    Focus.of(playerContext).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volume.value, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(engine.volume.value, 57);
  });

  testWidgets(
      'visible player controls expose Back and return to the prior route',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                        builder: (_) => VideoPlayerView(
                            engine: engine,
                            surface: const _FakeSurface(),
                            client: client))),
                child: const Text('Open player'),
              ))),
    ));
    await tester.tap(find.text('Open player'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open player'), findsOneWidget);
  });

  testWidgets('new engine state replaces old OSD timer state', (tester) async {
    final paused = TestPlaybackEngine();
    final playing = TestPlaybackEngine();
    addTearDown(paused.dispose);
    addTearDown(playing.dispose);
    await playing.play();
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: paused, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(activeBinding: binding, client: client)));
    binding.value = PlaybackRuntimeViewBinding(
        engine: playing, surface: const _FakeSurface());
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
  });

  testWidgets('paused and buffering replacement engines keep OSD visible',
      (tester) async {
    final playing = TestPlaybackEngine();
    final paused = TestPlaybackEngine();
    final buffering = TestPlaybackEngine();
    addTearDown(playing.dispose);
    addTearDown(paused.dispose);
    addTearDown(buffering.dispose);
    await playing.play();
    buffering.buffering.value = true;
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: playing, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(activeBinding: binding, client: client)));
    binding.value = PlaybackRuntimeViewBinding(
        engine: paused, surface: const _FakeSurface());
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
    binding.value = PlaybackRuntimeViewBinding(
        engine: buffering, surface: const _FakeSurface());
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
  });

  testWidgets(
      'player keyboard transport uses the current engine and clamps seeks',
      (tester) async {
    final first = _RecordingEngine(id: 'first')
      ..position = const Duration(seconds: 5);
    final second = _RecordingEngine(id: 'second')
      ..position = const Duration(seconds: 95);
    final third = _RecordingEngine(id: 'third')
      ..position = const Duration(seconds: 95);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(third.dispose);
    second.duration = const Duration(seconds: 100);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: first, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    final session = _session();
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            activeBinding: binding, client: client, logicalSession: session)));
    final player = tester.element(find.byType(Scaffold));
    Focus.of(player).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pump();
    expect(first.seekCalls, <Duration>[Duration.zero]);
    binding.value = PlaybackRuntimeViewBinding(
        engine: second, surface: const _FakeSurface());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(first.seekCalls, <Duration>[Duration.zero]);
    expect(second.seekCalls, <Duration>[const Duration(seconds: 100)]);
    expect(session.position, const Duration(seconds: 100));
    binding.value = PlaybackRuntimeViewBinding(
        engine: third, surface: const _FakeSurface());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(third.seekCalls, <Duration>[const Duration(seconds: 105)]);
    expect(session.position, const Duration(seconds: 105));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(third.playing.value, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(third.playing.value, isTrue);
  });

  testWidgets(
      'OSD activity replaces an expiring timer and pointer hover restores hidden controls',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    await engine.play();
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            engine: engine, surface: const _FakeSurface(), client: client)));
    await tester.pump(const Duration(milliseconds: 2900));
    await tester.sendEventToBinding(
        const PointerHoverEvent(position: Offset(200, 200)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_osdOpacity(tester), 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
    await tester.sendEventToBinding(
        const PointerHoverEvent(position: Offset(200, 200)));
    await tester.pump();
    expect(_osdOpacity(tester), 1);
  });

  testWidgets('OSD stays visible over skip, volume, and settings controls',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    await engine.play();
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 200));
    await mouse.moveTo(const Offset(200, 200));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 2800));
    await mouse.moveTo(tester.getCenter(find.byTooltip('Rewind 10 seconds')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_osdOpacity(tester), 1,
        reason: 'hovering skip-back must cancel the original deadline');

    await mouse.moveTo(tester.getCenter(find.byTooltip('Forward 10 seconds')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1,
        reason: 'hovering skip-forward must keep the OSD visible');

    await mouse.moveTo(tester.getCenter(find.byTooltip('Mute')));
    await tester.pump();
    final volumeSlider = find.byType(Slider).last;
    await mouse.moveTo(tester.getCenter(volumeSlider));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1,
        reason: 'hovering volume must keep the OSD visible');

    await mouse.moveTo(tester.getCenter(find.byTooltip('Playback settings')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1,
        reason: 'hovering settings must keep the OSD visible');
    await mouse.moveTo(const Offset(900, 700));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(_osdOpacity(tester), 0);
    await mouse.removePointer();
  });

  testWidgets('player exposes one playback position semantic timeline',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    engine.duration = const Duration(minutes: 2);
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
      ),
    ));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.slider == true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('track sheet keeps the OSD active while open', (tester) async {
    final engine = _InputCountingEngine(id: 'track-sheet');
    addTearDown(engine.dispose);
    await engine.play();
    engine.resetCounts();
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(
        engine: engine,
        surface: const _FakeSurface(),
        tracks: _TwoTrackController(),
      ),
    );
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(activeBinding: binding, client: client),
    ));
    await tester.tap(find.byTooltip('Audio and subtitles'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
    expect(find.text('English'), findsWidgets);
    expect((engine.playCalls, engine.pauseCalls), (0, 0),
        reason: 'opening the track popup does not activate the video gesture');
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((engine.playCalls, engine.pauseCalls), (0, 0));
  });

  testWidgets('settings sheet keeps the OSD active while open', (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    await engine.play();
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _NoopClient(),
    );
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
      ),
    ));
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
    expect(find.text('Seek interval'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('player More actions publish favorite and watched changes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final client = _PlayerUserDataClient();
    final changes = <JellyfinUserDataChange>[];
    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        engine: engine,
        surface: const _FakeSurface(),
        client: client,
        itemId: 'movie',
        onUserDataChanged: changes.add,
      ),
    ));

    await tester.tap(find.byTooltip('More player actions'));
    await tester.pumpAndSettle();
    expect(find.text('Add to favorites'), findsOneWidget);
    expect(find.text('Mark watched'), findsOneWidget);
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();
    expect(client.favoriteCalls, <bool>[true]);
    expect(changes.single.isFavorite, isTrue);

    await tester.tap(find.byTooltip('More player actions'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from favorites'), findsOneWidget);
    await tester.tap(find.text('Mark watched'));
    await tester.pumpAndSettle();
    expect(client.playedCalls, <bool>[true]);
    expect(changes.last.played, isTrue);
    expect(changes.last.playbackProgressMayHaveChanged, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'VideoPlayerView rebinds its surface and media controls with the active runtime',
      (tester) async {
    final first = TestPlaybackEngine();
    final second = TestPlaybackEngine();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: first, surface: const _NamedSurface('first')));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());

    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            activeBinding: binding, client: client, itemId: 'item')));
    expect(find.text('first'), findsOneWidget);
    binding.value = PlaybackRuntimeViewBinding(
        engine: second, surface: const _NamedSurface('second'));
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    final playerContext = tester.element(find.byType(Scaffold));
    Focus.of(playerContext).requestFocus();
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();
    expect(first.playing.value, isFalse);
    expect(second.playing.value, isTrue);
  });

  testWidgets(
      'VideoPlayerView replaces a surface without rebinding the same engine',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _NamedSurface('first')));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(activeBinding: binding, client: client)));
    expect(find.text('first'), findsOneWidget);
    binding.value = PlaybackRuntimeViewBinding(
        engine: engine, surface: const _NamedSurface('second'));
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
  });

  testWidgets('Playback info follows the active runtime binding',
      (tester) async {
    final first = TestPlaybackEngine();
    final second = TestPlaybackEngine();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final firstPlan = _plan(
        backend: 'backend-a',
        source: 'source-a',
        container: 'mkv',
        codec: 'hevc');
    final secondPlan = _plan(
        backend: 'backend-b',
        source: 'source-b',
        container: 'mp4',
        codec: 'h264');
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
      serverId: testServerId,
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
    expect(find.byTooltip('Playback info'), findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == 'Playback info'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Playback info'));
    await tester.pump(const Duration(milliseconds: 400));
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

  testWidgets(
      'skip marker visibility uses exact start inclusive end exclusive boundaries',
      (tester) async {
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
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == 'Skip Intro'),
        findsOneWidget);

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

  testWidgets(
      'skip marker seeks exactly to marker end and updates logical position after success',
      (tester) async {
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

  testWidgets(
      'pending skip completes after OSD hides and its button is removed',
      (tester) async {
    final gate = Completer<void>();
    final engine = _RecordingEngine()..position = const Duration(seconds: 2);
    await engine.play();
    engine.seekHandler = (_) => gate.future;
    addTearDown(engine.dispose);
    final session = _session(markers: const <PlaybackMarker>[_introMarker])
      ..position = const Duration(seconds: 1);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    await _pumpSkipPlayer(tester, binding, session);
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();
    expect(engine.seekCalls, <Duration>[const Duration(seconds: 3)]);

    await tester.pump(const Duration(seconds: 3));
    expect(_osdOpacity(tester), 0);
    expect(find.text('Skip Intro'), findsNothing);
    gate.complete();
    await tester.pump();
    expect(session.position, const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline drag suspends auto-hide until interaction ends',
      (tester) async {
    final engine = _RecordingEngine()..duration = const Duration(minutes: 2);
    await engine.play();
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            engine: engine, surface: const _FakeSurface(), client: client)));
    await tester.pump(const Duration(milliseconds: 2900));
    final drag =
        await tester.startGesture(tester.getCenter(find.byType(Slider).first));
    await drag.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(seconds: 4));
    expect(_osdOpacity(tester), 1);
    await drag.up();
    await tester.pump();
    expect(engine.seekCalls, isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
    expect(_osdOpacity(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'seek and mute failures show scoped feedback without uncaught errors',
      (tester) async {
    final engine = _FailingActionEngine()..volume.value = 57;
    addTearDown(engine.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            engine: engine, surface: const _FakeSurface(), client: client)));
    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pump();
    expect(find.text('Unable to seek'), findsOneWidget);
    expect(engine.position, Duration.zero);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
        .removeCurrentSnackBar();
    await tester.pump();
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(find.text('Unable to change volume'), findsOneWidget);
    expect(engine.volume.value, 57);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'compact scaled player keeps skip, timeline, and controls separate',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = _RecordingEngine()
      ..position = const Duration(seconds: 2)
      ..duration = const Duration(minutes: 2);
    addTearDown(engine.dispose);
    final session = _session(markers: const <PlaybackMarker>[_introMarker]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 760))
            .copyWith(textScaler: TextScaler.linear(1.25)),
        child: VideoPlayerView(
            activeBinding: binding, logicalSession: session, client: client),
      ),
    ));
    await tester.pump();
    expect(find.text('Skip Intro'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(tester.getRect(find.byType(Slider).first).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Skip Intro')).top));
    expect(tester.getRect(find.text('Skip Intro')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Play')).top));
    expect(find.byTooltip('More player actions'), findsOneWidget);
    expect(find.byTooltip('Playback settings'), findsNothing);
    await tester.tap(find.byTooltip('More player actions'));
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed skip does not fake logical position and shows feedback',
      (tester) async {
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

  testWidgets('skip marker ignores duplicate activation while seek is pending',
      (tester) async {
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

  testWidgets('skip marker reacts when server metadata arrives asynchronously',
      (tester) async {
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

  testWidgets(
      'skip marker follows active runtime replacement and never seeks stale engine',
      (tester) async {
    final first = _RecordingEngine(id: 'first');
    final second = _RecordingEngine(id: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.position = const Duration(seconds: 2);
    second.position = const Duration(seconds: 2);
    final session = _session(markers: const <PlaybackMarker>[_introMarker]);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
      PlaybackRuntimeViewBinding(
          engine: first, surface: const _NamedSurface('first')),
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

  testWidgets('stale skip completion cannot update the logical position',
      (tester) async {
    final gate = Completer<void>();
    final first = _RecordingEngine(id: 'first')
      ..position = const Duration(seconds: 2);
    final second = _RecordingEngine(id: 'second')
      ..position = const Duration(seconds: 2);
    first.seekHandler = (_) => gate.future;
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final session = _session(markers: const <PlaybackMarker>[_introMarker])
      ..position = const Duration(seconds: 1);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: first, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    await _pumpSkipPlayer(tester, binding, session);
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();
    binding.value = PlaybackRuntimeViewBinding(
        engine: second, surface: const _FakeSurface());
    gate.complete();
    await tester.pump();
    expect(session.position, const Duration(seconds: 1));
  });

  testWidgets('same-engine binding replacement invalidates a pending skip',
      (tester) async {
    final gate = Completer<void>();
    final engine = _RecordingEngine()..position = const Duration(seconds: 2);
    engine.seekHandler = (_) => gate.future;
    addTearDown(engine.dispose);
    final session = _session(markers: const <PlaybackMarker>[_introMarker])
      ..position = const Duration(seconds: 1);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _NamedSurface('first')));
    addTearDown(binding.dispose);
    await _pumpSkipPlayer(tester, binding, session);
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();
    binding.value = PlaybackRuntimeViewBinding(
        engine: engine, surface: const _NamedSurface('second'));
    gate.complete();
    await tester.pump();
    expect(session.position, const Duration(seconds: 1));
  });

  testWidgets('same-engine binding replacement suppresses a stale skip failure',
      (tester) async {
    final gate = Completer<void>();
    final engine = _RecordingEngine()..position = const Duration(seconds: 2);
    engine.seekHandler = (_) async {
      await gate.future;
      throw StateError('stale');
    };
    addTearDown(engine.dispose);
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _NamedSurface('first')));
    addTearDown(binding.dispose);
    await _pumpSkipPlayer(tester, binding,
        _session(markers: const <PlaybackMarker>[_introMarker]));
    await tester.tap(find.text('Skip Intro'));
    await tester.pump();
    binding.value = PlaybackRuntimeViewBinding(
        engine: engine, surface: const _NamedSurface('second'));
    gate.complete();
    await tester.pump();
    expect(find.text('Unable to skip this segment'), findsNothing);
  });

  testWidgets(
      'same-engine binding replacement suppresses a pending playback error',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    var recoveries = 0;
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _NamedSurface('first')));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            activeBinding: binding,
            client: client,
            onPlaybackError: () async {
              recoveries++;
            })));
    engine.error.value = 'old failure';
    binding.value = PlaybackRuntimeViewBinding(
        engine: engine, surface: const _NamedSurface('second'));
    await tester.pump();
    expect(find.text('Playback error: old failure'), findsNothing);
    expect(recoveries, 0);
  });

  testWidgets(
      'error retry only recovers while its binding and error remain current',
      (tester) async {
    final engine = TestPlaybackEngine();
    addTearDown(engine.dispose);
    var recoveries = 0;
    final binding = ValueNotifier<PlaybackRuntimeViewBinding>(
        PlaybackRuntimeViewBinding(
            engine: engine, surface: const _FakeSurface()));
    addTearDown(binding.dispose);
    final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _NoopClient());
    await tester.pumpWidget(MaterialApp(
        home: VideoPlayerView(
            activeBinding: binding,
            client: client,
            onPlaybackError: () async {
              recoveries++;
            })));
    engine.error.value = 'failure';
    await tester.pump();
    await tester.pump();
    expect(find.text('RETRY'), findsOneWidget);
    expect(recoveries, 1);
    final staleRetry =
        tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    engine.error.value = null;
    staleRetry();
    await tester.pump();
    expect(recoveries, 1);
    engine.error.value = 'current failure';
    await tester.pump();
    await tester.pump();
    final currentRetry =
        tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    currentRetry();
    await tester.pump();
    expect(recoveries, 3);
  });
}

const _introMarker = PlaybackMarker(
  kind: 'Intro',
  start: Duration(seconds: 1),
  end: Duration(seconds: 3),
);

double _osdOpacity(WidgetTester tester) => tester
    .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
    .map((widget) => widget.opacity)
    .first;

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
}) =>
    PlaybackPlan(
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
          if (codec != null)
            <String, dynamic>{'Index': 0, 'Type': 'Video', 'Codec': codec},
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
    serverId: testServerId,
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

class _FailingActionEngine extends TestPlaybackEngine {
  @override
  Future<void> seek(Duration position) async => throw StateError('seek failed');

  @override
  Future<void> setVolume(double value) async =>
      throw StateError('volume failed');
}

class _TwoTrackController implements TrackSelectionController {
  static const _audio = RodPlayerTrack(
    engineTrackId: 'audio-1',
    serverStreamIndex: 0,
    label: 'English',
    language: 'eng',
    title: 'English',
  );
  static const _audioCommentary = RodPlayerTrack(
    engineTrackId: 'audio-2',
    serverStreamIndex: 1,
    label: 'English Commentary',
    language: 'eng',
    title: 'English Commentary',
  );

  @override
  TrackSelectionCapabilities get capabilities =>
      const TrackSelectionCapabilities(
        audioSelection: CapabilitySupport.supported,
      );

  @override
  List<RodPlayerTrack> get audioTracks =>
      const <RodPlayerTrack>[_audio, _audioCommentary];

  @override
  List<RodPlayerTrack> get subtitleTracks => const <RodPlayerTrack>[];

  @override
  RodPlayerTrack? get selectedAudio => _audio;

  @override
  RodPlayerTrack? get selectedSubtitle => null;

  @override
  Future<TrackSwitchResult> selectAudio(RodPlayerTrack track) async =>
      const TrackSwitchResult(
          mode: TrackSwitchMode.local, serverStreamIndex: 0);

  @override
  Future<TrackSwitchResult> selectSubtitle(RodPlayerTrack? track) async =>
      const TrackSwitchResult(mode: TrackSwitchMode.local);
}

class _PlayerUserDataClient extends JellyfinApiClient {
  _PlayerUserDataClient()
      : super(
          baseUrl: 'https://media.example.com',
          identity: testIdentity,
          serverId: testServerId,
          client: _NoopClient(),
        );

  final favoriteCalls = <bool>[];
  final playedCalls = <bool>[];
  final item = JellyfinLibraryItem.fromJson(<String, dynamic>{
    'Id': 'movie',
    'Name': 'Movie',
    'Type': 'Movie',
    'UserData': <String, dynamic>{'IsFavorite': false, 'Played': false},
  });

  @override
  Future<JellyfinLibraryItem> getItem(String itemId) async => item;

  @override
  Future<void> setFavorite(
      {required String itemId, required bool isFavorite}) async {
    favoriteCalls.add(isFavorite);
  }

  @override
  Future<void> setPlayed({required String itemId, required bool played}) async {
    playedCalls.add(played);
  }
}

class _FakeSurface implements PlaybackVideoSurface {
  const _FakeSurface();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Colors.black, child: Text('surface'));
}

class _InputCountingEngine extends TestPlaybackEngine {
  _InputCountingEngine({required super.id});

  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> play() async {
    playCalls++;
    await super.play();
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    await super.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    await super.seek(position);
  }

  void resetCounts() {
    playCalls = 0;
    pauseCalls = 0;
    seekCalls = 0;
  }
}

class _FakeFullscreenWindow implements PlayerFullscreenWindow {
  bool fullscreen = false;
  bool maximized = false;

  @override
  Future<bool> isFullscreen() async => fullscreen;

  @override
  Future<bool> isMaximized() async => maximized;

  @override
  Future<void> setFullscreen(bool value) async {
    fullscreen = value;
  }

  @override
  Future<void> maximize() async {
    maximized = true;
  }
}

class _NamedSurface implements PlaybackVideoSurface {
  const _NamedSurface(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Text(name);
}

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream<List<int>>.empty(), 204);
}
