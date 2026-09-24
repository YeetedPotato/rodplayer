import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/routed_jellyfin_image.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

typedef PlayItemCallback = void Function(BuildContext context, String itemId);

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.client, this.onPlayItem, this.onUserDataChanged, this.latestUserDataChange, this.userDataRevision = 0, super.key});
  final JellyfinApiClient client;
  final PlayItemCallback? onPlayItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final JellyfinUserDataChange? latestUserDataChange;
  final int userDataRevision;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Load<ResumableItem> _resume = const _Load.loading();
  _Load<NextUpItem> _nextUp = const _Load.loading();
  _Load<JellyfinLibraryItem> _movies = const _Load.loading();
  _Load<JellyfinLibraryItem> _shows = const _Load.loading();
  int _clientRevision = 0;
  int _resumeRevision = 0;
  int _nextUpRevision = 0;
  int _moviesRevision = 0;
  int _showsRevision = 0;

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _clientRevision++;
      _reloadAll();
    } else if (oldWidget.userDataRevision != widget.userDataRevision) {
      _applyUserDataChange(widget.latestUserDataChange);
    }
  }

  void _reloadAll() {
    _reloadResume();
    _reloadNextUp();
    _reloadMovies();
    _reloadShows();
  }

  void _reloadResume() {
    final requestRevision = ++_resumeRevision;
    _load((items) => _resume = items, () => widget.client.getResumeItems(), () => requestRevision == _resumeRevision);
  }

  void _reloadNextUp() {
    final requestRevision = ++_nextUpRevision;
    _load((items) => _nextUp = items, () => widget.client.getNextUp(), () => requestRevision == _nextUpRevision);
  }

  void _reloadMovies() {
    final requestRevision = ++_moviesRevision;
    _load((items) => _movies = items, () => widget.client.getLatestMovies(limit: 12), () => requestRevision == _moviesRevision);
  }

  void _reloadShows() {
    final requestRevision = ++_showsRevision;
    _load((items) => _shows = items, () => widget.client.getLatestTvShows(limit: 12), () => requestRevision == _showsRevision);
  }

  Future<void> _load<T extends JellyfinLibraryItem>(void Function(_Load<T>) assign, Future<List<T>> Function() request, bool Function() isCurrentRequest) async {
    final revision = _clientRevision;
    setState(() => assign(const _Load.loading()));
    try {
      final items = await request();
      if (mounted && revision == _clientRevision && isCurrentRequest()) setState(() => assign(_Load.data(items)));
    } catch (error) {
      if (mounted && revision == _clientRevision && isCurrentRequest()) setState(() => assign(_Load.error(error)));
    }
  }

  Future<void> _play(String itemId) async {
    final callback = widget.onPlayItem;
    if (callback != null) return callback(context, itemId);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerRoute(client: widget.client, itemId: itemId)));
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
        _resume = _resume.map((item) => ResumableItem.fromItem(item.withUserDataChange(change)));
        _nextUp = _nextUp.map((item) => NextUpItem.fromItem(item.withUserDataChange(change)));
        _movies = _movies.map((item) => item.withUserDataChange(change));
        _shows = _shows.map((item) => item.withUserDataChange(change));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hero = _heroItem;
    final loaded = !_resume.loading && !_nextUp.loading && !_movies.loading && !_shows.loading;
    final anyContent = _resume.items.isNotEmpty || _nextUp.items.isNotEmpty || _movies.items.isNotEmpty || _shows.items.isNotEmpty;
    return CustomScrollView(
      key: const PageStorageKey<String>('home-scroll'),
      slivers: [
        if (hero != null) SliverToBoxAdapter(child: _HomeHero(item: hero, client: widget.client, onPlay: () => _play(hero.id))),
        _shelf<ResumableItem>('Continue Watching', _resume, 16 / 9, (item) => _resumeSubtitle(item), _reloadResume, progress: _visualProgress),
        _shelf<NextUpItem>('Next Up', _nextUp, 16 / 9, _episodeSubtitle, _reloadNextUp),
        _shelf<JellyfinLibraryItem>('Latest Movies', _movies, 2 / 3, (item) => item.productionYear?.toString() ?? 'Movie', _reloadMovies),
        _shelf<JellyfinLibraryItem>('Latest TV Shows', _shows, 2 / 3, (item) => item.productionYear?.toString() ?? 'Series', _reloadShows),
        if (loaded && !anyContent) const SliverFillRemaining(hasScrollBody: false, child: _HomeEmpty()),
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
    for (final item in _movies.items) {
      if (_playable(item)) return item;
    }
    return null;
  }

  Widget _shelf<T extends JellyfinLibraryItem>(String title, _Load<T> state, double aspectRatio, String Function(T) subtitle, VoidCallback onRetry, {double? Function(T)? progress}) {
    if (state.loading) return SliverToBoxAdapter(child: _ShelfLoading(title: title));
    if (state.error != null) return SliverToBoxAdapter(child: _ShelfError(title: title, onRetry: onRetry));
    if (state.items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: SmartShelf(
        title: title,
        itemCount: state.items.length,
        aspectRatio: aspectRatio,
        autofocusFirstItem: title == 'Continue Watching',
        itemBuilder: (context, index) {
          final item = state.items[index];
          return FocusableMediaCard(
            title: _title(item),
            subtitle: subtitle(item),
            imageUrl: item.imageUrl(widget.client.baseUrl),
            imageClient: widget.client,
            progress: progress?.call(item),
            aspectRatio: aspectRatio,
            badge: userDataBadgeFor(item),
            onTap: () => _openDetails(item),
          );
        },
      ),
    );
  }

  void _openDetails(JellyfinLibraryItem item) {
    if (item.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailsScreen(client: widget.client, itemId: item.id, onPlayItem: widget.onPlayItem, onUserDataChanged: widget.onUserDataChanged)));
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.item, required this.client, required this.onPlay});
  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 650;
    final height = compact ? 290.0 : 380.0;
    final imageUrl = item.imageUrl(client.baseUrl, type: JellyfinImageType.backdrop, quality: 85) ?? item.imageUrl(client.baseUrl, quality: 85);
    return SizedBox(
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        if (imageUrl != null)
          RoutedJellyfinImage(client: client, url: imageUrl, fallback: const SizedBox.shrink()),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.obsidian, theme.obsidian.withValues(alpha: .72), theme.obsidian], begin: Alignment.bottomCenter, end: Alignment.topCenter))),
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 20 : 40, compact ? 28 : 36, compact ? 20 : 48, compact ? 22 : 28),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_title(item), maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: compact ? 28 : 42)),
                      SizedBox(height: compact ? 6 : 8),
                      Text(_heroSubtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary)),
                      if (item.overview != null) ...[SizedBox(height: compact ? 8 : 12), Text(item.overview!, maxLines: compact ? 1 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary))],
                      SizedBox(height: compact ? 12 : 18),
                      FilledButton.icon(onPressed: onPlay, icon: const Icon(Icons.play_arrow), label: Text(hasMeaningfulResumeProgress(item) ? 'Resume' : 'Play')),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ShelfLoading extends StatelessWidget {
  const _ShelfLoading({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), child: Row(children: [Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))), const SizedBox(width: 12), const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))]));
}

