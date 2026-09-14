import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';
import 'package:rodplayer/core/playback/playback_reporting.dart';

import 'test_support.dart';

void main() {
  PlaybackPlan plan(String id, PlayMethod method) => PlaybackPlan(
        itemId: 'item',
        mediaSourceId: id,
        playSessionId: 'play-$id',
        playMethod: method,
        playbackUri: Uri.parse('https://media/$id'),
        engineId: 'media_kit',
        selectedAudioStreamIndex: 1,
        selectedSubtitleStreamIndex: 2,
        source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': id, 'MediaStreams': <dynamic>[]}),
      );

  test('report state serializes Jellyfin-compatible payload', () {
    final state = PlaybackReportState(itemId: 'item', playSessionId: 'play', mediaSourceId: 'source', positionTicks: 123, playMethod: PlayMethod.directPlay, audioStreamIndex: 1, subtitleStreamIndex: 2);
    expect(state.toJson(), containsPair('PlaySessionId', 'play'));
    expect(state.toJson(), containsPair('MediaSourceId', 'source'));
    expect(state.toJson(), containsPair('PlayMethod', 'DirectPlay'));
    expect(state.toJson(), containsPair('AudioStreamIndex', 1));
    expect(state.toJson(), containsPair('SubtitleStreamIndex', 2));
    expect(state.toJson(), containsPair('PositionTicks', 123));
  });

  test('next progress state reflects active plan changes', () {
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay));
    session.activatePlan(plan('B', PlayMethod.transcode));
    final state = PlaybackReportState(
      itemId: session.itemId,
      playSessionId: session.activePlan.playSessionId,
      mediaSourceId: session.activePlan.mediaSourceId,
      positionTicks: 10,
      playMethod: session.activePlan.playMethod,
    );
    expect(state.toJson(), containsPair('MediaSourceId', 'B'));
    expect(state.toJson(), containsPair('PlayMethod', 'Transcode'));
  });

  test('reporting after track switch emits updated Jellyfin stream index', () async {
    late Map<String, dynamic> payload;
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      client: _CaptureClient((request, body) {
        payload = jsonDecode(body) as Map<String, dynamic>;
        return http.Response('', 204);
      }),
    );
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay));
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    await PlaybackReporter(client: client, session: session).progress(const Duration(seconds: 5), const Duration(minutes: 1));
    expect(payload, containsPair('AudioStreamIndex', 4));
    expect(payload, containsPair('SubtitleStreamIndex', 8));
  });
}

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.handler);
  final FutureOr<http.Response> Function(http.BaseRequest request, String body) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final response = await handler(request, utf8.decode(bytes));
    return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, request: request);
  }
}
