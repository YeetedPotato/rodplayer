import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/routed_jellyfin_image.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

typedef DetailPlayItemCallback = void Function(BuildContext context, String itemId);

class ItemDetailsScreen extends StatefulWidget {
  const ItemDetailsScreen({
    required this.client,
    required this.itemId,
    this.onPlayItem,
    this.onUserDataChanged,
    super.key,
  });

  final JellyfinApiClient client;
  final String itemId;
  final DetailPlayItemCallback? onPlayItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  JellyfinLibraryItem? _item;
  List<JellyfinLibraryItem> _seasons = const <JellyfinLibraryItem>[];
  List<JellyfinLibraryItem> _episodes = const <JellyfinLibraryItem>[];
  List<JellyfinLibraryItem> _similar = const <JellyfinLibraryItem>[];
  String? _selectedSeasonId;
  Object? _itemError;
  Object? _seasonsError;
  Object? _episodesError;
  Object? _similarError;
  bool _loadingItem = true;
  bool _loadingSeasons = false;
  bool _loadingEpisodes = false;
  bool _loadingSimilar = false;
  bool _favoriteBusy = false;
  bool _playedBusy = false;
  int _generation = 0;
  int _episodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadItem();
  }

  @override
  void didUpdateWidget(covariant ItemDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client || oldWidget.itemId != widget.itemId) _loadItem();
  }

  void _loadItem() {
    final generation = ++_generation;
    _episodeGeneration++;
    setState(() {
      _item = null;
      _seasons = const <JellyfinLibraryItem>[];
      _episodes = const <JellyfinLibraryItem>[];
      _similar = const <JellyfinLibraryItem>[];
      _selectedSeasonId = null;
      _itemError = null;
      _seasonsError = null;
      _episodesError = null;
      _similarError = null;
      _loadingItem = true;
      _loadingSeasons = false;
      _loadingEpisodes = false;
      _loadingSimilar = false;
      _favoriteBusy = false;
      _playedBusy = false;
    });
    unawaited(_loadItemBody(generation));
  }

  Future<void> _loadItemBody(int generation) async {
    try {
      final item = await widget.client.getItem(widget.itemId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _item = item;
        _loadingItem = false;
      });
      if (item.kind == JellyfinItemKind.series && item.id.isNotEmpty) unawaited(_loadSeasons(item.id, generation));
      if (_supportsSimilar(item)) unawaited(_loadSimilar(item.id, generation));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _itemError = error;
          _loadingItem = false;
        });
      }
    }
  }

  Future<void> _loadSeasons(String seriesId, int generation) async {
    setState(() {
      _loadingSeasons = true;
      _seasonsError = null;
    });
    try {
      final seasons = await widget.client.getSeasons(seriesId: seriesId);
      if (!mounted || generation != _generation) return;
      final seen = <String>{};
      JellyfinLibraryItem? firstSeason;
      for (final season in seasons) {
        if (season.id.isNotEmpty && seen.add(season.id)) {
          firstSeason = season;
          break;
        }
      }
      setState(() {
        _seasons = seasons;
        _selectedSeasonId = firstSeason?.id;
        _loadingSeasons = false;
      });
      if (firstSeason != null) unawaited(_loadEpisodes(seriesId: seriesId, seasonId: firstSeason.id));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _seasonsError = error;
          _loadingSeasons = false;
        });
      }
    }
  }

  Future<void> _loadEpisodes({required String seriesId, required String seasonId}) async {
    final episodeGeneration = ++_episodeGeneration;
    setState(() {
      _selectedSeasonId = seasonId;
      _episodes = const <JellyfinLibraryItem>[];
      _episodesError = null;
      _loadingEpisodes = true;
    });
    try {
      final episodes = await widget.client.getEpisodes(seriesId: seriesId, seasonId: seasonId);
      if (!mounted || episodeGeneration != _episodeGeneration) return;
      setState(() {
        _episodes = episodes;
        _loadingEpisodes = false;
      });
    } catch (error) {
      if (mounted && episodeGeneration == _episodeGeneration) {
        setState(() {
          _episodesError = error;
          _loadingEpisodes = false;
        });
      }
    }
  }

  Future<void> _loadSimilar(String itemId, int generation) async {
    setState(() {
      _similarError = null;
      _loadingSimilar = true;
    });
    try {
      final items = await widget.client.getSimilarItems(itemId: itemId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _similar = items;
        _loadingSimilar = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _similarError = error;
          _loadingSimilar = false;
        });
      }
    }
  }

  Future<void> _play(String itemId) async {
    final callback = widget.onPlayItem;
    if (callback != null) return callback(context, itemId);
    final generation = _generation;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerRoute(client: widget.client, itemId: itemId)));
    if (!mounted || generation != _generation) return;
    try {
      final refreshed = await widget.client.getItem(itemId);
      if (!mounted || generation != _generation) return;
      setState(() => _item = refreshed);
      widget.onUserDataChanged?.call(JellyfinUserDataChange(itemId: itemId, played: refreshed.userData.played, playbackProgressMayHaveChanged: true));
    } catch (_) {
      if (mounted && generation == _generation) widget.onUserDataChanged?.call(JellyfinUserDataChange(itemId: itemId, playbackProgressMayHaveChanged: true));
    }
  }

  void _openEpisode(JellyfinLibraryItem item) {
    _openItem(item);
  }

  void _openItem(JellyfinLibraryItem item) {
    if (item.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailsScreen(client: widget.client, itemId: item.id, onPlayItem: widget.onPlayItem, onUserDataChanged: _handleChildUserDataChange)));
  }

  void _handleChildUserDataChange(JellyfinUserDataChange change) {
    if (mounted) {
      setState(() {
        _episodes = _episodes.map((item) => item.withUserDataChange(change)).toList(growable: false);
        _similar = _similar.map((item) => item.withUserDataChange(change)).toList(growable: false);
      });
    }
    widget.onUserDataChanged?.call(change);
  }

  Future<void> _setFavorite(bool value) async {
    final item = _item;
    if (item == null || item.id.isEmpty || _favoriteBusy) return;
    final generation = _generation;
    setState(() => _favoriteBusy = true);
    try {
      await widget.client.setFavorite(itemId: item.id, isFavorite: value);
      if (!mounted || generation != _generation) return;
      final change = JellyfinUserDataChange(itemId: item.id, isFavorite: value);
      setState(() => _item = _item!.withUserDataChange(change));
      widget.onUserDataChanged?.call(change);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value ? 'Added to favorites' : 'Removed from favorites')));
    } catch (_) {
      if (mounted && generation == _generation) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update favorite')));
    } finally {
      if (mounted && generation == _generation) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _setPlayed(bool value) async {
    final item = _item;
    if (item == null || item.id.isEmpty || _playedBusy) return;
    final generation = _generation;
    setState(() => _playedBusy = true);
    try {
      await widget.client.setPlayed(itemId: item.id, played: value);
      if (!mounted || generation != _generation) return;
      final change = JellyfinUserDataChange(itemId: item.id, played: value, playbackProgressMayHaveChanged: true);
      setState(() => _item = _item!.withUserDataChange(change));
      widget.onUserDataChanged?.call(change);
      if (item.kind == JellyfinItemKind.series && _selectedSeasonId != null) unawaited(_loadEpisodes(seriesId: item.id, seasonId: _selectedSeasonId!));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value ? 'Marked watched' : 'Marked unwatched')));
    } catch (_) {
      if (mounted && generation == _generation) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update watched state')));
    } finally {
      if (mounted && generation == _generation) setState(() => _playedBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Scaffold(
      backgroundColor: theme.obsidian,
      body: ColoredBox(
        color: theme.obsidian,
        child: _loadingItem
            ? const Center(child: CircularProgressIndicator())
            : _itemError != null
                ? _Message(icon: Icons.cloud_off_outlined, title: 'Details unavailable', action: TextButton(onPressed: _loadItem, child: const Text('Retry')))
                : _DetailsBody(
                    item: _item!,
                    client: widget.client,
                    seasons: _seasons,
                    episodes: _episodes,
                    selectedSeasonId: _selectedSeasonId,
                    loadingSeasons: _loadingSeasons,
                    loadingEpisodes: _loadingEpisodes,
                    loadingSimilar: _loadingSimilar,
                    seasonsError: _seasonsError,
                    episodesError: _episodesError,
                    similarError: _similarError,
                    similar: _similar,
                    onSeasonChanged: (seasonId) => unawaited(_loadEpisodes(seriesId: _item!.id, seasonId: seasonId)),
                    onRetrySeasons: () => unawaited(_loadSeasons(_item!.id, _generation)),
                    onRetryEpisodes: () {
                      final seasonId = _selectedSeasonId;
                      if (seasonId != null) unawaited(_loadEpisodes(seriesId: _item!.id, seasonId: seasonId));
                    },
                    onRetrySimilar: () => unawaited(_loadSimilar(_item!.id, _generation)),
                    onPlay: isDirectlyPlayable(_item!) ? () => _play(_item!.id) : null,
                    favoriteBusy: _favoriteBusy,
                    playedBusy: _playedBusy,
                    onFavorite: _supportsPersonalActions(_item!) ? () => unawaited(_setFavorite(!_item!.userData.isFavorite)) : null,
                    onPlayed: _supportsPlayedAction(_item!) ? () => unawaited(_setPlayed(!_item!.userData.played)) : null,
                    onEpisodeTap: _openEpisode,
                    onSimilarTap: _openItem,
                  ),
      ),
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({
    required this.item,
    required this.client,
    required this.seasons,
    required this.episodes,
    required this.selectedSeasonId,
    required this.loadingSeasons,
    required this.loadingEpisodes,
    required this.loadingSimilar,
    required this.seasonsError,
    required this.episodesError,
    required this.similarError,
    required this.similar,
    required this.onSeasonChanged,
    required this.onRetrySeasons,
    required this.onRetryEpisodes,
    required this.onRetrySimilar,
    required this.onPlay,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
    required this.onEpisodeTap,
    required this.onSimilarTap,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final List<JellyfinLibraryItem> seasons;
  final List<JellyfinLibraryItem> episodes;
  final String? selectedSeasonId;
  final bool loadingSeasons;
  final bool loadingEpisodes;
  final bool loadingSimilar;
  final Object? seasonsError;
  final Object? episodesError;
  final Object? similarError;
  final List<JellyfinLibraryItem> similar;
  final ValueChanged<String> onSeasonChanged;
  final VoidCallback onRetrySeasons;
  final VoidCallback onRetryEpisodes;
  final VoidCallback onRetrySimilar;
  final VoidCallback? onPlay;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;
  final ValueChanged<JellyfinLibraryItem> onEpisodeTap;
  final ValueChanged<JellyfinLibraryItem> onSimilarTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final topInset = MediaQuery.paddingOf(context).top;
        return CustomScrollView(slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _DetailsHeaderDelegate(
              item: item,
              client: client,
              compact: compact,
              topInset: topInset,
              onPlay: onPlay,
              favoriteBusy: favoriteBusy,
              playedBusy: playedBusy,
              onFavorite: onFavorite,
              onPlayed: onPlayed,
            ),
          ),
          if (compact && (item.studios.isNotEmpty || item.people.isNotEmpty))
            SliverPadding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 24, compact ? 20 : 36, 24),
              sliver: SliverToBoxAdapter(child: _DetailFacts(item: item)),
            ),
          if (item.kind == JellyfinItemKind.series) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 0, compact ? 20 : 36, 16),
              sliver: SliverToBoxAdapter(
                child: _SeriesControls(
                  seasons: seasons,
                  selectedSeasonId: selectedSeasonId,
                  loadingSeasons: loadingSeasons,
                  loadingEpisodes: loadingEpisodes,
                  seasonsError: seasonsError,
                  episodesError: episodesError,
                  onSeasonChanged: onSeasonChanged,
                  onRetrySeasons: onRetrySeasons,
                  onRetryEpisodes: onRetryEpisodes,
                ),
              ),
            ),
            if (!loadingSeasons && seasonsError == null && _selectableSeasons(seasons).isNotEmpty && !loadingEpisodes && episodesError == null && episodes.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 0, compact ? 20 : 36, 36),
                sliver: _EpisodeGrid(client: client, episodes: episodes, onEpisodeTap: onEpisodeTap),
              ),
            if (!loadingSeasons && seasonsError == null && _selectableSeasons(seasons).isNotEmpty && !loadingEpisodes && episodesError == null && episodes.isEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 0, compact ? 20 : 36, 36),
                sliver: const SliverToBoxAdapter(child: _Message(icon: Icons.video_library_outlined, title: 'No episodes found')),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
          if (loadingSimilar || similarError != null || similar.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 0, compact ? 20 : 36, 12),
              sliver: SliverToBoxAdapter(child: Text('More Like This', style: Theme.of(context).textTheme.titleLarge)),
            ),
            if (loadingSimilar)
              const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())))
            else if (similarError != null)
              SliverToBoxAdapter(child: _Message(icon: Icons.explore_off_outlined, title: 'Similar items unavailable', action: TextButton(onPressed: onRetrySimilar, child: const Text('Retry'))))
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 0, compact ? 20 : 36, 36),
                sliver: _SimilarGrid(client: client, items: similar, onTap: onSimilarTap),
              ),
          ],
        ]);
      });
}

