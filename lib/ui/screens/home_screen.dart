import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/home_shelf_preferences.dart';
import 'package:rodplayer/core/home_library_views.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/screens/playback_callbacks.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/routed_jellyfin_image.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

typedef PlayItemCallback = FutureOr<void> Function(
    BuildContext context, String itemId);

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {required this.client,
      this.onPlayItem,
      this.onResumeItem,
      this.onUserDataChanged,
      this.libraries = const <JellyfinLibraryItem>[],
      this.onOpenLibrary,
      this.latestUserDataChange,
      this.homeShelfPreferences = HomeShelfPreferences.defaults,
      this.userDataRevision = 0,
      this.serverDataRevision,
      super.key});
  final JellyfinApiClient client;
  final PlayItemCallback? onPlayItem;
  final ResumeItemCallback? onResumeItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final List<JellyfinLibraryItem> libraries;
  final ValueChanged<JellyfinLibraryItem>? onOpenLibrary;
  final JellyfinUserDataChange? latestUserDataChange;
  final HomeShelfPreferences homeShelfPreferences;
  final int userDataRevision;
  final ValueListenable<int>? serverDataRevision;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Load<ResumableItem> _resume = const _Load.loading();
  _Load<NextUpItem> _nextUp = const _Load.loading();
  int _clientRevision = 0;
  int _resumeRevision = 0;
  int _nextUpRevision = 0;
  final Map<HomeLibraryShelf, _Load<JellyfinLibraryItem>> _priorityShelves = {
    for (final shelf in HomeLibraryShelf.values) shelf: const _Load.loading(),
  };
  final Map<HomeLibraryShelf, int> _priorityRevisions = {
    for (final shelf in HomeLibraryShelf.values) shelf: 0,
  };
  final Map<String, _Load<JellyfinLibraryItem>> _additionalShelves =
      <String, _Load<JellyfinLibraryItem>>{};
  final Map<String, int> _additionalRevisions = <String, int>{};

  @override
  void initState() {
    super.initState();
    widget.serverDataRevision?.addListener(_onServerDataInvalidated);
    _reloadAll();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionSourceChanged =
        oldWidget.serverDataRevision != widget.serverDataRevision;
    if (revisionSourceChanged) {
      oldWidget.serverDataRevision?.removeListener(_onServerDataInvalidated);
      widget.serverDataRevision?.addListener(_onServerDataInvalidated);
    }
    if (oldWidget.client != widget.client || revisionSourceChanged) {
      _clientRevision++;
      _reloadAll();
    } else if (!_sameViews(oldWidget.libraries, widget.libraries)) {
      _reloadPriorityShelves();
    } else if (oldWidget.userDataRevision != widget.userDataRevision) {
      _applyUserDataChange(widget.latestUserDataChange);
    }
  }

  @override
  void dispose() {
    widget.serverDataRevision?.removeListener(_onServerDataInvalidated);
    super.dispose();
  }

  void _onServerDataInvalidated() {
    if (mounted) _reloadAll();
  }

  void _reloadAll() {
    _reloadResume();
    _reloadNextUp();
    _reloadPriorityShelves();
  }

  void _reloadResume() {
    final requestRevision = ++_resumeRevision;
    _load((items) => _resume = items, () => widget.client.getResumeItems(),
        () => requestRevision == _resumeRevision);
  }

  void _reloadNextUp() {
    final requestRevision = ++_nextUpRevision;
    _load((items) => _nextUp = items, () => widget.client.getNextUp(),
        () => requestRevision == _nextUpRevision);
  }

  void _reloadPriorityShelves() {
    final views = preferredHomeLibraryViews(widget.libraries);
    for (final shelf in HomeLibraryShelf.values) {
      _reloadPriorityShelf(shelf, views[shelf]);
    }
    _reloadAdditionalShelves();
  }

  void _reloadAdditionalShelves() {
    final preferredIds = preferredHomeLibraryViews(widget.libraries)
        .values
        .map((view) => view.id)
        .toSet();
    final views = additionalLibraryViews(widget.libraries)
        .where((view) =>
            !preferredIds.contains(view.id) &&
            const <String>{'movies', 'tvshows'}
                .contains('${view.raw['CollectionType'] ?? ''}'.toLowerCase()))
        .toList(growable: false);
    final ids = views.map((view) => view.id).toSet();
    for (final removed in _additionalShelves.keys.toList()) {
      if (!ids.contains(removed)) {
        _additionalShelves.remove(removed);
        _additionalRevisions[removed] =
            (_additionalRevisions[removed] ?? 0) + 1;
      }
    }
    for (final view in views) {
      _reloadAdditionalShelf(view);
    }
  }

  void _reloadAdditionalShelf(JellyfinLibraryItem view) {
    final revision = (_additionalRevisions[view.id] ?? 0) + 1;
    _additionalRevisions[view.id] = revision;
    setState(() => _additionalShelves[view.id] = const _Load.loading());
    final collectionType = '${view.raw['CollectionType']}'.toLowerCase();
    _load(
      (items) => _additionalShelves[view.id] = items,
      () => widget.client.getLatestItemsForView(
        parentId: view.id,
        collectionType: collectionType,
        limit: 60,
      ),
      () => revision == _additionalRevisions[view.id],
      onError: (error) => _logLibraryShelfFailure(view, error),
    );
  }

  void _logLibraryShelfFailure(JellyfinLibraryItem view, Object error) {
    if (!kDebugMode) return;
    final status = error is ServerConnectionException
        ? '${error.statusCode ?? 'unknown'}'
        : 'not-available';
    debugPrint('Home library shelf request failed: view=${view.id} '
        'status=$status errorType=${error.runtimeType}');
  }

  void _reloadPriorityShelf(HomeLibraryShelf shelf, JellyfinLibraryItem? view) {
    final revision = (_priorityRevisions[shelf] ?? 0) + 1;
    _priorityRevisions[shelf] = revision;
    if (view == null) {
      setState(() =>
          _priorityShelves[shelf] = const _Load.data(<JellyfinLibraryItem>[]));
      return;
    }
    setState(() => _priorityShelves[shelf] = const _Load.loading());
    _load(
      (items) => _priorityShelves[shelf] = items,
      () => widget.client.getLatestItemsForView(
        parentId: view.id,
        collectionType: shelf.collectionType,
        limit: 60,
      ),
      () => revision == _priorityRevisions[shelf],
      onError: (error) => _logPriorityShelfFailure(shelf, view.id, error),
    );
  }

  void _logPriorityShelfFailure(
      HomeLibraryShelf shelf, String parentId, Object error) {
    if (!kDebugMode) return;
    final status = error is ServerConnectionException
        ? '${error.statusCode ?? 'unknown'}'
        : 'not-available';
    final shape = error is ServerConnectionException
        ? error.responseShape ?? 'not-reported'
        : 'not-applicable';
    debugPrint('Home shelf request failed: view=${shelf.viewName} '
        'ParentId=$parentId endpoint=Users/{userId}/Items/Latest '
        'status=$status responseShape=$shape errorType=${error.runtimeType}');
  }

  Future<void> _load<T extends JellyfinLibraryItem>(
      void Function(_Load<T>) assign,
      Future<List<T>> Function() request,
      bool Function() isCurrentRequest,
      {void Function(Object error)? onError}) async {
    final revision = _clientRevision;
    setState(() => assign(const _Load.loading()));
    try {
      final items = await request();
      if (mounted && revision == _clientRevision && isCurrentRequest()) {
        setState(() => assign(_Load.data(items)));
      }
    } catch (error) {
      onError?.call(error);
      if (mounted && revision == _clientRevision && isCurrentRequest()) {
        setState(() => assign(_Load.error(error)));
      }
    }
  }

  Future<void> _play(String itemId) async {
    final callback = widget.onPlayItem;
    if (callback != null) return callback(context, itemId);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerRoute(
        client: widget.client,
        itemId: itemId,
        onUserDataChanged: widget.onUserDataChanged,
      ),
    ));
    if (!mounted) return;
    final change = JellyfinUserDataChange(
      itemId: itemId,
      playbackProgressMayHaveChanged: true,
    );
    final onUserDataChanged = widget.onUserDataChanged;
    if (onUserDataChanged != null) {
      onUserDataChanged(change);
    } else {
      _reloadResume();
      _reloadNextUp();
    }
  }

  void _applyUserDataChange(JellyfinUserDataChange? change) {
    if (change == null) return;
    if (change.played != null || change.playbackProgressMayHaveChanged) {
      _reloadResume();
      _reloadNextUp();
      return;
    }
    if (change.isFavorite != null) {
      setState(() {
        _resume = _resume.map(
            (item) => ResumableItem.fromItem(item.withUserDataChange(change)));
        _nextUp = _nextUp.map(
            (item) => NextUpItem.fromItem(item.withUserDataChange(change)));
        for (final shelf in _priorityShelves.keys) {
          _priorityShelves[shelf] = _priorityShelves[shelf]!
              .map((item) => item.withUserDataChange(change));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hero = _heroItem;
    final loaded = !_resume.loading &&
        !_nextUp.loading &&
        _priorityShelves.values.every((state) => !state.loading) &&
        _additionalShelves.values.every((state) => !state.loading);
    final movies = _priorityShelves[HomeLibraryShelf.newMovieReleases] ??
        const _Load<JellyfinLibraryItem>.data(<JellyfinLibraryItem>[]);
    final episodes = _priorityShelves[HomeLibraryShelf.newEpisodes] ??
        const _Load<JellyfinLibraryItem>.data(<JellyfinLibraryItem>[]);
    final popularMovies = _priorityShelves[HomeLibraryShelf.popularMovies] ??
        const _Load<JellyfinLibraryItem>.data(<JellyfinLibraryItem>[]);
    final popularShows = _priorityShelves[HomeLibraryShelf.popularShows] ??
        const _Load<JellyfinLibraryItem>.data(<JellyfinLibraryItem>[]);
    final anyContent = _resume.items.isNotEmpty ||
        _nextUp.items.isNotEmpty ||
        _priorityShelves.values.any((state) => state.items.isNotEmpty) ||
        _additionalShelves.values.any((state) => state.items.isNotEmpty);
    final shelfWidgets = <HomeShelfId, Widget>{
      HomeShelfId.continueWatching: _shelf<ResumableItem>(
          'Continue Watching', _resume, 16 / 9, _resumeSubtitle, _reloadResume,
          progress: _visualProgress, resumeOnTap: true),
      HomeShelfId.nextUp: _shelf<NextUpItem>(
          'Next Up', _nextUp, 16 / 9, _episodeSubtitle, _reloadNextUp),
      HomeShelfId.latestMovies: _shelf<JellyfinLibraryItem>(
          'New Movie Releases',
          movies,
          2 / 3,
          (item) => item.productionYear?.toString() ?? 'Movie',
          () => _retryPriorityShelf(HomeLibraryShelf.newMovieReleases),
          terminalLibrary: HomeLibraryShelf.newMovieReleases),
      HomeShelfId.latestShows: _shelf<JellyfinLibraryItem>(
          'New Episodes',
          episodes,
          2 / 3,
          (item) => item.productionYear?.toString() ?? 'Series',
          () => _retryPriorityShelf(HomeLibraryShelf.newEpisodes),
          terminalLibrary: HomeLibraryShelf.newEpisodes),
      HomeShelfId.popularMovies: _shelf<JellyfinLibraryItem>(
          'Popular Movies',
          popularMovies,
          2 / 3,
          (item) => item.productionYear?.toString() ?? 'Movie',
          () => _retryPriorityShelf(HomeLibraryShelf.popularMovies),
          terminalLibrary: HomeLibraryShelf.popularMovies),
      HomeShelfId.popularShows: _shelf<JellyfinLibraryItem>(
          'Popular Shows',
          popularShows,
          2 / 3,
          (item) => item.productionYear?.toString() ?? 'Series',
          () => _retryPriorityShelf(HomeLibraryShelf.popularShows),
          terminalLibrary: HomeLibraryShelf.popularShows),
    };
    return CustomScrollView(
      key: const PageStorageKey<String>('home-scroll'),
      slivers: [
        if (hero != null)
          SliverToBoxAdapter(
            child: _HomeHero(
              item: hero,
              client: widget.client,
              onPlay: () => _playFeatured(hero),
              onInfo: () => _openDetails(hero),
            ),
          ),
        if (loaded && !anyContent)
          const SliverFillRemaining(hasScrollBody: false, child: _HomeEmpty()),
        for (final shelf in widget.homeShelfPreferences.order)
          if (widget.homeShelfPreferences.visible.contains(shelf))
            shelfWidgets[shelf]!,
        for (final view in additionalLibraryViews(widget.libraries))
          if (_additionalShelves.containsKey(view.id))
            _libraryShelf(view, _additionalShelves[view.id]!),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  JellyfinLibraryItem? get _heroItem {
    for (final item in _resume.items) {
      if (_playable(item)) return item;
    }
    for (final item in _nextUp.items) {
      if (_playable(item)) return item;
    }
    for (final item
        in (_priorityShelves[HomeLibraryShelf.newMovieReleases]?.items ??
            const <JellyfinLibraryItem>[])) {
      if (_playable(item)) return item;
    }
    return null;
  }

  Widget _shelf<T extends JellyfinLibraryItem>(String title, _Load<T> state,
      double aspectRatio, String Function(T) subtitle, VoidCallback onRetry,
      {double? Function(T)? progress,
      HomeLibraryShelf? terminalLibrary,
      JellyfinLibraryItem? terminalView,
      bool resumeOnTap = false}) {
    if (state.loading) {
      return SliverToBoxAdapter(child: _ShelfLoading(title: title));
    }
    if (state.error != null) {
      return SliverToBoxAdapter(
          child: _ShelfError(title: title, onRetry: onRetry));
    }
    if (state.items.isEmpty &&
        terminalLibrary == null &&
        terminalView == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: SmartShelf(
        title: title,
        itemCount: state.items.length,
        aspectRatio: aspectRatio,
        autofocusFirstItem: title == 'Continue Watching',
        itemBuilder: (context, index, focusNode, {required autofocus}) {
          final item = state.items[index];
          return FocusableMediaCard(
            title: _title(item),
            subtitle: subtitle(item),
            imageUrl: item.imageUrl(widget.client.baseUrl),
            imageClient: widget.client,
            progress: progress?.call(item),
            aspectRatio: aspectRatio,
            badge: userDataBadgeFor(item),
            focusNode: focusNode,
            autofocus: autofocus,
            onTap: () =>
                resumeOnTap ? _resumeItem(context, item) : _openDetails(item),
          );
        },
        terminalItemBuilder: terminalLibrary == null && terminalView == null
            ? null
            : (context, focusNode) => _showMoreCard(
                  focusNode: focusNode,
                  onTap: () {
                    final view = terminalView ??
                        preferredHomeLibraryViews(
                            widget.libraries)[terminalLibrary];
                    if (view != null) widget.onOpenLibrary?.call(view);
                  },
                ),
      ),
    );
  }

  Widget _libraryShelf(
      JellyfinLibraryItem view, _Load<JellyfinLibraryItem> state) {
    final collectionType = '${view.raw['CollectionType']}'.toLowerCase();
    return _shelf<JellyfinLibraryItem>(
      view.title,
      state,
      2 / 3,
      (item) =>
          item.productionYear?.toString() ??
          (collectionType == 'tvshows' ? 'Series' : 'Movie'),
      () => _reloadAdditionalShelf(view),
      terminalView: view,
    );
  }

  Widget _showMoreCard(
          {required FocusNode focusNode, required VoidCallback onTap}) =>
      Builder(builder: (context) {
        final theme = Theme.of(context).extension<RodPlayerTheme>() ??
            const RodPlayerTheme();
        return Material(
          color: theme.obsidianRaised,
          borderRadius: BorderRadius.circular(theme.radiusMedium),
          child: InkWell(
            focusNode: focusNode,
            onTap: onTap,
            borderRadius: BorderRadius.circular(theme.radiusMedium),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_forward, color: theme.textSecondary),
                  const SizedBox(height: 8),
                  Text('Show more', style: TextStyle(color: theme.textPrimary)),
                ],
              ),
            ),
          ),
        );
      });

  void _retryPriorityShelf(HomeLibraryShelf shelf) {
    _reloadPriorityShelf(
        shelf, preferredHomeLibraryViews(widget.libraries)[shelf]);
  }

  Future<void> _playFeatured(JellyfinLibraryItem item) =>
      hasMeaningfulResumeProgress(item)
          ? _resumeItem(context, item)
          : _play(item.id);

  Future<void> _resumeItem(
      BuildContext context, JellyfinLibraryItem item) async {
    final position = item.playbackPosition ?? Duration.zero;
    final callback = widget.onResumeItem;
    if (callback != null) {
      await callback(context, item.id, position);
      return;
    }
    if (widget.onPlayItem != null && position <= Duration.zero) {
      await widget.onPlayItem!(context, item.id);
      return;
    }
    if (item.id.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerRoute(
        client: widget.client,
        itemId: item.id,
        startPosition: position,
        onUserDataChanged: widget.onUserDataChanged,
      ),
    ));
    if (!mounted) return;
    widget.onUserDataChanged?.call(JellyfinUserDataChange(
        itemId: item.id, playbackProgressMayHaveChanged: true));
    _reloadResume();
    _reloadNextUp();
  }

  void _openDetails(JellyfinLibraryItem item) {
    if (item.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ItemDetailsScreen(
            client: widget.client,
            itemId: item.id,
            onPlayItem: widget.onPlayItem,
            onResumeItem: widget.onResumeItem,
            onUserDataChanged: widget.onUserDataChanged,
            serverDataRevision: widget.serverDataRevision)));
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.item,
    required this.client,
    required this.onPlay,
    required this.onInfo,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final VoidCallback? onPlay;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final media = MediaQuery.of(context);
    final size = media.size;
    final compact =
        size.width < 650 && media.navigationMode != NavigationMode.directional;
    final targetHeight = size.height * (compact ? .5 : .64);
    final minHeight = (size.height * (compact ? .45 : .58))
        .clamp(180.0, compact ? 360.0 : 430.0);
    final maxHeight = (size.height * (compact ? .55 : .72))
        .clamp(200.0, compact ? 480.0 : 700.0);
    final height = targetHeight.clamp(minHeight, maxHeight).toDouble();
    final imageUrl = item.imageUrl(client.baseUrl,
            type: JellyfinImageType.backdrop, quality: 85) ??
        item.imageUrl(client.baseUrl, quality: 85);

    return SizedBox(
      key: const ValueKey<String>('home-cinematic-media-bar'),
      width: double.infinity,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            RoutedJellyfinImage(
              client: client,
              url: imageUrl,
              fit: BoxFit.cover,
              fallback: const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0, .36, .7, 1],
                colors: [
                  theme.artworkScrim.withValues(alpha: .94),
                  theme.artworkScrim.withValues(alpha: .72),
                  theme.artworkScrim.withValues(alpha: .22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .34, 1],
                colors: [
                  theme.artworkScrim.withValues(alpha: .32),
                  Colors.transparent,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .48, .82, 1],
                colors: [
                  Colors.transparent,
                  theme.artworkScrim.withValues(alpha: .12),
                  theme.artworkScrim.withValues(alpha: .8),
                  theme.artworkScrim,
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 22 : 48,
              compact ? 22 : 40,
              compact ? 22 : 48,
              compact ? 24 : 40,
            ),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 560 : 780),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title(item),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: theme.artworkTextPrimary,
                            fontSize: compact ? 28 : 48,
                            height: 1.05,
                          ),
                    ),
                    SizedBox(height: compact ? 6 : 10),
                    Text(
                      _heroSubtitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.artworkTextSecondary,
                        fontSize: compact ? 12 : 14,
                        letterSpacing: .2,
                      ),
                    ),
                    if (item.overview != null) ...[
                      SizedBox(height: compact ? 8 : 14),
                      Text(
                        item.overview!,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.artworkTextPrimary,
                          fontSize: compact ? 13 : 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                    SizedBox(height: compact ? 14 : 22),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: onPlay,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            hasMeaningfulResumeProgress(item)
                                ? 'Resume'
                                : 'Play',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.textPrimary,
                            foregroundColor: theme.obsidian,
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 20 : 24,
                              vertical: compact ? 12 : 15,
                            ),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey<String>(
                            'home-cinematic-info-button',
                          ),
                          onPressed: onInfo,
                          icon: const Icon(Icons.info_outline_rounded),
                          label: const Text('Info'),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: theme.obsidianGlassStrong,
                            foregroundColor: theme.textPrimary,
                            side: BorderSide(color: theme.borderColor(.22)),
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 18 : 22,
                              vertical: compact ? 12 : 15,
                            ),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShelfLoading extends StatelessWidget {
  const _ShelfLoading({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Row(children: [
        Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
      ]));
}

class _ShelfError extends StatelessWidget {
  const _ShelfError({required this.title, required this.onRetry});
  final String title;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Row(children: [
        Expanded(
            child: Text('$title unavailable',
                style: TextStyle(
                    color: (Theme.of(context).extension<RodPlayerTheme>() ??
                            const RodPlayerTheme())
                        .textSecondary))),
        TextButton(onPressed: onRetry, child: const Text('Retry'))
      ]));
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();
  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.movie_filter_outlined, size: 54, color: theme.textMuted),
      const SizedBox(height: 14),
      Text('No home content yet', style: Theme.of(context).textTheme.titleLarge)
    ]));
  }
}

