import 'package:rodplayer/core/models/jellyfin_library_item.dart';

enum HomeLibraryShelf {
  newMovieReleases('New Movie Releases', 'movies'),
  newEpisodes('New Episodes', 'tvshows'),
  popularMovies('Popular Movies', 'movies'),
  popularShows('Popular Shows', 'tvshows');

  const HomeLibraryShelf(this.viewName, this.collectionType);

  final String viewName;
  final String collectionType;

  String get key => name;

  static HomeLibraryShelf? fromKey(String value) {
    for (final shelf in values) {
      if (shelf.key == value) return shelf;
    }
    return null;
  }
}

const sidebarPreferredLibraryOrder = <HomeLibraryShelf>[
  HomeLibraryShelf.popularShows,
  HomeLibraryShelf.popularMovies,
  HomeLibraryShelf.newMovieReleases,
  HomeLibraryShelf.newEpisodes,
];

List<JellyfinLibraryItem> supportedLibraryViews(
  Iterable<JellyfinLibraryItem> views,
) =>
    views.where((view) {
      final type = _collectionType(view);
      return view.id.trim().isNotEmpty &&
          const <String>{'movies', 'tvshows', 'boxsets'}.contains(type);
    }).toList(growable: false);

Map<HomeLibraryShelf, JellyfinLibraryItem> preferredHomeLibraryViews(
  Iterable<JellyfinLibraryItem> views,
) {
  final supported = supportedLibraryViews(views);
  final result = <HomeLibraryShelf, JellyfinLibraryItem>{};
  for (final shelf in HomeLibraryShelf.values) {
    final match = supported.where((view) {
      return _collectionType(view) == shelf.collectionType &&
          _normalizedName(view.title) == _normalizedName(shelf.viewName);
    });
    if (match.isNotEmpty) result[shelf] = match.first;
  }
  return Map<HomeLibraryShelf, JellyfinLibraryItem>.unmodifiable(result);
}

List<JellyfinLibraryItem> orderedLibraryViews(
  Iterable<JellyfinLibraryItem> views, {
  bool showAll = false,
}) {
  final supported = supportedLibraryViews(views);
  final preferred = preferredHomeLibraryViews(supported);
  final pinned = <JellyfinLibraryItem>[
    for (final role in sidebarPreferredLibraryOrder)
      if (preferred[role] case final view?) view,
  ];
  final pinnedIds = pinned.map((view) => view.id).toSet();
  final remaining = supported
      .where((view) => !pinnedIds.contains(view.id))
      .toList(growable: false);
  return List<JellyfinLibraryItem>.unmodifiable(
    showAll ? <JellyfinLibraryItem>[...pinned, ...remaining] : pinned,
  );
}

List<JellyfinLibraryItem> additionalLibraryViews(
  Iterable<JellyfinLibraryItem> views,
) {
  final all = orderedLibraryViews(views, showAll: true);
  final pinnedIds = orderedLibraryViews(views).map((view) => view.id).toSet();
  return List<JellyfinLibraryItem>.unmodifiable(
      all.where((view) => !pinnedIds.contains(view.id)));
}

String _collectionType(JellyfinLibraryItem view) =>
    '${view.raw['CollectionType'] ?? ''}'.trim().toLowerCase();

String _normalizedName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