class _DetailsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DetailsHeaderDelegate({
    required this.item,
    required this.client,
    required this.compact,
    required this.topInset,
    required this.onPlay,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final bool compact;
  final double topInset;
  final VoidCallback? onPlay;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;

  @override
  double get minExtent => topInset + 64;

  @override
  double get maxExtent => topInset + (compact ? 420 : 440);

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final collapse = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    return _CinematicDetailsHeader(
      item: item,
      client: client,
      compact: compact,
      topInset: topInset,
      collapse: collapse,
      onPlay: onPlay,
      favoriteBusy: favoriteBusy,
      playedBusy: playedBusy,
      onFavorite: onFavorite,
      onPlayed: onPlayed,
    );
  }

  @override
  bool shouldRebuild(covariant _DetailsHeaderDelegate oldDelegate) =>
      item != oldDelegate.item ||
      client != oldDelegate.client ||
      compact != oldDelegate.compact ||
      topInset != oldDelegate.topInset ||
      onPlay != oldDelegate.onPlay ||
      favoriteBusy != oldDelegate.favoriteBusy ||
      playedBusy != oldDelegate.playedBusy ||
      onFavorite != oldDelegate.onFavorite ||
      onPlayed != oldDelegate.onPlayed;
}

class _CinematicDetailsHeader extends StatelessWidget {
  const _CinematicDetailsHeader({
    required this.item,
    required this.client,
    required this.compact,
    required this.topInset,
    required this.collapse,
    required this.onPlay,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final bool compact;
  final double topInset;
  final double collapse;
  final VoidCallback? onPlay;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final backdropUrl = item.imageUrl(client.baseUrl, type: JellyfinImageType.backdrop, quality: 90) ?? item.imageUrl(client.baseUrl, type: JellyfinImageType.primary, quality: 90);
    final expandedOpacity = 1 - ((collapse - .05) / .18).clamp(0.0, 1.0);
    final collapsedOpacity = ((collapse - .23) / .11).clamp(0.0, 1.0);
    final compactControlsActive = collapse >= .23;
    final summaryLeft = (compact ? 22.0 : 40.0) +
        (compact ? 54.0 : 48.0) * (collapse * 2.2).clamp(0.0, 1.0);
    final title = mediaItemTitle(item);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.obsidianGlassStrong),
      child: ClipRect(
        child: Stack(fit: StackFit.expand, children: [
          if (backdropUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 1 - collapse,
                child: RoutedJellyfinImage(
                  client: client,
                  url: backdropUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  fallback: ColoredBox(color: theme.surface3),
                ),
              ),
            )
          else
            Positioned.fill(child: ColoredBox(color: theme.surface3)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: .42),
                    Colors.transparent,
                    theme.artworkScrim.withValues(alpha: .98),
                  ],
                  stops: const <double>[0, .34, 1],
                ),
              ),
            ),
          ),
          if (collapse > 0)
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: collapse * .72)),
            ),
          if (expandedOpacity > 0)
            Positioned(
              left: summaryLeft,
              right: compact ? 22 : 40,
              bottom: compact ? 18 : 28,
              child: Opacity(
                opacity: expandedOpacity,
                child: IgnorePointer(
                  ignoring: compactControlsActive,
                  child: ExcludeFocus(
                    excluding: compactControlsActive,
                    child: ExcludeSemantics(
                      excluding: compactControlsActive,
                      child: _ExpandedDetailSummary(
                        item: item,
                        compact: compact,
                        onPlay: onPlay,
                        favoriteBusy: favoriteBusy,
                        playedBusy: playedBusy,
                        onFavorite: onFavorite,
                        onPlayed: onPlayed,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (collapsedOpacity > 0)
            Positioned(
              left: 0,
              right: 0,
              top: topInset,
              height: 64,
              child: Opacity(
                opacity: collapsedOpacity,
                child: IgnorePointer(
                  ignoring: !compactControlsActive,
                  child: ExcludeFocus(
                    excluding: !compactControlsActive,
                    child: ExcludeSemantics(
                      excluding: !compactControlsActive,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: theme.obsidianGlassStrong),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 76, right: 12),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Color.lerp(Colors.white, theme.textPrimary, collapsedOpacity), fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (onPlay != null) ...[
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: hasMeaningfulResumeProgress(item) ? 'Resume' : 'Play',
                                onPressed: onPlay,
                                icon: const Icon(Icons.play_arrow),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 18,
            top: topInset + 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(Colors.black.withValues(alpha: .46), theme.surface2, collapse),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back, color: Color.lerp(Colors.white, theme.textPrimary, collapse)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ExpandedDetailSummary extends StatelessWidget {
  const _ExpandedDetailSummary({
    required this.item,
    required this.compact,
    required this.onPlay,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
  });

  final JellyfinLibraryItem item;
  final bool compact;
  final VoidCallback? onPlay;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final metadata = _detailMetadata(item);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          mediaItemTitle(item),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: theme.artworkTextPrimary,
                fontSize: compact ? 32 : 44,
                height: 1.02,
                shadows: const <Shadow>[Shadow(color: Colors.black54, blurRadius: 18)],
              ),
        ),
        if (metadata.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: metadata.map((label) => _DetailPill(label: label)).toList()),
        ],
        if (item.genres.isNotEmpty) ...[
          const SizedBox(height: 9),
          Text(item.genres.take(4).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.artworkTextSecondary, fontWeight: FontWeight.w600)),
        ],
        if (item.tagline != null && item.tagline!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(item.tagline!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.artworkTextSecondary, fontStyle: FontStyle.italic)),
        ],
        if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 520 : 780),
            child: Text(item.overview!, maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.artworkTextPrimary, height: 1.35)),
          ),
        ],
        if (!compact && (item.studios.isNotEmpty || item.people.isNotEmpty)) ...[
          const SizedBox(height: 7),
          _DetailFacts(item: item, onArtwork: true),
        ],
        if (onPlay != null || onFavorite != null || onPlayed != null) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (onPlay != null)
              FilledButton.icon(onPressed: onPlay, icon: const Icon(Icons.play_arrow), label: Text(hasMeaningfulResumeProgress(item) ? 'Resume' : 'Play')),
            if (onFavorite != null)
              OutlinedButton.icon(
                onPressed: favoriteBusy ? null : onFavorite,
                icon: Icon(item.userData.isFavorite ? Icons.favorite : Icons.favorite_border),
                label: Text(item.userData.isFavorite ? 'Remove from favorites' : 'Add to favorites'),
              ),
            if (onPlayed != null)
              OutlinedButton.icon(
                onPressed: playedBusy ? null : onPlayed,
                icon: Icon(item.userData.played ? Icons.check_circle : Icons.check_circle_outline),
                label: Text(item.kind == JellyfinItemKind.audio ? (item.userData.played ? 'Mark unplayed' : 'Mark played') : (item.userData.played ? 'Mark unwatched' : 'Mark watched')),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(theme.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(label, style: TextStyle(color: theme.artworkTextPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _DetailFacts extends StatelessWidget {
  const _DetailFacts({required this.item, this.onArtwork = false});
  final JellyfinLibraryItem item;
  final bool onArtwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final cast = item.people.take(5).map((person) => person.name).where((name) => name.isNotEmpty).join(', ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (item.studios.isNotEmpty) _FactLine(label: 'Studios', value: item.studios.take(3).join(', '), theme: theme, onArtwork: onArtwork),
      if (cast.isNotEmpty) _FactLine(label: 'Cast', value: cast, theme: theme, onArtwork: onArtwork),
    ]);
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.label, required this.value, required this.theme, this.onArtwork = false});
  final String label;
  final String value;
  final RodPlayerTheme theme;
  final bool onArtwork;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$label: ', style: TextStyle(color: onArtwork ? theme.artworkTextSecondary : theme.textMuted, fontWeight: FontWeight.w700)),
          TextSpan(text: value, style: TextStyle(color: onArtwork ? theme.artworkTextSecondary : theme.textSecondary)),
        ])),
      );
}

