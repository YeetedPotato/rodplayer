import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/player/playback_video_surface.dart';
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
  });
}

class _FakeSurface implements PlaybackVideoSurface {
  const _FakeSurface();

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black, child: Text('surface'));
}

class _NoopClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(Stream<List<int>>.empty(), 204);
}