class _ShelfError extends StatelessWidget {
  const _ShelfError({required this.title, required this.onRetry});
  final String title;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 18), child: Row(children: [Expanded(child: Text('$title unavailable', style: const TextStyle(color: Colors.white70))), TextButton(onPressed: onRetry, child: const Text('Retry'))]));
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();
  @override
  Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.movie_filter_outlined, size: 54, color: Colors.white38), SizedBox(height: 14), Text('No home content yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))]));
}

class _Load<T extends JellyfinLibraryItem> {
  const _Load.loading() : items = const [], error = null, loading = true;
  const _Load.data(this.items) : error = null, loading = false;
  const _Load.error(this.error) : items = const [], loading = false;
  final List<T> items;
  final Object? error;
  final bool loading;

  _Load<T> map(JellyfinLibraryItem Function(T) update) {
    if (loading) return const _Load.loading();
    if (error != null) return _Load.error(error);
    return _Load.data(items.map((item) => update(item) as T).toList(growable: false));
  }
}

String _title(JellyfinLibraryItem item) => mediaItemTitle(item);
bool _playable(JellyfinLibraryItem item) => isDirectlyPlayable(item);
String _resumeSubtitle(ResumableItem item) => item.productionYear?.toString() ?? item.rawType ?? 'Resume';
String _episodeSubtitle(NextUpItem item) {
  final code = episodeCode(item).ifEmpty('');
  return [item.seriesName, code].whereType<String>().where((part) => part.isNotEmpty).join(' · ').ifEmpty(item.rawType ?? 'Episode');
}
String _heroSubtitle(JellyfinLibraryItem item) => [item.seriesName, item.productionYear?.toString(), item.officialRating, item.communityRating == null ? null : '★ ${item.communityRating}'].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
double? _visualProgress(JellyfinLibraryItem item) => visualProgress(item);

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
