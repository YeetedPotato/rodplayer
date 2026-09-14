import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';

import 'test_support.dart';

class MockClient extends http.BaseClient {
  MockClient(this.body);
  final String body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async => http.StreamedResponse(Stream.value(utf8.encode(body)), 200, request: request);
}

void main() {
  test('accepts server-provided audio-only transform transcode plan', () async {
    final body = File('test/fixtures/playback_info/video_copy_audio_transcode.json').readAsStringSync();
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: MockClient(body))..userId = 'user';
    final plan = await PlaybackNegotiator(client: client).negotiate(itemId: 'item');
    expect(plan.playMethod, PlayMethod.transcode);
    expect(plan.playbackUri.toString(), contains('/Videos/source-transcode/master.m3u8'));
    expect(plan.videoCopied, isTrue);
    expect(plan.audioCopied, isFalse);
    expect(plan.containerChanged, isTrue);
  });

  test('builds standard Jellyfin direct-play URL instead of using filesystem path', () async {
    final body = File('test/fixtures/playback_info/direct_play_mkv.json').readAsStringSync();
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: MockClient(body))
      ..userId = 'user'
      ..accessToken = 'secret';
    final plan = await PlaybackNegotiator(client: client).negotiate(itemId: 'item');
    expect(plan.playMethod, PlayMethod.directPlay);
    expect(plan.playbackUri.path, '/Videos/item/stream');
    expect(plan.playbackUri.toString(), isNot(contains('/Videos/movie.mkv')));
    expect(plan.playbackUri.queryParameters, containsPair('mediaSourceId', 'source-direct'));
    expect(plan.playbackUri.queryParameters, containsPair('playSessionId', 'play-direct'));
    expect(plan.playbackUri.queryParameters, containsPair('api_key', 'secret'));
  });

  test('requested audio and subtitle indexes survive negotiation', () async {
    final body = File('test/fixtures/playback_info/direct_play_mkv.json').readAsStringSync();
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: MockClient(body))..userId = 'user';
    final plan = await PlaybackNegotiator(client: client).negotiate(itemId: 'item', audioStreamIndex: 4, subtitleStreamIndex: 7);
    expect(plan.selectedAudioStreamIndex, 4);
    expect(plan.selectedSubtitleStreamIndex, 7);
    expect(plan.playbackUri.queryParameters, containsPair('audioStreamIndex', '4'));
    expect(plan.playbackUri.queryParameters, containsPair('subtitleStreamIndex', '7'));
  });

  test('direct stream keeps server-provided transformed URL', () async {
    final body = jsonEncode(<String, dynamic>{
      'PlaySessionId': 'play-stream',
      'MediaSources': <Map<String, dynamic>>[
        <String, dynamic>{
          'Id': 'source-stream',
          'Path': '/media/Movie.mkv',
          'DirectStreamUrl': '/Videos/source-stream/stream.mkv',
          'PlayMethod': 'DirectStream',
          'MediaStreams': <dynamic>[],
        },
      ],
    });
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: MockClient(body))
      ..userId = 'user'
      ..accessToken = 'secret';
    final plan = await PlaybackNegotiator(client: client).negotiate(itemId: 'item');
    expect(plan.playMethod, PlayMethod.directStream);
    expect(plan.playbackUri.path, '/Videos/source-stream/stream.mkv');
    expect(plan.playbackUri.queryParameters, containsPair('api_key', 'secret'));
  });
}
