import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/api/models/media_source_info.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/playback/playback_negotiator.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/platform/playback/platform_playback_runtimes.dart';
import 'package:rodplayer/platform/playback/runtime_playback_probes.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/screens/playback_callbacks.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/routed_jellyfin_image.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

typedef DetailPlayItemCallback = FutureOr<void> Function(
    BuildContext context, String itemId);

class ItemDetailsScreen extends StatefulWidget {
  const ItemDetailsScreen({
    required this.client,
    required this.itemId,
    this.onPlayItem,
    this.onResumeItem,
    this.onUserDataChanged,
    this.serverDataRevision,
    super.key,
  });

  final JellyfinApiClient client;
  final String itemId;
  final DetailPlayItemCallback? onPlayItem;
  final ResumeItemCallback? onResumeItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final ValueListenable<int>? serverDataRevision;

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
  bool _compactTitleVisible = false;
  int _generation = 0;
  int _episodeGeneration = 0;
  bool _loadingSources = false;

  @override
  void initState() {
    super.initState();
    widget.serverDataRevision?.addListener(_onServerDataInvalidated);
    _loadItem();
  }

  @override
  void didUpdateWidget(covariant ItemDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionSourceChanged =
        oldWidget.serverDataRevision != widget.serverDataRevision;
    if (revisionSourceChanged) {
      oldWidget.serverDataRevision?.removeListener(_onServerDataInvalidated);
      widget.serverDataRevision?.addListener(_onServerDataInvalidated);
    }
    if (oldWidget.client != widget.client ||
        oldWidget.itemId != widget.itemId) {
      _loadItem();
    } else if (revisionSourceChanged) {
      _onServerDataInvalidated();
    }
  }

  @override
  void dispose() {
    widget.serverDataRevision?.removeListener(_onServerDataInvalidated);
    super.dispose();
  }

