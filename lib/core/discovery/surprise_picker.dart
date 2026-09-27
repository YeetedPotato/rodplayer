import 'dart:math';

import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';

enum SurpriseMode {
  unwatchedMovies('Unwatched movies'),
  unwatchedShows('Unwatched shows'),
  favorites('Favorite movies and shows');

  const SurpriseMode(this.label);

  final String label;

  List<_SurpriseQuery> get _queries => switch (this) {
        SurpriseMode.unwatchedMovies => const <_SurpriseQuery>[
            _SurpriseQuery(
                JellyfinLibraryKind.movies, JellyfinLibraryFilter.unplayed),
          ],
        SurpriseMode.unwatchedShows => const <_SurpriseQuery>[
            _SurpriseQuery(
                JellyfinLibraryKind.tvShows, JellyfinLibraryFilter.unplayed),
          ],
        SurpriseMode.favorites => const <_SurpriseQuery>[
            _SurpriseQuery(
                JellyfinLibraryKind.movies, JellyfinLibraryFilter.favorites),
            _SurpriseQuery(
                JellyfinLibraryKind.tvShows, JellyfinLibraryFilter.favorites),
          ],
      };
}

class SurpriseSelectionUnavailableException implements Exception {
  const SurpriseSelectionUnavailableException();
}

/// Selects uniformly from all matching library rows using Jellyfin's total
/// count and indexed paging. A missing count is treated as unavailable rather
/// than falling back to a biased first page.
class SurprisePicker {
  SurprisePicker({required this.client, Random? random})
      : _random = random ?? Random();

  static const _maxRandomAttempts = 20;
  static const _exhaustionPageSize = 100;

  final JellyfinApiClient client;
  final Random _random;

  Future<JellyfinLibraryItem?> pick({
    required SurpriseMode mode,
    Set<String> excludedItemIds = const <String>{},
  }) async {
    final queries = mode._queries;
    final pages = await Future.wait(queries.map(
      (query) => _readPage(query, startIndex: 0, limit: 1),
    ));
    if (pages.any((page) => page.totalRecordCount == null)) {
      throw const SurpriseSelectionUnavailableException();
    }

    final counts =
        pages.map((page) => page.totalRecordCount!).toList(growable: false);
    if (counts.any((count) => count < 0)) {
      throw const SurpriseSelectionUnavailableException();
    }
    for (var index = 0; index < counts.length; index++) {
      if (counts[index] == 0 && pages[index].items.isNotEmpty) {
        throw const SurpriseSelectionUnavailableException();
      }
    }

    final total = counts.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) return null;
    if (excludedItemIds.length >= total &&
        await _allCandidatesExcluded(queries, counts, excludedItemIds)) {
      return null;
    }

    for (var attempt = 0; attempt < _maxRandomAttempts; attempt++) {
      var offset = _random.nextInt(total);
      var queryIndex = 0;
      while (offset >= counts[queryIndex]) {
        offset -= counts[queryIndex];
        queryIndex++;
      }

      final page = offset == 0
          ? pages[queryIndex]
          : await _readPage(
              queries[queryIndex],
              startIndex: offset,
              limit: 1,
            );
      if (page.totalRecordCount != counts[queryIndex]) {
        throw const SurpriseSelectionUnavailableException();
      }
      if (page.items.isEmpty) continue;
      final item = page.items.first;
      if (item.id.isNotEmpty && !excludedItemIds.contains(item.id)) return item;
    }

    if (await _allCandidatesExcluded(queries, counts, excludedItemIds)) {
      return null;
    }
    throw const SurpriseSelectionUnavailableException();
  }

  Future<bool> _allCandidatesExcluded(
    List<_SurpriseQuery> queries,
    List<int> counts,
    Set<String> excludedItemIds,
  ) async {
    for (var queryIndex = 0; queryIndex < queries.length; queryIndex++) {
      final count = counts[queryIndex];
      for (var startIndex = 0; startIndex < count;) {
        final limit = min(_exhaustionPageSize, count - startIndex);
        final page = await _readPage(
          queries[queryIndex],
          startIndex: startIndex,
          limit: limit,
        );
        if (page.totalRecordCount != count || page.items.length != limit) {
          throw const SurpriseSelectionUnavailableException();
        }
        for (final item in page.items) {
          if (item.id.isEmpty) {
            throw const SurpriseSelectionUnavailableException();
          }
          if (!excludedItemIds.contains(item.id)) return false;
        }
        startIndex += limit;
      }
    }
    return true;
  }

  Future<JellyfinItemsPage<JellyfinLibraryItem>> _readPage(
    _SurpriseQuery query, {
    required int startIndex,
    required int limit,
  }) =>
      client.getLibraryItemsPage(
        kind: query.kind,
        sort: JellyfinLibrarySort.title,
        filter: query.filter,
        startIndex: startIndex,
        limit: limit,
      );
}

class _SurpriseQuery {
  const _SurpriseQuery(this.kind, this.filter);

  final JellyfinLibraryKind kind;
  final JellyfinLibraryFilter filter;
}
