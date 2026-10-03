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
  test(
    'acknowledged Stop A is not repeated when Start B fails then retries',
    () async {
      final calls = <String>[];
      var failB = true;
      final client = JellyfinApiClient(
        baseUrl: 'https://media.example.test',
        identity: testIdentity,
        serverId: testServerId,
        client: _CaptureClient((request, body) {
          final payload = jsonDecode(body) as Map<String, dynamic>;
          calls.add('${request.url.path}:${payload['MediaSourceId']}');
          if (request.url.path == '/Sessions/Playing' &&
              payload['MediaSourceId'] == 'B' &&
              failB) {
            failB = false;
            return http.Response('', 503);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);
      final session = LogicalPlaybackSession(
        id: 'report',
        itemId: 'item',
        activePlan: _reportPlan('A'),
      );
      final reporter = PlaybackReporter(client: client, session: session);
      await reporter.started();
      session.activatePlan(_reportPlan('B'));
      await reporter.progress(Duration.zero, const Duration(minutes: 1));
      expect(reporter.reportingFailures, 1);
      await reporter.progress(
        const Duration(seconds: 2),
        const Duration(minutes: 1),
      );
      await reporter.stopped(const Duration(seconds: 3));
      await reporter.stopped(const Duration(seconds: 3));
      expect(calls, [
        '/Sessions/Playing:A',
        '/Sessions/Playing/Stopped:A',
        '/Sessions/Playing:B',
        '/Sessions/Playing:B',
        '/Sessions/Playing/Progress:B',
        '/Sessions/Playing/Stopped:B',
      ]);
    },
  );

  test(
    'failed Stop A retries before starting B without failing playback',
    () async {
      final calls = <String>[];
      var failStop = true;
      final client = JellyfinApiClient(
        baseUrl: 'https://media.example.test',
        identity: testIdentity,
        serverId: testServerId,
        client: _CaptureClient((request, body) {
          final source = (jsonDecode(body) as Map)['MediaSourceId'];
          calls.add('${request.url.path}:$source');
          if (request.url.path.endsWith('/Stopped') && failStop) {
            failStop = false;
            return http.Response('', 503);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);
      final session = LogicalPlaybackSession(
        id: 'report',
        itemId: 'item',
        activePlan: _reportPlan('A'),
      );
      final reporter = PlaybackReporter(client: client, session: session);
      await reporter.started();
      session.activatePlan(_reportPlan('B'));
      await reporter.synchronize(Duration.zero);
      expect(calls, ['/Sessions/Playing:A', '/Sessions/Playing/Stopped:A']);
      await reporter.synchronize(Duration.zero);
      expect(calls, [
        '/Sessions/Playing:A',
        '/Sessions/Playing/Stopped:A',
        '/Sessions/Playing/Stopped:A',
        '/Sessions/Playing:B',
      ]);
    },
  );

  for (final stopPending in [false, true]) {
    test(
      'pending Start B is serialized with ${stopPending ? 'final stop' : 'C supersession'}',
      () async {
        final gate = Completer<http.Response>();
        final entered = Completer<void>();
        final calls = <String>[];
        final client = JellyfinApiClient(
          baseUrl: 'https://media.example.test',
          identity: testIdentity,
          serverId: testServerId,
          client: _CaptureClient((request, body) {
            final payload = jsonDecode(body) as Map;
            final source = payload['MediaSourceId'];
            expect(payload['PlaySessionId'], 'play-$source');
            calls.add('${request.url.path}:$source');
            if (request.url.path == '/Sessions/Playing' &&
                source == 'B' &&
                !entered.isCompleted) {
              entered.complete();
              return gate.future;
            }
            return http.Response('', 204);
          }),
        );
        addTearDown(client.close);
        final session = LogicalPlaybackSession(
          id: 'report',
          itemId: 'item',
          activePlan: _reportPlan('A'),
        );
        final reporter = PlaybackReporter(client: client, session: session);
        await reporter.started();
        session.activatePlan(_reportPlan('B'));
        final b = reporter.synchronize(Duration.zero);
        await entered.future;
        final queuedProgress = reporter.progress(
          Duration.zero,
          const Duration(minutes: 1),
        );
        final Future<void> last;
        if (stopPending) {
          last = reporter.stopped(Duration.zero);
        } else {
          session.activatePlan(_reportPlan('C'));
          last = reporter.synchronize(Duration.zero);
        }
        gate.complete(http.Response('', stopPending ? 204 : 503));
        await Future.wait([b, queuedProgress, last]);
        if (!stopPending) await reporter.stopped(Duration.zero);
        expect(
          calls.where((call) => call == '/Sessions/Playing/Stopped:A'),
          hasLength(1),
        );
        expect(
          calls.last,
          stopPending
              ? '/Sessions/Playing/Stopped:B'
              : '/Sessions/Playing/Stopped:C',
        );
        if (stopPending)
          expect(calls.any((call) => call.contains('/Progress')), isFalse);
      },
    );
  }

  PlaybackPlan plan(String id, PlayMethod method) => PlaybackPlan(
        itemId: 'item',
        mediaSourceId: id,
        playSessionId: 'play-$id',
        playMethod: method,
        playbackUri: Uri.parse('https://media/$id'),
        engineId: 'media_kit',
        selectedAudioStreamIndex: 1,
        selectedSubtitleStreamIndex: 2,
        source: MediaSourceInfo.fromJson(<String, dynamic>{
          'Id': id,
          'MediaStreams': <dynamic>[],
        }),
      );

  test('report state serializes Jellyfin-compatible payload', () {
    final state = PlaybackReportState(
      itemId: 'item',
      playSessionId: 'play',
      mediaSourceId: 'source',
      positionTicks: 123,
      playMethod: PlayMethod.directPlay,
      audioStreamIndex: 1,
      subtitleStreamIndex: 2,
    );
    expect(state.toJson(), containsPair('PlaySessionId', 'play'));
    expect(state.toJson(), containsPair('MediaSourceId', 'source'));
    expect(state.toJson(), containsPair('PlayMethod', 'DirectPlay'));
    expect(state.toJson(), containsPair('AudioStreamIndex', 1));
    expect(state.toJson(), containsPair('SubtitleStreamIndex', 2));
    expect(state.toJson(), containsPair('PositionTicks', 123));
  });

  test('next progress state reflects active plan changes', () {
    final session = LogicalPlaybackSession(
      id: 'logical',
      itemId: 'item',
      activePlan: plan('A', PlayMethod.directPlay),
    );
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

  test(
    'reporting after track switch emits updated Jellyfin stream index',
    () async {
      late Map<String, dynamic> payload;
      final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _CaptureClient((request, body) {
          payload = jsonDecode(body) as Map<String, dynamic>;
          return http.Response('', 204);
        }),
      );
      final session = LogicalPlaybackSession(
        id: 'logical',
        itemId: 'item',
        activePlan: plan('A', PlayMethod.directPlay),
      );
      session.selectedAudio = 4;
      session.selectedSubtitle = 8;
      await PlaybackReporter(
        client: client,
        session: session,
      ).progress(const Duration(seconds: 5), const Duration(minutes: 1));
      expect(payload, containsPair('AudioStreamIndex', 4));
      expect(payload, containsPair('SubtitleStreamIndex', 8));
    },
  );

  test(
    'reporter transitions immutable server targets in lifecycle order',
    () async {
      final payloads = <Map<String, dynamic>>[];
      final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _CaptureClient((_, body) {
          payloads.add(jsonDecode(body) as Map<String, dynamic>);
          return http.Response('', 204);
        }),
      );
      final session = LogicalPlaybackSession(
        id: 'logical',
        itemId: 'item',
        activePlan: plan('A', PlayMethod.directPlay),
      );
      final reporter = PlaybackReporter(client: client, session: session);
      await reporter.started();
      session.activatePlan(plan('B', PlayMethod.transcode));
      await reporter.progress(
        const Duration(seconds: 3),
        const Duration(minutes: 1),
      );
      await reporter.stopped(const Duration(seconds: 4));
      expect(payloads.map((value) => value['MediaSourceId']), <String>[
        'A',
        'A',
        'B',
        'B',
        'B',
      ]);
      expect(payloads.map((value) => value['PlaySessionId']), <String>[
        'play-A',
        'play-A',
        'play-B',
        'play-B',
        'play-B',
      ]);
    },
  );

  test(
      'queued progress keeps its captured target and stream indexes through a transition',
      () async {
    final gate = Completer<http.Response>();
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _CaptureClient((_, body) {
        final payload = jsonDecode(body) as Map<String, dynamic>;
        payloads.add(payload);
        if (payload['MediaSourceId'] == 'A' &&
            payload['EventName'] == 'timeupdate') return gate.future;
        return http.Response('', 204);
      }),
    );
    final session = LogicalPlaybackSession(
      id: 'logical',
      itemId: 'item',
      activePlan: plan('A', PlayMethod.directPlay),
    )
      ..selectedAudio = 1
      ..selectedSubtitle = 2;
    final reporter = PlaybackReporter(client: client, session: session);
    await reporter.started();
    final progressA = reporter.progress(
      const Duration(seconds: 1),
      const Duration(minutes: 1),
    );
    session.activatePlan(plan('B', PlayMethod.transcode));
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    final progressB = reporter.progress(
      const Duration(seconds: 2),
      const Duration(minutes: 1),
    );
    gate.complete(http.Response('', 204));
    await Future.wait(<Future<void>>[progressA, progressB]);
    expect(payloads.map((value) => value['MediaSourceId']), <String>[
      'A',
      'A',
      'A',
      'B',
      'B',
    ]);
    expect(payloads[1], containsPair('AudioStreamIndex', 1));
    expect(payloads[1], containsPair('SubtitleStreamIndex', 2));
  });

  test(
    'terminal stop blocks late queued progress and duplicate start',
    () async {
      final gate = Completer<http.Response>();
      final payloads = <Map<String, dynamic>>[];
      final paths = <String>[];
      final client = JellyfinApiClient(
        baseUrl: 'https://media.example.com',
        identity: testIdentity,
        serverId: testServerId,
        client: _CaptureClient((request, body) {
          paths.add(request.url.path);
          final payload = jsonDecode(body) as Map<String, dynamic>;
          payloads.add(payload);
          if (payload['EventName'] == 'timeupdate') return gate.future;
          return http.Response('', 204);
        }),
      );
      final session = LogicalPlaybackSession(
        id: 'logical',
        itemId: 'item',
        activePlan: plan('A', PlayMethod.directPlay),
      );
      final reporter = PlaybackReporter(client: client, session: session);
      await reporter.started();
      final inFlight = reporter.progress(
        const Duration(seconds: 1),
        const Duration(minutes: 1),
      );
      await Future<void>.delayed(Duration.zero);
      final stop = reporter.stopped(const Duration(seconds: 2));
      final lateProgress = reporter.progress(
        const Duration(seconds: 3),
        const Duration(minutes: 1),
      );
      final duplicateStart = reporter.started();
      final lateSynchronize = reporter.synchronize(const Duration(seconds: 4));
      gate.complete(http.Response('', 204));
      await Future.wait<void>(<Future<void>>[
        inFlight,
        stop,
        lateProgress,
        duplicateStart,
        lateSynchronize,
      ]);

      expect(payloads.map((payload) => payload['EventName']), <Object?>[
        null,
        'timeupdate',
        null,
      ]);
      expect(paths, <String>[
        '/Sessions/Playing',
        '/Sessions/Playing/Progress',
        '/Sessions/Playing/Stopped',
      ]);
    },
  );

  test(
      'synchronize transitions lifecycle without progress and preserves old indexes',
      () async {
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _CaptureClient((_, body) {
        payloads.add(jsonDecode(body) as Map<String, dynamic>);
        return http.Response('', 204);
      }),
    );
    final session = LogicalPlaybackSession(
      id: 'logical',
      itemId: 'item',
      activePlan: plan('A', PlayMethod.directPlay),
    )
      ..selectedAudio = 1
      ..selectedSubtitle = 2;
    final reporter = PlaybackReporter(client: client, session: session);
    await reporter.started();
    await reporter.synchronize(Duration.zero);
    expect(payloads, hasLength(1));
    session.activatePlan(plan('B', PlayMethod.transcode));
    session.selectedAudio = 4;
    session.selectedSubtitle = 8;
    await reporter.synchronize(const Duration(seconds: 3));
    expect(payloads, hasLength(3));
    expect(payloads[1], containsPair('MediaSourceId', 'A'));
    expect(payloads[1], containsPair('AudioStreamIndex', 1));
    expect(payloads[1], containsPair('SubtitleStreamIndex', 2));
    expect(payloads[2], containsPair('MediaSourceId', 'B'));
    expect(
      payloads.where((value) => value['EventName'] == 'timeupdate'),
      isEmpty,
    );
  });

  test(
      'same-target synchronize refreshes stream indexes without a lifecycle event',
      () async {
    final payloads = <Map<String, dynamic>>[];
    final client = JellyfinApiClient(
      baseUrl: 'https://media.example.com',
      identity: testIdentity,
      serverId: testServerId,
      client: _CaptureClient((_, body) {
        payloads.add(jsonDecode(body) as Map<String, dynamic>);
        return http.Response('', 204);
      }),
    );
    final session = LogicalPlaybackSession(
      id: 'logical',
      itemId: 'item',
      activePlan: plan('A', PlayMethod.directPlay),
    )
      ..selectedAudio = 1
      ..selectedSubtitle = 2;
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
    expect(
      payloads.where((value) => value['EventName'] == 'timeupdate'),
      isEmpty,
    );
  });
}

PlaybackPlan _reportPlan(String id) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: id,
      playSessionId: 'play-$id',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://media.example.test/$id'),
      engineId: 'fake',
      source: MediaSourceInfo.fromJson({'Id': id, 'MediaStreams': []}),
    );

class _CaptureClient extends http.BaseClient {
  _CaptureClient(this.handler);
  final FutureOr<http.Response> Function(http.BaseRequest request, String body)
      handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final response = await handler(request, utf8.decode(bytes));
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      request: request,
    );
  }
}