  void _onServerDataInvalidated() {
    if (mounted) _loadItem();
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
      _loadingSources = false;
      _favoriteBusy = false;
      _playedBusy = false;
      _compactTitleVisible = false;
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
      if (item.kind == JellyfinItemKind.series && item.id.isNotEmpty) {
        unawaited(_loadSeasons(item.id, generation));
      }
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
      if (firstSeason != null) {
        unawaited(_loadEpisodes(seriesId: seriesId, seasonId: firstSeason.id));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _seasonsError = error;
          _loadingSeasons = false;
        });
      }
    }
  }

  Future<void> _loadEpisodes(
      {required String seriesId, required String seasonId}) async {
    final episodeGeneration = ++_episodeGeneration;
    setState(() {
      _selectedSeasonId = seasonId;
      _episodes = const <JellyfinLibraryItem>[];
      _episodesError = null;
      _loadingEpisodes = true;
    });
    try {
      final episodes = await widget.client
          .getEpisodes(seriesId: seriesId, seasonId: seasonId);
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

  Future<void> _play(String itemId,
      {String? mediaSourceId, Duration? startPosition}) async {
    final callback = widget.onPlayItem;
    final generation = _generation;
    final isResume = startPosition != null && startPosition > Duration.zero;
    if (callback != null &&
        mediaSourceId == null &&
        (!isResume || widget.onResumeItem != null)) {
      final resume = widget.onResumeItem;
      if (isResume && resume != null) {
        await resume(context, itemId, startPosition);
      } else {
        await callback(context, itemId);
      }
      await _refreshPlayedItem(itemId, generation);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayerRoute(
              client: widget.client,
              itemId: itemId,
              selectedMediaSourceId: mediaSourceId,
              startPosition: startPosition ?? Duration.zero,
              onUserDataChanged: widget.onUserDataChanged,
            )));
    await _refreshPlayedItem(itemId, generation);
  }

  Future<void> _refreshPlayedItem(String itemId, int generation) async {
    if (!mounted || generation != _generation) return;
    try {
      final refreshed = await widget.client.getItem(itemId);
      if (!mounted || generation != _generation) return;
      setState(() => _item = refreshed);
      widget.onUserDataChanged?.call(JellyfinUserDataChange(
          itemId: itemId,
          played: refreshed.userData.played,
          playbackProgressMayHaveChanged: true));
    } catch (_) {
      if (mounted && generation == _generation) {
        widget.onUserDataChanged?.call(JellyfinUserDataChange(
            itemId: itemId, playbackProgressMayHaveChanged: true));
      }
    }
  }

  Future<List<MediaSourceInfo>> _loadMediaSources(String itemId) async {
    final runtimes = await createPlatformPlaybackRuntimes();
    return PlaybackNegotiator(
      client: widget.client,
      environmentProvider: createDefaultRuntimePlaybackEnvironmentProvider(
        identity: widget.client.identity,
        playbackBackendRegistry: runtimes.backendRegistry,
      ),
      runtimeRegistry: runtimes.registry,
    ).listMediaSources(itemId: itemId);
  }

  Future<void> _playVersion() async {
    if (_loadingSources) return;
    final requestedItemId = widget.itemId;
    final requestedGeneration = _generation;
    setState(() {
      _loadingSources = true;
    });
    try {
      final sources = await _loadMediaSources(requestedItemId);
      if (!mounted ||
          requestedGeneration != _generation ||
          requestedItemId != widget.itemId) {
        return;
      }
      if (sources.isEmpty) throw StateError('No versions returned');
      final startPosition =
          hasMeaningfulResumeProgress(_item!) ? _item!.playbackPosition : null;
      if (sources.length == 1) {
        await _play(requestedItemId,
            mediaSourceId: sources.single.id, startPosition: startPosition);
        return;
      }
      final selected = await showModalBottomSheet<MediaSourceInfo>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _MediaSourcePicker(sources: sources),
      );
      if (selected != null &&
          mounted &&
          requestedGeneration == _generation &&
          requestedItemId == widget.itemId) {
        await _play(requestedItemId,
            mediaSourceId: selected.id, startPosition: startPosition);
      }
    } on Object {
      if (mounted && requestedGeneration == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load playback versions')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  void _openEpisode(JellyfinLibraryItem item) {
    _openItem(item);
  }

  void _openItem(JellyfinLibraryItem item) {
    if (item.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ItemDetailsScreen(
            client: widget.client,
            itemId: item.id,
            onPlayItem: widget.onPlayItem,
            onResumeItem: widget.onResumeItem,
            onUserDataChanged: _handleChildUserDataChange,
            serverDataRevision: widget.serverDataRevision)));
  }

  void _handleChildUserDataChange(JellyfinUserDataChange change) {
    if (mounted) {
      setState(() {
        _episodes = _episodes
            .map((item) => item.withUserDataChange(change))
            .toList(growable: false);
        _similar = _similar
            .map((item) => item.withUserDataChange(change))
            .toList(growable: false);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(value ? 'Added to favorites' : 'Removed from favorites')));
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update favorite')));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _favoriteBusy = false);
      }
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
      final change = JellyfinUserDataChange(
          itemId: item.id, played: value, playbackProgressMayHaveChanged: true);
      setState(() => _item = _item!.withUserDataChange(change));
      widget.onUserDataChanged?.call(change);
      if (item.kind == JellyfinItemKind.series && _selectedSeasonId != null) {
        unawaited(
            _loadEpisodes(seriesId: item.id, seasonId: _selectedSeasonId!));
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(value ? 'Marked watched' : 'Marked unwatched')));
    } catch (_) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update watched state')));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _playedBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Scaffold(
      backgroundColor: theme.obsidian,
      body: ColoredBox(
        color: theme.obsidian,
        child: _loadingItem
            ? const Center(child: CircularProgressIndicator())
            : _itemError != null
                ? _Message(
                    icon: Icons.cloud_off_outlined,
                    title: 'Details unavailable',
                    action: TextButton(
                        onPressed: _loadItem, child: const Text('Retry')))
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
                    onSeasonChanged: (seasonId) => unawaited(
                        _loadEpisodes(seriesId: _item!.id, seasonId: seasonId)),
                    onRetrySeasons: () =>
                        unawaited(_loadSeasons(_item!.id, _generation)),
                    onRetryEpisodes: () {
                      final seasonId = _selectedSeasonId;
                      if (seasonId != null) {
                        unawaited(_loadEpisodes(
                            seriesId: _item!.id, seasonId: seasonId));
                      }
                    },
                    onRetrySimilar: () =>
                        unawaited(_loadSimilar(_item!.id, _generation)),
                    onPlay: isDirectlyPlayable(_item!)
                        ? () => _play(_item!.id,
                            startPosition: hasMeaningfulResumeProgress(_item!)
                                ? _item!.playbackPosition
                                : null)
                        : null,
                    onPlayVersion: isDirectlyPlayable(_item!)
                        ? () => unawaited(_playVersion())
                        : null,
                    loadingSources: _loadingSources,
                    favoriteBusy: _favoriteBusy,
                    playedBusy: _playedBusy,
                    onFavorite: _supportsPersonalActions(_item!)
                        ? () =>
                            unawaited(_setFavorite(!_item!.userData.isFavorite))
                        : null,
                    onPlayed: _supportsPlayedAction(_item!)
                        ? () => unawaited(_setPlayed(!_item!.userData.played))
                        : null,
                    compactTitleVisible: _compactTitleVisible,
                    onCompactTitleVisibilityChanged: (visible) {
                      if (_compactTitleVisible != visible) {
                        setState(() => _compactTitleVisible = visible);
                      }
                    },
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
    required this.onPlayVersion,
    required this.loadingSources,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
    required this.compactTitleVisible,
    required this.onCompactTitleVisibilityChanged,
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
  final VoidCallback? onPlayVersion;
  final bool loadingSources;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;
  final bool compactTitleVisible;
  final ValueChanged<bool> onCompactTitleVisibilityChanged;
  final ValueChanged<JellyfinLibraryItem> onEpisodeTap;
  final ValueChanged<JellyfinLibraryItem> onSimilarTap;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final topInset = MediaQuery.paddingOf(context).top;
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final heroExtent = compact
            ? (viewportHeight * .58).clamp(380.0, 520.0).toDouble()
            : (viewportHeight * .76).clamp(560.0, 900.0).toDouble();
        final cast = item.people
            .where((person) =>
                person.name.trim().isNotEmpty &&
                person.type?.trim().toLowerCase() == 'actor')
            .toList(growable: false);
        return Stack(children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              onCompactTitleVisibilityChanged(
                  notification.metrics.pixels >= (heroExtent - 64) * .23);
              return false;
            },
            child: CustomScrollView(slivers: [
              SliverPersistentHeader(
                pinned: false,
                delegate: _DetailsHeaderDelegate(
                  item: item,
                  client: client,
                  compact: compact,
                  topInset: topInset,
                  expandedExtent: heroExtent,
                  onPlay: onPlay,
                  onPlayVersion: onPlayVersion,
                  loadingSources: loadingSources,
                  favoriteBusy: favoriteBusy,
                  playedBusy: playedBusy,
                  onFavorite: onFavorite,
                  onPlayed: onPlayed,
                ),
              ),
              if (compact && item.studios.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 36, 24, compact ? 20 : 36, 24),
                  sliver: SliverToBoxAdapter(child: _DetailFacts(item: item)),
                ),
              if (item.kind == JellyfinItemKind.series) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 36, 0, compact ? 20 : 36, 16),
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
                if (!loadingSeasons &&
                    seasonsError == null &&
                    _selectableSeasons(seasons).isNotEmpty &&
                    !loadingEpisodes &&
                    episodesError == null &&
                    episodes.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        compact ? 20 : 36, 0, compact ? 20 : 36, 36),
                    sliver: _EpisodeGrid(
                        client: client,
                        episodes: episodes,
                        onEpisodeTap: onEpisodeTap),
                  ),
                if (!loadingSeasons &&
                    seasonsError == null &&
                    _selectableSeasons(seasons).isNotEmpty &&
                    !loadingEpisodes &&
                    episodesError == null &&
                    episodes.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        compact ? 20 : 36, 0, compact ? 20 : 36, 36),
                    sliver: const SliverToBoxAdapter(
                        child: _Message(
                            icon: Icons.video_library_outlined,
                            title: 'No episodes found')),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
              if (cast.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 36, 8, compact ? 20 : 36, 32),
                  sliver: SliverToBoxAdapter(
                      child: _CastSection(client: client, people: cast)),
                ),
              if (loadingSimilar ||
                  similarError != null ||
                  similar.isNotEmpty) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 36, 0, compact ? 20 : 36, 12),
                  sliver: SliverToBoxAdapter(
                      child: Text('More Like This',
                          style: Theme.of(context).textTheme.titleLarge)),
                ),
                if (loadingSimilar)
                  const SliverToBoxAdapter(
                      child: Center(
                          child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator())))
                else if (similarError != null)
                  SliverToBoxAdapter(
                      child: _Message(
                          icon: Icons.explore_off_outlined,
                          title: 'Similar items unavailable',
                          action: TextButton(
                              onPressed: onRetrySimilar,
                              child: const Text('Retry'))))
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        compact ? 20 : 36, 0, compact ? 20 : 36, 36),
                    sliver: SliverToBoxAdapter(
                      child: SizedBox(
                        height: 340,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                              horizontal: compact ? 20 : 36),
                          itemCount: similar.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 14),
                          itemBuilder: (context, index) {
                            final item = similar[index];
                            return SizedBox(
                              width: 176,
                              child: FocusableMediaCard(
                                title: mediaItemTitle(item),
                                subtitle: item.subtitle(),
                                imageUrl: item.imageUrl(client.baseUrl),
                                imageClient: client,
                                badge: userDataBadgeFor(item),
                                onTap: () => onSimilarTap(item),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ]),
          ),
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            height: 64,
            child:
                _DetailsTopBar(item: item, titleVisible: compactTitleVisible),
          ),
        ]);
      });
}

