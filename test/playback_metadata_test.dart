import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/api/models/media_segment.dart';
import 'package:rodplayer/core/playback/advanced_playback.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/api/models/play_method.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/logical_playback_session.dart';
import 'package:rodplayer/core/playback/playback_metadata.dart';
import 'package:rodplayer/core/playback/playback_plan.dart';

void main() {
  test('chapter ticks parse in chronological order without fabrication', () {
    final metadata = PlaybackMetadata.fromLibraryItem(_item(<String, dynamic>{
      'Chapters': <Map<String, dynamic>>[
        <String, dynamic>{'Name': 'Second', 'StartPositionTicks': 20000000},
        <String, dynamic>{'Name': 'First', 'StartPositionTicks': 0},
        <String, dynamic>{'Name': 'Broken', 'StartPositionTicks': -1},
        <String, dynamic>{'Name': 'Malformed', 'StartPositionTicks': 'not-a-tick'},
      ],
    }));

    expect(metadata.chapters.map((chapter) => chapter.title), <String>['First', 'Second']);
    expect(metadata.chapters.first.start, Duration.zero);
    expect(metadata.chapters.last.start, const Duration(seconds: 2));
    expect(metadata.chapters.first.end, const Duration(seconds: 2));
    expect(metadata.chapters.last.end, isNull);
  });

  test('markers preserve unknown server kinds and reject invalid ranges', () {
    final metadata = PlaybackMetadata.fromLibraryItem(_item(<String, dynamic>{
      'MediaSegments': <Map<String, dynamic>>[
        <String, dynamic>{'Type': 'SponsorBlock', 'StartTicks': 10000000, 'EndTicks': 20000000},
        <String, dynamic>{'Type': 'Intro', 'StartTicks': -1, 'EndTicks': 10000000},
        <String, dynamic>{'Type': 'Credits', 'StartTicks': 20000000, 'EndTicks': 20000000},
      ],
    }));

    expect(metadata.markers, hasLength(1));
    expect(metadata.markers.single.kind, 'SponsorBlock');
    expect(metadata.markers.single.start, const Duration(seconds: 1));
  });

  test('missing optional playback metadata remains empty', () {
    final metadata = PlaybackMetadata.fromLibraryItem(_item(const <String, dynamic>{}));
    expect(metadata.chapters, isEmpty);
    expect(metadata.markers, isEmpty);
  });

  test('only explicit server intro and outro markers are actionable', () {
    final metadata = PlaybackMetadata.fromLibraryItem(_item(<String, dynamic>{
      'Chapters': <Map<String, dynamic>>[<String, dynamic>{'Name': 'Opening', 'StartTicks': 0}],
      'MediaSegments': <Map<String, dynamic>>[
        <String, dynamic>{'Type': 'Intro', 'StartTicks': 10000000, 'EndTicks': 20000000},
        <String, dynamic>{'Type': 'Outro', 'StartTicks': 30000000, 'EndTicks': 40000000},
        <String, dynamic>{'Type': 'Recap', 'StartTicks': 50000000, 'EndTicks': 60000000},
      ],
    }));

    expect(metadata.chapters.single.title, 'Opening');
    expect(metadata.markers.map((marker) => marker.skipAction?.label), <String?>['Skip Intro', 'Skip Outro', null]);
  });

  test('media source hasSegments preserves unknown separately from false', () {
    expect(MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'a', 'HasSegments': true}).hasSegments, isTrue);
    expect(MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'b', 'HasSegments': false}).hasSegments, isFalse);
    expect(MediaSourceInfo.fromJson(<String, dynamic>{'Id': 'c'}).hasSegments, isNull);
  });

  test('logical metadata survives a backend plan replacement', () {
    final first = _plan('one');
    final session = LogicalPlaybackSession(id: 'logical', itemId: 'item', activePlan: first);
    session.updateMetadata(PlaybackMetadata.fromLibraryItem(_item(<String, dynamic>{
      'Chapters': <Map<String, dynamic>>[<String, dynamic>{'Name': 'Opening', 'StartPositionTicks': 0}],
    })));

    session.activatePlan(_plan('two'));

    expect(session.metadata.chapters.single.title, 'Opening');
    expect(session.activePlan.engineId, 'two');
  });


  test('media segment DTO rejects invalid ranges and preserves unknown type', () {
    expect(JellyfinMediaSegment.fromJson(<String, dynamic>{
      'Type': 'Intro',
      'EndTicks': 20000000,
    }), isNull);
    expect(JellyfinMediaSegment.fromJson(<String, dynamic>{
      'Type': 'Intro',
      'StartTicks': 10000000,
    }), isNull);
    expect(JellyfinMediaSegment.fromJson(<String, dynamic>{
      'Type': 'Intro',
      'StartTicks': -1,
      'EndTicks': 10000000,
    }), isNull);
    expect(JellyfinMediaSegment.fromJson(<String, dynamic>{
      'Type': 'Intro',
      'StartTicks': 10000000,
      'EndTicks': 10000000,
    }), isNull);
    expect(JellyfinMediaSegment.fromJson(<String, dynamic>{
      'Type': 'Intro',
      'StartTicks': 20000000,
      'EndTicks': 10000000,
    }), isNull);

    final unknown = JellyfinMediaSegment.fromJson(<String, dynamic>{
      'Id': 'unknown-id',
      'ItemId': 'item',
      'Type': 'CustomServerMarker',
      'StartTicks': 10000000,
      'EndTicks': 20000000,
    });

    expect(unknown, isNotNull);
    expect(unknown!.type, 'CustomServerMarker');
    expect(unknown.id, 'unknown-id');
    expect(unknown.itemId, 'item');
    expect(unknown.start, const Duration(seconds: 1));
    expect(unknown.end, const Duration(seconds: 2));
  });

  test('only Intro and Outro marker kinds are actionable', () {
    PlaybackMarker marker(String kind) => PlaybackMarker(
          kind: kind,
          start: const Duration(seconds: 1),
          end: const Duration(seconds: 2),
        );

    expect(marker('Intro').skipAction?.label, 'Skip Intro');
    expect(marker('Outro').skipAction?.label, 'Skip Outro');

    for (final kind in <String>[
      'Recap',
      'Preview',
      'Commercial',
      'Unknown',
      'custom',
      'Credits',
    ]) {
      expect(marker(kind).skipAction, isNull, reason: kind);
    }
  });

  test('chapter names never create skip markers', () {
    final metadata = PlaybackMetadata.fromLibraryItem(_item(<String, dynamic>{
      'Chapters': <Map<String, dynamic>>[
        <String, dynamic>{'Name': 'Intro', 'StartTicks': 0},
        <String, dynamic>{'Name': 'Opening', 'StartTicks': 10000000},
        <String, dynamic>{'Name': 'OP', 'StartTicks': 20000000},
        <String, dynamic>{'Name': 'Ending', 'StartTicks': 30000000},
      ],
    }));

    expect(
      metadata.chapters.map((chapter) => chapter.title),
      <String>['Intro', 'Opening', 'OP', 'Ending'],
    );
    expect(metadata.markers, isEmpty);
  });

  test('authoritative empty segments clear markers while unavailable preserves prior metadata', () {
    final existing = PlaybackMetadata(
      markers: const <PlaybackMarker>[
        PlaybackMarker(
          kind: 'Intro',
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
        ),
      ],
    );

    final unavailable = existing;
    final authoritativeEmpty = existing.withMediaSegments(const <PlaybackMarker>[]);
    final authoritativeDeduplicated = existing.withMediaSegments(const <PlaybackMarker>[
      PlaybackMarker(
        kind: 'Outro',
        start: Duration(seconds: 10),
        end: Duration(seconds: 12),
      ),
      PlaybackMarker(
        kind: 'Outro',
        start: Duration(seconds: 10),
        end: Duration(seconds: 12),
      ),
    ]);

    expect(unavailable.markers, hasLength(1));
    expect(unavailable.markers.single.kind, 'Intro');
    expect(authoritativeEmpty.markers, isEmpty);
    expect(authoritativeDeduplicated.markers, hasLength(1));
    expect(authoritativeDeduplicated.markers.single.kind, 'Outro');
  });
}

JellyfinLibraryItem _item(Map<String, dynamic> extras) => JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'item', 'Name': 'Item', ...extras});

PlaybackPlan _plan(String engineId) => PlaybackPlan(
      itemId: 'item',
      mediaSourceId: engineId,
      playSessionId: 'play-$engineId',
      playMethod: PlayMethod.directPlay,
      playbackUri: Uri.parse('https://server/$engineId'),
      engineId: engineId,
      source: MediaSourceInfo.fromJson(<String, dynamic>{'Id': engineId, 'MediaStreams': <dynamic>[]}),
    );