List<String> _detailMetadata(JellyfinLibraryItem item) => <String>[
      if (item.productionYear != null) item.productionYear.toString(),
      if (item.officialRating != null && item.officialRating!.isNotEmpty) item.officialRating!,
      if (item.communityRating != null) 'Rating ${item.communityRating} / 10',
      if (item.runTime != null) _duration(item.runTime!),
      if (item.status != null && item.status!.isNotEmpty) item.status!,
      if (_dateLabel(item.premiereDate) != null) _dateLabel(item.premiereDate)!,
      if (item.kind == JellyfinItemKind.episode && item.seriesName != null) item.seriesName!,
      if (item.kind == JellyfinItemKind.episode && item.seasonName != null) item.seasonName!,
      if (item.kind == JellyfinItemKind.episode && episodeCode(item).isNotEmpty) episodeCode(item),
    ];

class _SeriesControls extends StatelessWidget {
  const _SeriesControls({
    required this.seasons,
    required this.selectedSeasonId,
    required this.loadingSeasons,
    required this.loadingEpisodes,
    required this.seasonsError,
    required this.episodesError,
    required this.onSeasonChanged,
    required this.onRetrySeasons,
    required this.onRetryEpisodes,
  });

  final List<JellyfinLibraryItem> seasons;
  final String? selectedSeasonId;
  final bool loadingSeasons;
  final bool loadingEpisodes;
  final Object? seasonsError;
  final Object? episodesError;
  final ValueChanged<String> onSeasonChanged;
  final VoidCallback onRetrySeasons;
  final VoidCallback onRetryEpisodes;