class _CastSection extends StatelessWidget {
  const _CastSection({required this.client, required this.people});

  final JellyfinApiClient client;
  final List<JellyfinPerson> people;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cast', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: people.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final person = people[index];
                final imageUrl = person.imageUrl(client.baseUrl);
                final theme = Theme.of(context).extension<RodPlayerTheme>() ??
                    const RodPlayerTheme();
                return SizedBox(
                  key: ValueKey<String>('cast-card-${person.id}'),
                  width: 132,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(theme.radiusSmall),
                        child: SizedBox(
                          width: 132,
                          height: 148,
                          child: imageUrl == null
                              ? ColoredBox(
                                  color: theme.surface2,
                                  child: Icon(Icons.person_outline,
                                      color: theme.textSecondary, size: 36),
                                )
                              : RoutedJellyfinImage(
                                  client: client,
                                  url: imageUrl,
                                  fit: BoxFit.cover,
                                  fallback: ColoredBox(
                                    color: theme.surface2,
                                    child: Icon(Icons.person_outline,
                                        color: theme.textSecondary, size: 36),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(person.name,
                          key: ValueKey<String>('cast-name-${person.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      if (person.role?.trim().isNotEmpty == true)
                        Text(person.role!,
                            key: ValueKey<String>('cast-role-${person.id}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: theme.textSecondary, fontSize: 12)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
}

class _DetailsTopBar extends StatelessWidget {
  const _DetailsTopBar({required this.item, required this.titleVisible});

  final JellyfinLibraryItem item;
  final bool titleVisible;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Material(
      color: titleVisible ? theme.obsidianGlassStrong : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: titleVisible
                  ? Colors.transparent
                  : Colors.black.withValues(alpha: .46),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back,
                  color: titleVisible ? theme.textPrimary : Colors.white),
            ),
          ),
          Expanded(
            child: IgnorePointer(
              ignoring: !titleVisible,
              child: ExcludeFocus(
                excluding: !titleVisible,
                child: ExcludeSemantics(
                  excluding: !titleVisible,
                  child: AnimatedOpacity(
                    opacity: titleVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Text(
                      mediaItemTitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DetailsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DetailsHeaderDelegate({
    required this.item,
    required this.client,
    required this.compact,
    required this.topInset,
    required this.expandedExtent,
    required this.onPlay,
    required this.onPlayVersion,
    required this.loadingSources,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final bool compact;
  final double topInset;
  final double expandedExtent;
  final VoidCallback? onPlay;
  final VoidCallback? onPlayVersion;
  final bool loadingSources;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;

  @override
  double get minExtent => topInset + 64;

  @override
  double get maxExtent => topInset + expandedExtent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = maxExtent - minExtent;
    final collapse = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    return _CinematicDetailsHeader(
      item: item,
      client: client,
      compact: compact,
      topInset: topInset,
      collapse: collapse,
      onPlay: onPlay,
      onPlayVersion: onPlayVersion,
      loadingSources: loadingSources,
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
      expandedExtent != oldDelegate.expandedExtent ||
      onPlay != oldDelegate.onPlay ||
      onPlayVersion != oldDelegate.onPlayVersion ||
      loadingSources != oldDelegate.loadingSources ||
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
    required this.onPlayVersion,
    required this.loadingSources,
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
  final VoidCallback? onPlayVersion;
  final bool loadingSources;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final backdropUrl = item.imageUrl(client.baseUrl,
            type: JellyfinImageType.backdrop, quality: 90) ??
        item.imageUrl(client.baseUrl,
            type: JellyfinImageType.primary, quality: 90);
    final expandedOpacity = 1 - ((collapse - .05) / .18).clamp(0.0, 1.0);
    final compactControlsActive = collapse >= .23;
    final summaryLeft = (compact ? 22.0 : 40.0) +
        (compact ? 54.0 : 48.0) * (collapse * 2.2).clamp(0.0, 1.0);

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
                    Colors.black.withValues(alpha: .40),
                    Colors.black.withValues(alpha: .12),
                    Colors.transparent,
                    theme.artworkScrim.withValues(alpha: .62),
                    theme.obsidian.withValues(alpha: .96),
                    theme.obsidian,
                  ],
                  stops: const <double>[0, .14, .34, .62, .88, 1],
                ),
              ),
            ),
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
                        client: client,
                        compact: compact,
                        onPlay: onPlay,
                        onPlayVersion: onPlayVersion,
                        loadingSources: loadingSources,
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
        ]),
      ),
    );
  }
}

class _ExpandedDetailSummary extends StatelessWidget {
  const _ExpandedDetailSummary({
    required this.item,
    required this.client,
    required this.compact,
    required this.onPlay,
    required this.onPlayVersion,
    required this.loadingSources,
    required this.favoriteBusy,
    required this.playedBusy,
    required this.onFavorite,
    required this.onPlayed,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final bool compact;
  final VoidCallback? onPlay;
  final VoidCallback? onPlayVersion;
  final bool loadingSources;
  final bool favoriteBusy;
  final bool playedBusy;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlayed;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final metadata = _detailMetadata(item);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailTitleTreatment(
              item: item,
              client: client,
              compact: compact,
              theme: theme,
            ),
            if (metadata.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: metadata
                      .map((label) => _DetailPill(label: label))
                      .toList()),
            ],
            if (item.genres.isNotEmpty) ...[
              const SizedBox(height: 9),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: item.genres.take(6).map(_GenrePill.new).toList(),
              ),
            ],
            if (item.tagline != null && item.tagline!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(item.tagline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: theme.artworkTextSecondary,
                      fontStyle: FontStyle.italic)),
            ],
            if (item.overview != null && item.overview!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 520 : 780),
                child: Text(item.overview!,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: theme.artworkTextPrimary, height: 1.35)),
              ),
            ],
            if (!compact && item.studios.isNotEmpty) ...[
              const SizedBox(height: 7),
              _DetailFacts(item: item, onArtwork: true),
            ],
            if (onPlay != null || onFavorite != null || onPlayed != null) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (onPlay != null)
                  FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(hasMeaningfulResumeProgress(item)
                          ? 'Resume'
                          : 'Play'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      )),
                if (onPlayVersion != null)
                  OutlinedButton.icon(
                    onPressed: loadingSources ? null : onPlayVersion,
                    icon: loadingSources
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.video_settings_outlined),
                    label: const Text('Play Version'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.artworkTextPrimary,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: .24)),
                    ),
                  ),
                if (onFavorite != null)
                  OutlinedButton.icon(
                    onPressed: favoriteBusy ? null : onFavorite,
                    icon: Icon(item.userData.isFavorite
                        ? Icons.favorite
                        : Icons.favorite_border),
                    label: Text(item.userData.isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.artworkTextPrimary,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: .24)),
                    ),
                  ),
                if (onPlayed != null)
                  OutlinedButton.icon(
                    onPressed: playedBusy ? null : onPlayed,
                    icon: Icon(item.userData.played
                        ? Icons.check_circle
                        : Icons.check_circle_outline),
                    label: Text(item.kind == JellyfinItemKind.audio
                        ? (item.userData.played
                            ? 'Mark unplayed'
                            : 'Mark played')
                        : (item.userData.played
                            ? 'Mark unwatched'
                            : 'Mark watched')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.artworkTextPrimary,
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: .24)),
                    ),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'More item actions',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (action) {
                    switch (action) {
                      case 'version':
                        onPlayVersion?.call();
                        break;
                      case 'favorite':
                        onFavorite?.call();
                        break;
                      case 'played':
                        onPlayed?.call();
                        break;
                      case 'info':
                        unawaited(_showItemInformation(context, item));
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (onPlayVersion != null)
                      const PopupMenuItem(
                          value: 'version', child: Text('Play Version…')),
                    if (onFavorite != null)
                      PopupMenuItem(
                          value: 'favorite',
                          child: Text(item.userData.isFavorite
                              ? 'Remove from favorites'
                              : 'Add to favorites')),
                    if (onPlayed != null)
                      PopupMenuItem(
                          value: 'played',
                          child: Text(item.userData.played
                              ? 'Mark unwatched'
                              : 'Mark watched')),
                    const PopupMenuItem(
                        value: 'info', child: Text('Item information')),
                  ],
                ),
              ]),
            ],
          ]),
    );
  }
}

