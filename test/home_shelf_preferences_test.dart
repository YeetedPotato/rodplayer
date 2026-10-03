import 'package:flutter_test/flutter_test.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Home shelf order and visibility persist with safe defaults', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    var settings = await HomeShelfPreferences.load(preferences: prefs);
    expect(settings.order, HomeShelfId.values);
    expect(settings.visible, HomeShelfPreferences.defaults.visible);

    settings = settings.copyWith(
      order: <HomeShelfId>[
        HomeShelfId.latestMovies,
        HomeShelfId.continueWatching,
        HomeShelfId.nextUp,
        HomeShelfId.latestShows,
        HomeShelfId.popularMovies,
        HomeShelfId.popularShows,
      ],
      visible: <HomeShelfId>{HomeShelfId.latestMovies},
    );
    await settings.save(prefs);
    final restored = await HomeShelfPreferences.load(preferences: prefs);
    expect(restored.order, settings.order);
    expect(restored.visible, settings.visible);
  });

  test('invalid order falls back and unknown visibility keys are ignored',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      HomeShelfPreferences.orderKey: <String>['latestMovies', 'latestMovies'],
      HomeShelfPreferences.visibleKey: <String>['nextUp', 'futureShelf'],
    });
    final prefs = await SharedPreferences.getInstance();
    final settings = await HomeShelfPreferences.load(preferences: prefs);
    expect(settings.order, HomeShelfPreferences.defaults.order);
    expect(settings.visible, <HomeShelfId>{
      HomeShelfId.nextUp,
      HomeShelfId.popularMovies,
      HomeShelfId.popularShows,
    });
  });

  test('new shelves migrate once and can be hidden afterwards', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      HomeShelfPreferences.visibleKey: <String>[
        HomeShelfId.continueWatching.key,
        HomeShelfId.nextUp.key,
      ],
    });
    final prefs = await SharedPreferences.getInstance();
    final migrated = await HomeShelfPreferences.load(preferences: prefs);
    expect(
        migrated.visible,
        containsAll(<HomeShelfId>{
          HomeShelfId.popularMovies,
          HomeShelfId.popularShows,
        }));

    final hidden = migrated.copyWith(visible: <HomeShelfId>{
      HomeShelfId.continueWatching,
      HomeShelfId.nextUp,
    });
    await hidden.save(prefs);
    final restored = await HomeShelfPreferences.load(preferences: prefs);
    expect(restored.visible, hidden.visible);
  });
}
