import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
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