Future<void> _showItemInformation(
    BuildContext context, JellyfinLibraryItem item) async {
  final facts = <String>[
    if (item.productionYear != null) '${item.productionYear}',
    if (item.officialRating?.isNotEmpty == true) item.officialRating!,
    if (item.runTime != null) _duration(item.runTime!),
    ...item.genres.take(4),
    ...item.studios.take(3),
  ];
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(item.title),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (facts.isNotEmpty) Text(facts.join(' · ')),
            const SizedBox(height: 12),
            Text('Jellyfin item ID',
                style: Theme.of(context).textTheme.labelMedium),
            SelectableText(item.id),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Close'))
      ],
    ),
  );
}

class _DetailTitleTreatment extends StatelessWidget {
  const _DetailTitleTreatment({
    required this.item,
    required this.client,
    required this.compact,
    required this.theme,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final bool compact;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) {
    final title = mediaItemTitle(item);
    final fallback = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        color: theme.artworkTextPrimary,
        fontSize: compact ? 32 : 44,
        height: 1.02,
        letterSpacing: compact ? -0.5 : -0.8,
        fontWeight: FontWeight.w800,
        shadows: const <Shadow>[
          Shadow(color: Colors.black54, blurRadius: 18),
        ],
      ),
    );
    final logoUrl = item.imageUrl(
      client.baseUrl,
      type: JellyfinImageType.logo,
      quality: 90,
    );
    if (logoUrl == null) return fallback;
    return Semantics(
      image: true,
      label: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 520 : 760),
        child: SizedBox(
          height: compact ? 74 : 112,
          child: Align(
            alignment: Alignment.centerLeft,
            child: RoutedJellyfinImage(
              client: client,
              url: logoUrl,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              fallback: fallback,
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(theme.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(label,
            style: TextStyle(
                color: theme.artworkTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _GenrePill extends StatelessWidget {
  const _GenrePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(theme.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(label,
            style: TextStyle(
              color: theme.artworkTextSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            )),
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
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (item.studios.isNotEmpty)
        _FactLine(
            label: 'Studios',
            value: item.studios.take(3).join(', '),
            theme: theme,
            onArtwork: onArtwork),
    ]);
  }
}

class _FactLine extends StatelessWidget {
  const _FactLine(
      {required this.label,
      required this.value,
      required this.theme,
      this.onArtwork = false});
  final String label;
  final String value;
  final RodPlayerTheme theme;
  final bool onArtwork;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label: ',
              style: TextStyle(
                  color:
                      onArtwork ? theme.artworkTextSecondary : theme.textMuted,
                  fontWeight: FontWeight.w700)),
          TextSpan(
              text: value,
              style: TextStyle(
                  color: onArtwork
                      ? theme.artworkTextSecondary
                      : theme.textSecondary)),
        ])),
      );
}