class _Load<T extends JellyfinLibraryItem> {
  const _Load.loading()
      : items = const [],
        error = null,
        loading = true;
  const _Load.data(this.items)
      : error = null,
        loading = false;
  const _Load.error(this.error)
      : items = const [],
        loading = false;
  final List<T> items;
  final Object? error;
  final bool loading;

  _Load<T> map(JellyfinLibraryItem Function(T) update) {
    if (loading) return const _Load.loading();
    if (error != null) return _Load.error(error);
    return _Load.data(
        items.map((item) => update(item) as T).toList(growable: false));
  }
}

String _title(JellyfinLibraryItem item) => mediaItemTitle(item);
bool _sameViews(List<JellyfinLibraryItem> a, List<JellyfinLibraryItem> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index].id != b[index].id || a[index].title != b[index].title) {
      return false;
    }
  }
  return true;
}

bool _playable(JellyfinLibraryItem item) => isDirectlyPlayable(item);
String _resumeSubtitle(ResumableItem item) =>
    item.productionYear?.toString() ?? item.rawType ?? 'Resume';
String _episodeSubtitle(NextUpItem item) {
  final code = episodeCode(item).ifEmpty('');
  return [item.seriesName, code]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' · ')
      .ifEmpty(item.rawType ?? 'Episode');
}

String _heroSubtitle(JellyfinLibraryItem item) => [
      item.seriesName,
      item.productionYear?.toString(),
      item.officialRating,
      item.communityRating == null ? null : '★ ${item.communityRating}'
    ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
double? _visualProgress(JellyfinLibraryItem item) => visualProgress(item);

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
