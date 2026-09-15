import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

typedef PlayItemCallback = void Function(BuildContext context, String itemId);

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.client, this.onPlayItem, super.key});
  final JellyfinApiClient client;
  final PlayItemCallback? onPlayItem;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Load<ResumableItem> _resume = const _Load.loading();
  _Load<NextUpItem> _nextUp = const _Load.loading();
  _Load<JellyfinLibraryItem> _movies = const _Load.loading();
  _Load<JellyfinLibraryItem> _shows = const _Load.loading();

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  void _reloadAll() {
    _reloadResume();
    _reloadNextUp();
    _reloadMovies();
    _reloadShows();
  }

  void _reloadResume() => _load((items) => _resume = items, () => widget.client.getResumeItems());
  void _reloadNextUp() => _load((items) => _nextUp = items, () => widget.client.getNextUp());
  void _reloadMovies() => _load((items) => _movies = items, () => widget.client.getLatestMovies(limit: 12));
  void _reloadShows() => _load((items) => _shows = items, () => widget.client.getLatestTvShows(limit: 12));

  Future<void> _load<T extends JellyfinLibraryItem>(void Function(_Load<T>) assign, Future<List<T>> Function() request) async {
    setState(() => assign(const _Load.loading()));
    try {
      final items = await request();
      if (mounted) setState(() => assign(_Load.data(items)));
    } catch (error) {
      if (mounted) setState(() => assign(_Load.error(error)));
    }
  }

  void _play(String itemId) {
    final callback = widget.onPlayItem;
    if (callback != null) return callback(context, itemId);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerRoute(client: widget.client, itemId: itemId)));
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
        _shelf<JellyfinLibraryItem>('Latest TV Shows', _shows, 2 / 3, (item) => item.productionYear?.toString() ?? 'Series', _reloadShows, playable: false),
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

  Widget _shelf<T extends JellyfinLibraryItem>(String title, _Load<T> state, double aspectRatio, String Function(T) subtitle, VoidCallback onRetry, {double? Function(T)? progress, bool playable = true}) {
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
            progress: progress?.call(item),
            aspectRatio: aspectRatio,
            onTap: () => _showItem(item, playable: playable && _playable(item)),
          );
        },
      ),
    );
  }

  void _showItem(JellyfinLibraryItem item, {required bool playable}) => showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_title(item), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
              if (item.overview != null) ...[const SizedBox(height: 12), Text(item.overview!, maxLines: 4, overflow: TextOverflow.ellipsis)],
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: playable ? () { Navigator.pop(context); _play(item.id); } : null, icon: const Icon(Icons.play_arrow), label: Text(_hasMeaningfulResumeProgress(item) ? 'Resume' : 'Play')),
            ]),
          ),
        ),
      );
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
    final height = size.width < 650 ? 290.0 : 380.0;
    final imageUrl = item.imageUrl(client.baseUrl, type: JellyfinImageType.backdrop, quality: 85) ?? item.imageUrl(client.baseUrl, quality: 85);
    return SizedBox(
      height: height,
      child: Stack(fit: StackFit.expand, children: [
        if (imageUrl != null)
          Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.obsidian, theme.obsidian.withValues(alpha: .72), theme.obsidian], begin: Alignment.bottomCenter, end: Alignment.topCenter))),
        Padding(
          padding: EdgeInsets.fromLTRB(size.width < 650 ? 20 : 40, 36, size.width < 650 ? 20 : 48, 28),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_title(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontSize: size.width < 650 ? 30 : 42)),
                      const SizedBox(height: 8),
                      Text(_heroSubtitle(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textSecondary)),
                      if (item.overview != null) ...[const SizedBox(height: 12), Text(item.overview!, maxLines: size.width < 650 ? 2 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.textPrimary))],
                      const SizedBox(height: 18),
                      FilledButton.icon(onPressed: onPlay, icon: const Icon(Icons.play_arrow), label: Text(_hasMeaningfulResumeProgress(item) ? 'Resume' : 'Play')),
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
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), child: Row(children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const Spacer(), const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))]));
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
}

String _title(JellyfinLibraryItem item) => item.title.isEmpty ? 'Untitled' : item.title;
bool _playable(JellyfinLibraryItem item) => item.id.isNotEmpty && (item.kind == JellyfinItemKind.movie || item.kind == JellyfinItemKind.episode || item.kind == JellyfinItemKind.audio);
String _resumeSubtitle(ResumableItem item) => item.productionYear?.toString() ?? item.rawType ?? 'Resume';
String _episodeSubtitle(NextUpItem item) {
  final season = item.seasonNumber == null ? null : 'S${item.seasonNumber!.toString().padLeft(2, '0')}';
  final episode = item.episodeNumber == null ? null : 'E${item.episodeNumber!.toString().padLeft(2, '0')}';
  final code = season == null && episode == null ? null : '${season ?? ''}${episode ?? ''}';
  return [item.seriesName, code].whereType<String>().where((part) => part.isNotEmpty).join(' · ').ifEmpty(item.rawType ?? 'Episode');
}
String _heroSubtitle(JellyfinLibraryItem item) => [item.seriesName, item.productionYear?.toString(), item.officialRating, item.communityRating == null ? null : '★ ${item.communityRating}'].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
double? _rawProgress(JellyfinLibraryItem item) {
  final percent = item.playedPercentage;
  if (percent != null) return (percent / 100).clamp(0, 1).toDouble();
  final position = item.playbackPositionTicks;
  final runtime = item.runTimeTicks;
  if (position == null || runtime == null || runtime <= 0) return null;
  return (position / runtime).clamp(0, 1).toDouble();
}
double? _visualProgress(JellyfinLibraryItem item) {
  final progress = _rawProgress(item);
  return progress == null || progress <= 0 ? null : progress;
}
bool _hasMeaningfulResumeProgress(JellyfinLibraryItem item) => (_rawProgress(item) ?? 0) > 0;

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