List<String> _detailMetadata(JellyfinLibraryItem item) => <String>[
      if (item.productionYear != null) item.productionYear.toString(),
      if (item.officialRating != null && item.officialRating!.isNotEmpty)
        item.officialRating!,
      if (item.communityRating != null) 'Rating ${item.communityRating} / 10',
      if (item.runTime != null) _duration(item.runTime!),
      if (item.status != null && item.status!.isNotEmpty) item.status!,
      if (_dateLabel(item.premiereDate) != null) _dateLabel(item.premiereDate)!,
      if (item.kind == JellyfinItemKind.episode && item.seriesName != null)
        item.seriesName!,
      if (item.kind == JellyfinItemKind.episode && item.seasonName != null)
        item.seasonName!,
      if (item.kind == JellyfinItemKind.episode && episodeCode(item).isNotEmpty)
        episodeCode(item),
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
    if (loadingSeasons) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (seasonsError != null) {
      return _Message(
          icon: Icons.cloud_off_outlined,
          title: 'Seasons unavailable',
          action: TextButton(
              onPressed: onRetrySeasons, child: const Text('Retry')));
    }
    if (seasons.isEmpty) {
      return const _Message(icon: Icons.tv_outlined, title: 'No seasons found');
    }
    final selectableSeasons = _selectableSeasons(seasons);
    if (selectableSeasons.isEmpty) {
      return const _Message(
          icon: Icons.tv_outlined, title: 'No selectable seasons found');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Episodes',
                style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(width: 12),
        Flexible(
          child: DropdownButton<String>(
            value: selectedSeasonId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: selectableSeasons
                .map((season) => DropdownMenuItem<String>(
                    value: season.id,
                    child: Text(_seasonTitle(season),
                        maxLines: 1, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (value) {
              if (value != null) onSeasonChanged(value);
            },
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (loadingEpisodes)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator()))
      else if (episodesError != null)
        _Message(
            icon: Icons.cloud_off_outlined,
            title: 'Episodes unavailable',
            action: TextButton(
                onPressed: onRetryEpisodes, child: const Text('Retry')))
    ]);
  }

  String _seasonTitle(JellyfinLibraryItem season) {
    if (season.seasonName != null && season.seasonName!.trim().isNotEmpty) {
      return season.seasonName!;
    }
    if (season.title.isNotEmpty) return season.title;
    if (season.seasonNumber == 0) return 'Specials';
    return season.seasonNumber == null
        ? 'Season'
        : 'Season ${season.seasonNumber}';
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid(
      {required this.client,
      required this.episodes,
      required this.onEpisodeTap});
  final JellyfinApiClient client;
  final List<JellyfinLibraryItem> episodes;
  final ValueChanged<JellyfinLibraryItem> onEpisodeTap;

  @override
  Widget build(BuildContext context) =>
      SliverLayoutBuilder(builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width < 540
            ? 1
            : width < 960
                ? 2
                : 3;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 1.15,
              crossAxisSpacing: 14,
              mainAxisSpacing: 16),
          delegate: SliverChildBuilderDelegate((context, index) {
            final episode = episodes[index];
            final code = episodeCode(episode);
            return FocusableMediaCard(
              title: mediaItemTitle(episode),
              subtitle: [
                code,
                _dateLabel(episode.premiereDate),
                episode.runTime == null ? null : _duration(episode.runTime!)
              ]
                  .whereType<String>()
                  .where((part) => part.isNotEmpty)
                  .join(' · '),
              imageUrl: episode.imageUrl(client.baseUrl,
                  type: JellyfinImageType.primary),
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

class _MediaSourcePicker extends StatelessWidget {
  const _MediaSourcePicker({required this.sources});
  final List<MediaSourceInfo> sources;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose playback version',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final source = sources[index];
                      final video = source.videoStreams.isEmpty
                          ? null
                          : source.videoStreams.first;
                      final audio = source.audioStreams.isEmpty
                          ? null
                          : source.audioStreams.first;
                      final name = '${source.raw['Name'] ?? ''}'.trim();
                      final resolution =
                          video?.width != null && video?.height != null
                              ? '${video!.width}×${video.height}'
                              : null;
                      final hdr = video?.videoRangeType ?? video?.videoRange;
                      final details = <String>[
                        if (resolution != null) resolution,
                        if (video?.codec?.isNotEmpty == true) video!.codec!,
                        if (hdr?.isNotEmpty == true) hdr!,
                        if (audio?.codec?.isNotEmpty == true) audio!.codec!,
                        if (audio?.channelLayout?.isNotEmpty == true)
                          audio!.channelLayout!,
                        if (audio?.channels != null) '${audio!.channels} ch',
                        if (source.container?.isNotEmpty == true)
                          source.container!,
                        if (source.bitrate != null && source.bitrate! > 0)
                          '${(source.bitrate! / 1000000).toStringAsFixed(1)} Mbps',
                      ];
                      return ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title:
                            Text(name.isEmpty ? 'Version ${index + 1}' : name),
                        subtitle:
                            details.isEmpty ? null : Text(details.join(' · ')),
                        onTap: () => Navigator.of(context).pop(source),
                      );
                    },
                  ),
                ),
              ]),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 52, color: theme.textMuted),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              if (action != null) ...[const SizedBox(height: 12), action!]
            ])));
  }
}

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}

String? _dateLabel(DateTime? value) => value == null
    ? null
    : '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
List<JellyfinLibraryItem> _selectableSeasons(
    List<JellyfinLibraryItem> seasons) {
  final seen = <String>{};
  return List<JellyfinLibraryItem>.unmodifiable(
      seasons.where((season) => season.id.isNotEmpty && seen.add(season.id)));
}

bool _supportsSimilar(JellyfinLibraryItem item) =>
    item.id.isNotEmpty &&
    (item.kind == JellyfinItemKind.movie ||
        item.kind == JellyfinItemKind.series ||
        item.kind == JellyfinItemKind.episode);
bool _supportsPersonalActions(JellyfinLibraryItem item) =>
    item.id.isNotEmpty &&
    (item.kind == JellyfinItemKind.movie ||
        item.kind == JellyfinItemKind.series ||
        item.kind == JellyfinItemKind.episode ||
        item.kind == JellyfinItemKind.audio);
bool _supportsPlayedAction(JellyfinLibraryItem item) =>
    item.id.isNotEmpty &&
    (item.kind == JellyfinItemKind.movie ||
        item.kind == JellyfinItemKind.series ||
        item.kind == JellyfinItemKind.episode ||
        item.kind == JellyfinItemKind.audio);