  @override
  Widget build(BuildContext context) {
    if (loadingSeasons) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    if (seasonsError != null) return _Message(icon: Icons.cloud_off_outlined, title: 'Seasons unavailable', action: TextButton(onPressed: onRetrySeasons, child: const Text('Retry')));
    if (seasons.isEmpty) return const _Message(icon: Icons.tv_outlined, title: 'No seasons found');
    final selectableSeasons = _selectableSeasons(seasons);
    if (selectableSeasons.isEmpty) return const _Message(icon: Icons.tv_outlined, title: 'No selectable seasons found');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Episodes', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(width: 12),
        Flexible(
          child: DropdownButton<String>(
            value: selectedSeasonId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: selectableSeasons.map((season) => DropdownMenuItem<String>(value: season.id, child: Text(_seasonTitle(season), maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (value) {
              if (value != null) onSeasonChanged(value);
            },
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (loadingEpisodes)
        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (episodesError != null)
        _Message(icon: Icons.cloud_off_outlined, title: 'Episodes unavailable', action: TextButton(onPressed: onRetryEpisodes, child: const Text('Retry')))
    ]);
  }

  String _seasonTitle(JellyfinLibraryItem season) {
    if (season.seasonName != null && season.seasonName!.trim().isNotEmpty) return season.seasonName!;
    if (season.title.isNotEmpty) return season.title;
    if (season.seasonNumber == 0) return 'Specials';
    return season.seasonNumber == null ? 'Season' : 'Season ${season.seasonNumber}';
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.client, required this.episodes, required this.onEpisodeTap});
  final JellyfinApiClient client;
  final List<JellyfinLibraryItem> episodes;
  final ValueChanged<JellyfinLibraryItem> onEpisodeTap;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width < 540 ? 1 : width < 960 ? 2 : 3;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: 1.15, crossAxisSpacing: 14, mainAxisSpacing: 16),
          delegate: SliverChildBuilderDelegate((context, index) {
            final episode = episodes[index];
            final code = episodeCode(episode);
            return FocusableMediaCard(
              title: mediaItemTitle(episode),
              subtitle: [code, _dateLabel(episode.premiereDate), episode.runTime == null ? null : _duration(episode.runTime!)].whereType<String>().where((part) => part.isNotEmpty).join(' · '),
              imageUrl: episode.imageUrl(client.baseUrl, type: JellyfinImageType.primary),
              imageClient: client,
              aspectRatio: 16 / 9,
              progress: visualProgress(episode),
              badge: userDataBadgeFor(episode),
              onTap: () => onEpisodeTap(episode),
            );
          }, childCount: episodes.length),
        );
      });
}

