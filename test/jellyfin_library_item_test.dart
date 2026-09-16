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
      'Taglines': <String>['Tag', 'Second'],
      'Genres': <String>['Drama', 'Sci-Fi'],
      'Studios': <Map<String, dynamic>>[<String, dynamic>{'Name': 'Studio'}],
      'People': <Map<String, dynamic>>[<String, dynamic>{'Id': 'p1', 'Name': 'Actor', 'Role': 'Lead', 'Type': 'Actor', 'ImageTags': <String, dynamic>{'Primary': 'person-p'}}],
      'RunTimeTicks': 1200000000,
      'Status': 'Continuing',
      'EndDate': '2025-02-03T00:00:00Z',
      'ChildCount': 3,
      'RecursiveItemCount': 7,
      'PrimaryImageAspectRatio': 0.7,
      'ImageTags': <String, dynamic>{'Primary': 'p', 'Thumb': 't'},
      'BackdropImageTags': <String>['b'],
      'UserData': <String, dynamic>{'IsFavorite': true, 'Played': true, 'PlaybackPositionTicks': 1000, 'PlayedPercentage': 50.5, 'UnplayedItemCount': 4},
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
    expect(item.genres, <String>['Drama', 'Sci-Fi']);
    expect(item.studios, <String>['Studio']);
    expect(item.people.single.name, 'Actor');
    expect(item.people.single.primaryImageTag, 'person-p');
    expect(item.status, 'Continuing');
    expect(item.endDate, DateTime.utc(2025, 2, 3));
    expect(item.childCount, 3);
    expect(item.recursiveItemCount, 7);
    expect(item.runTimeTicks, 1200000000);
    expect(item.primaryImageTag, 'p');
    expect(item.backdropImageTag, 'b');
    expect(item.thumbImageTag, 't');
    expect(item.primaryImageAspectRatio, 0.7);
    expect(item.isFavorite, isTrue);
    expect(item.played, isTrue);
    expect(item.playbackPositionTicks, 1000);
    expect(item.playedPercentage, 50.5);
    expect(item.userData.unplayedItemCount, 4);
    expect(() => item.genres.add('x'), throwsUnsupportedError);
    expect(() => item.studios.add('x'), throwsUnsupportedError);
    expect(() => item.people.add(const JellyfinPerson(id: 'x', name: 'x')), throwsUnsupportedError);
    expect(() => item.backdropImageTags.add('x'), throwsUnsupportedError);
    expect(item.imageUrl('https://server'), 'https://server/Items/movie%201/Images/Primary?tag=p&quality=90');
    expect(item.imageUrl('https://server/jellyfin'), 'https://server/jellyfin/Items/movie%201/Images/Primary?tag=p&quality=90');
    expect(item.raw['Name'], 'Film');
  });

  test('parses taglines conservatively', () {
    expect(JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'a', 'Name': 'A', 'Taglines': <String>['First', 'Second']}).tagline, 'First');
    expect(JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'a', 'Name': 'A', 'Taglines': <String>['', '  ']}).tagline, isNull);
    expect(JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'a', 'Name': 'A', 'Tagline': 'Legacy'}).tagline, 'Legacy');
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
      'SeasonName': 'Season Two',
      'ParentId': 'parent',
      'ParentIndexNumber': 2,
      'IndexNumber': 3,
    });

    expect(series.kind, JellyfinItemKind.series);
    expect(episode.kind, JellyfinItemKind.episode);
    expect(episode.seriesName, 'Show');
    expect(episode.seriesId, 'series');
    expect(episode.seasonId, 'season');
    expect(episode.seasonName, 'Season Two');
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
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'x', 'Name': 'Mystery', 'Type': 'Weird', 'ProductionYear': 'not-a-number', 'EndDate': 'not-a-date', 'BackdropImageTag': 'single'});

    expect(item.kind, JellyfinItemKind.unknown);
    expect(item.rawType, 'Weird');
    expect(item.productionYear, isNull);
    expect(item.endDate, isNull);
    expect(item.runTimeTicks, isNull);
    expect(item.primaryImageTag, isNull);
    expect(item.backdropImageTags, <String>['single']);
    expect(() => item.backdropImageTags.add('x'), throwsUnsupportedError);
    expect(item.imageUrl('https://server'), isNull);
  });

  test('sparse M4 collections stay conservative', () {
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{'Id': 'x', 'Name': 'Sparse', 'Genres': 'bad', 'Studios': 'bad', 'People': 'bad'});
    expect(item.genres, isEmpty);
    expect(item.studios, isEmpty);
    expect(item.people, isEmpty);
  });

  test('user-data changes patch matching item without rewriting metadata', () {
    final item = JellyfinLibraryItem.fromJson(<String, dynamic>{
      'Id': 'item',
      'Name': 'Film',
      'Type': 'Movie',
      'Overview': 'Story',
      'RunTimeTicks': 1000,
      'UserData': <String, dynamic>{'IsFavorite': false, 'Played': false, 'PlayedPercentage': 25},
    });

    final favorite = item.withUserDataChange(const JellyfinUserDataChange(itemId: 'item', isFavorite: true));
    expect(favorite.userData.isFavorite, isTrue);
    expect(favorite.userData.played, isFalse);
    expect(favorite.playedPercentage, 25);
    expect(favorite.overview, 'Story');
    expect(favorite.raw['Overview'], 'Story');

    final played = favorite.withUserDataChange(const JellyfinUserDataChange(itemId: 'item', played: true));
    expect(played.userData.isFavorite, isTrue);
    expect(played.userData.played, isTrue);
    expect(played.playedPercentage, 25);

    final unrelated = played.withUserDataChange(const JellyfinUserDataChange(itemId: 'other', isFavorite: false, played: false, playbackProgressMayHaveChanged: true));
    expect(unrelated.userData.isFavorite, isTrue);
    expect(unrelated.userData.played, isTrue);
    expect(unrelated.playedPercentage, 25);
  });
}
