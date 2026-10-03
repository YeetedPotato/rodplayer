import 'package:shared_preferences/shared_preferences.dart';

enum HomeShelfId {
  continueWatching('Continue Watching'),
  nextUp('Next Up'),
  latestMovies('New Movie Releases'),
  latestShows('New Episodes'),
  popularMovies('Popular Movies'),
  popularShows('Popular Shows');

  const HomeShelfId(this.label);

  final String label;

  String get key => name;
}

/// App-defined Home shelf visibility and order, stored on this device only.
class HomeShelfPreferences {
  const HomeShelfPreferences({required this.order, required this.visible});

  static const orderKey = 'nautilus.home.shelfOrder';
  static const visibleKey = 'nautilus.home.visibleShelves';
  static const schemaVersionKey = 'nautilus.home.shelfSchemaVersion';
  static const schemaVersion = 1;
  static const defaults = HomeShelfPreferences(
    order: HomeShelfId.values,
    visible: <HomeShelfId>{
      HomeShelfId.continueWatching,
      HomeShelfId.nextUp,
      HomeShelfId.latestMovies,
      HomeShelfId.latestShows,
      HomeShelfId.popularMovies,
      HomeShelfId.popularShows,
    },
  );

  final List<HomeShelfId> order;
  final Set<HomeShelfId> visible;

  static Future<HomeShelfPreferences> load({
    SharedPreferences? preferences,
  }) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final order = _readOrder(prefs.getStringList(orderKey)) ?? defaults.order;
    final storedVisible = prefs.getStringList(visibleKey);
    final visible = _readVisible(storedVisible) ?? defaults.visible;
    final storedSchema = prefs.getInt(schemaVersionKey) ?? 0;
    final migratedVisible =
        storedSchema < schemaVersion && storedVisible != null
        ? <HomeShelfId>{
            ...visible,
            HomeShelfId.popularMovies,
            HomeShelfId.popularShows,
          }
        : visible;
    if (storedSchema < schemaVersion) {
      await prefs.setStringList(
        visibleKey,
        HomeShelfId.values
            .where(migratedVisible.contains)
            .map((shelf) => shelf.key)
            .toList(),
      );
      await prefs.setInt(schemaVersionKey, schemaVersion);
    }
    return HomeShelfPreferences(order: order, visible: migratedVisible);
  }

  HomeShelfPreferences copyWith({
    List<HomeShelfId>? order,
    Set<HomeShelfId>? visible,
  }) => HomeShelfPreferences(
    order: List<HomeShelfId>.unmodifiable(order ?? this.order),
    visible: Set<HomeShelfId>.unmodifiable(visible ?? this.visible),
  );

  Future<void> save(SharedPreferences preferences) async {
    if (!await preferences.setStringList(
          orderKey,
          order.map((shelf) => shelf.key).toList(),
        ) ||
        !await preferences.setStringList(
          visibleKey,
          HomeShelfId.values
              .where(visible.contains)
              .map((shelf) => shelf.key)
              .toList(),
        ) ||
        !await preferences.setInt(schemaVersionKey, schemaVersion)) {
      throw StateError('Home settings could not be saved');
    }
  }

  Map<String, Object> toJson() => <String, Object>{
    'order': order.map((shelf) => shelf.key).toList(),
    'visible': HomeShelfId.values
        .where(visible.contains)
        .map((shelf) => shelf.key)
        .toList(),
  };

  static HomeShelfPreferences fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.length != 2 ||
        !value.keys.toSet().containsAll(const <String>{'order', 'visible'}) ||
        value['order'] is! List<dynamic> ||
        value['visible'] is! List<dynamic>) {
      throw const FormatException('Invalid Home shelf settings.');
    }
    final orderValues = (value['order']! as List<dynamic>);
    final visibleValues = (value['visible']! as List<dynamic>);
    if (orderValues.any((entry) => entry is! String) ||
        visibleValues.any((entry) => entry is! String)) {
      throw const FormatException('Invalid Home shelf settings.');
    }
    if (!_containsOnlyUniqueShelfIds(orderValues.cast<String>()) ||
        !_containsOnlyUniqueShelfIds(visibleValues.cast<String>())) {
      throw const FormatException('Invalid Home shelf settings.');
    }
    final order = _readOrder(orderValues.cast<String>());
    final visible = _readVisible(visibleValues.cast<String>());
    if (order == null || visible == null) {
      throw const FormatException('Invalid Home shelf settings.');
    }
    return HomeShelfPreferences(order: order, visible: visible);
  }

  static List<HomeShelfId>? _readOrder(List<String>? values) {
    if (values == null) return null;
    final byKey = <String, HomeShelfId>{
      for (final shelf in HomeShelfId.values) shelf.key: shelf,
    };
    final parsed = <HomeShelfId>[];
    for (final value in values) {
      final shelf = byKey[value];
      if (shelf == null || parsed.contains(shelf)) return null;
      parsed.add(shelf);
    }
    for (final shelf in HomeShelfId.values) {
      if (!parsed.contains(shelf)) parsed.add(shelf);
    }
    return List<HomeShelfId>.unmodifiable(parsed);
  }

  static Set<HomeShelfId>? _readVisible(List<String>? values) {
    if (values == null) return null;
    final byKey = <String, HomeShelfId>{
      for (final shelf in HomeShelfId.values) shelf.key: shelf,
    };
    return Set<HomeShelfId>.unmodifiable(<HomeShelfId>{
      ...values.map((key) => byKey[key]).whereType<HomeShelfId>(),
    });
  }

  static bool _containsOnlyUniqueShelfIds(List<String> values) {
    final known = HomeShelfId.values.map((shelf) => shelf.key).toSet();
    return values.every(known.contains) &&
        values.toSet().length == values.length;
  }
}
