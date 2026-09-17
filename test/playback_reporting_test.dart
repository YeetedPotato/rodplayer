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

  test('reporter transitions immutable server targets in lifecycle order', () async {
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      client: _CaptureClient((_, body) {
        payloads.add(jsonDecode(body) as Map<String, dynamic>);
        return http.Response('', 204);
      }),
    );
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay));
    final reporter = PlaybackReporter(client: client, session: session);
    await reporter.started();
    session.activatePlan(plan('B', PlayMethod.transcode));
    await reporter.progress(const Duration(seconds: 3), const Duration(minutes: 1));
    await reporter.stopped(const Duration(seconds: 4));
    expect(payloads.map((value) => value['MediaSourceId']), <String>['A', 'A', 'B', 'B', 'B']);
    expect(payloads.map((value) => value['PlaySessionId']), <String>['play-A', 'play-A', 'play-B', 'play-B', 'play-B']);
  });

  test('queued progress keeps its captured target and stream indexes through a transition', () async {
    final gate = Completer<http.Response>();
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: _CaptureClient((_, body) {
      final payload = jsonDecode(body) as Map<String, dynamic>;
      payloads.add(payload);
      if (payload['MediaSourceId'] == 'A' && payload['EventName'] == 'timeupdate') return gate.future;
      return http.Response('', 204);
    }));
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay))
      ..selectedAudio = 1
      ..selectedSubtitle = 2;
    final reporter = PlaybackReporter(client: client, session: session);
    await reporter.started();
    final progressA = reporter.progress(const Duration(seconds: 1), const Duration(minutes: 1));
    session.activatePlan(plan('B', PlayMethod.transcode));
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    final progressB = reporter.progress(const Duration(seconds: 2), const Duration(minutes: 1));
    gate.complete(http.Response('', 204));
    await Future.wait(<Future<void>>[progressA, progressB]);
    expect(payloads.map((value) => value['MediaSourceId']), <String>['A', 'A', 'A', 'B', 'B']);
    expect(payloads[1], containsPair('AudioStreamIndex', 1));
    expect(payloads[1], containsPair('SubtitleStreamIndex', 2));
  });

  test('synchronize transitions lifecycle without progress and preserves old indexes', () async {
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: _CaptureClient((_, body) { payloads.add(jsonDecode(body) as Map<String, dynamic>); return http.Response('', 204); }));
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay))..selectedAudio = 1..selectedSubtitle = 2;
    final reporter = PlaybackReporter(client: client, session: session);
    await reporter.started();
    await reporter.synchronize(Duration.zero);
    expect(payloads, hasLength(1));
    session.activatePlan(plan('B', PlayMethod.transcode));
    session.selectedAudio = 4; session.selectedSubtitle = 8;
    await reporter.synchronize(const Duration(seconds: 3));
    expect(payloads, hasLength(3));
    expect(payloads[1], containsPair('MediaSourceId', 'A'));
    expect(payloads[1], containsPair('AudioStreamIndex', 1));
    expect(payloads[1], containsPair('SubtitleStreamIndex', 2));
    expect(payloads[2], containsPair('MediaSourceId', 'B'));
    expect(payloads.where((value) => value['EventName'] == 'timeupdate'), isEmpty);
  });

  test('same-target synchronize refreshes stream indexes without a lifecycle event', () async {
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(baseUrl: 'https://media.example.com', identity: testIdentity, client: _CaptureClient((_, body) { payloads.add(jsonDecode(body) as Map<String, dynamic>); return http.Response('', 204); }));
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: plan('A', PlayMethod.directPlay))..selectedAudio = 1..selectedSubtitle = 2;
    final reporter = PlaybackReporter(client: client, session: session);
    await reporter.started();
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    await reporter.synchronize(const Duration(seconds: 1));
    expect(payloads, hasLength(1));
    session.activatePlan(plan('B', PlayMethod.transcode));
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    await reporter.synchronize(const Duration(seconds: 2));
    expect(payloads, hasLength(3));
    expect(payloads[1], containsPair('MediaSourceId', 'A'));
    expect(payloads[1], containsPair('AudioStreamIndex', 4));
    expect(payloads[1], containsPair('SubtitleStreamIndex', 8));
    expect(payloads[2], containsPair('MediaSourceId', 'B'));
    expect(payloads[2], containsPair('AudioStreamIndex', 4));
    expect(payloads[2], containsPair('SubtitleStreamIndex', 8));
    expect(payloads.where((value) => value['EventName'] == 'timeupdate'), isEmpty);
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
