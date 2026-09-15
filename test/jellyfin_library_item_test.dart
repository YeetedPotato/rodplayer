import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';

void main() {
  test('parses movie BaseItem metadata and images', () {
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': 'movie 1',
      'Name': 'Film',
      'Type': 'Movie',
      'MediaType': 'Video',
      'ProductionYear': 2024,
      'PremiereDate': '2024-01-02T00:00:00.0000000Z',
      'Overview': 'Story',
      'OfficialRating': 'PG-13',
      'CommunityRating': 7.5,
      'Tagline': 'Tag',
      'RunTimeTicks': 1200000000,
      'PrimaryImageAspectRatio': 0.7,
      'ImageTags': <String, dynamic>{'Primary': 'p', 'Thumb': 't'},
      'BackdropImageTags': <String>['b'],
      'UserData': <String, dynamic>{'IsFavorite': true, 'Played': true, 'PlaybackPositionTicks': 1000, 'PlayedPercentage': 50.5},
    });

    expect(item.id, 'movie 1');
    expect(item.title, 'Film');
    expect(item.kind, JellyfinItemKind.movie);
    expect(item.mediaType, 'Video');
    expect(item.productionYear, 2024);
    expect(item.premiereDate, isNotNull);
    expect(item.overview, 'Story');
    expect(item.officialRating, 'PG-13');
    expect(item.communityRating, 7.5);
    expect(item.tagline, 'Tag');
    expect(item.runTimeTicks, 1200000000);
    expect(item.primaryImageTag, 'p');
    expect(item.backdropImageTag, 'b');
    expect(item.thumbImageTag, 't');
    expect(item.primaryImageAspectRatio, 0.7);
    expect(item.isFavorite, isTrue);
    expect(item.played, isTrue);
    expect(item.playbackPositionTicks, 1000);
    expect(item.playedPercentage, 50.5);
    expect(item.imageUrl('https://server'), 'https://server/Items/movie%201/Images/Primary?tag=p&quality=90');
    expect(item.raw['Name'], 'Film');
  });

  test('parses series and episode hierarchy', () {
    final series = JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 's', 'Name': 'Show', 'Type': 'Series'});
    final episode = JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': 'e',
      'Name': 'Episode',
      'Type': 'Episode',
      'SeriesName': 'Show',
      'SeriesId': 'series',
      'SeasonId': 'season',
      'ParentId': 'parent',
      'ParentIndexNumber': 2,
      'IndexNumber': 3,
    });

    expect(series.kind, JellyfinItemKind.series);
    expect(episode.kind, JellyfinItemKind.episode);
    expect(episode.seriesName, 'Show');
    expect(episode.seriesId, 'series');
    expect(episode.seasonId, 'season');
    expect(episode.parentId, 'parent');
    expect(episode.seasonNumber, 2);
    expect(episode.episodeNumber, 3);
  });

  test('next up and resumable keep typed fields', () {
    final json = <String, dynamic>{
      'Id': 'item',
      'Name': 'Episode',
      'Type': 'Episode',
      'RunTimeTicks': '9000',
      'UserData': <String, dynamic>{'PlaybackPositionTicks': '4500'},
    };

    expect(NextUpItem.fromJson(json).runTimeTicks, 9000);
    expect(ResumableItem.fromJson(json).playbackPositionTicks, 4500);
  });

  test('missing optional fields and unknown type stay conservative', () {
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'x', 'Name': 'Mystery', 'Type': 'Weird', 'ProductionYear': 'not-a-number'});

    expect(item.kind, JellyfinItemKind.unknown);
    expect(item.rawType, 'Weird');
    expect(item.productionYear, isNull);
    expect(item.runTimeTicks, isNull);
    expect(item.primaryImageTag, isNull);
    expect(item.imageUrl('https://server'), isNull);
  });

  test('search hint parses ItemId without pretending full item metadata exists', () {
    final hint = JellyfinSearchHint.fromJson(<String, dynamic>{
      'ItemId': 'item',
      'Name': 'Result',
      'Type': 'Series',
      'ProductionYear': 2020,
      'ImageTags': <String, dynamic>{'Primary': 'p'},
    });

    expect(hint.id, 'item');
    expect(hint.title, 'Result');
    expect(hint.kind, JellyfinItemKind.series);
    expect(hint.productionYear, 2020);
    expect(hint.primaryImageTag, 'p');
    expect(hint.raw.containsKey('Overview'), isFalse);
  });

  test('search hint tolerates missing optional fields', () {
    final hint = JellyfinSearchHint.fromJson(<String, dynamic>{'Id': 'fallback', 'Name': 'Sparse'});

    expect(hint.id, 'fallback');
    expect(hint.primaryImageTag, isNull);
    expect(hint.productionYear, isNull);
    expect(hint.imageUrl('https://server'), isNull);
  });
}