class _SimilarGrid extends StatelessWidget {
  const _SimilarGrid({required this.client, required this.items, required this.onTap});
  final JellyfinApiClient client;
  final List<JellyfinLibraryItem> items;
  final ValueChanged<JellyfinLibraryItem> onTap;

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width < 520 ? 2 : width < 760 ? 3 : width < 980 ? 4 : 5;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: .64, crossAxisSpacing: 14, mainAxisSpacing: 16),
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = items[index];
            return FocusableMediaCard(
              title: mediaItemTitle(item),
              subtitle: item.subtitle(),
              imageUrl: item.imageUrl(client.baseUrl, type: JellyfinImageType.primary),
              imageClient: client,
              badge: userDataBadgeFor(item),
              onTap: () => onTap(item),
            );
          }, childCount: items.length),
        );
      });
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) { final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme(); return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: theme.textMuted), const SizedBox(height: 16), Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge), if (action != null) ...[const SizedBox(height: 12), action!]]))); }
}

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
String? _dateLabel(DateTime? value) => value == null ? null : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
List<JellyfinLibraryItem> _selectableSeasons(List<JellyfinLibraryItem> seasons) {
  final seen = <String>{};
  return List<JellyfinLibraryItem>.unmodifiable(seasons.where((season) => season.id.isNotEmpty && seen.add(season.id)));
}
bool _supportsSimilar(JellyfinLibraryItem item) => item.id.isNotEmpty && (item.kind == JellyfinItemKind.movie || item.kind == JellyfinItemKind.series || item.kind == JellyfinItemKind.episode);
bool _supportsPersonalActions(JellyfinLibraryItem item) => item.id.isNotEmpty && (item.kind == JellyfinItemKind.movie || item.kind == JellyfinItemKind.series || item.kind == JellyfinItemKind.episode || item.kind == JellyfinItemKind.audio);
bool _supportsPlayedAction(JellyfinLibraryItem item) => item.id.isNotEmpty && (item.kind == JellyfinItemKind.movie || item.kind == JellyfinItemKind.series || item.kind == JellyfinItemKind.episode || item.kind == JellyfinItemKind.audio);
