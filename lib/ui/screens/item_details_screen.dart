import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';

typedef DetailPlayItemCallback = void Function(BuildContext context, String itemId);

class ItemDetailsScreen extends StatefulWidget {
  const ItemDetailsScreen({
    required this.client,
    required this.itemId,
    this.onPlayItem,
    super.key,
  });

  final JellyfinApiClient client;
  final String itemId;
  final DetailPlayItemCallback? onPlayItem;

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  JellyfinLibraryItem? _item;
  List<JellyfinLibraryItem> _seasons = const <JellyfinLibraryItem>[];
  List<JellyfinLibraryItem> _episodes = const <JellyfinLibraryItem>[];
  String? _selectedSeasonId;
  Object? _itemError;
  Object? _seasonsError;
  Object? _episodesError;
  bool _loadingItem = true;
  bool _loadingSeasons = false;
  bool _loadingEpisodes = false;
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
      _selectedSeasonId = null;
      _itemError = null;
      _seasonsError = null;
      _episodesError = null;
      _loadingItem = true;
      _loadingSeasons = false;
      _loadingEpisodes = false;
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
      if (item.kind == JellyfinItemKind.series) unawaited(_loadSeasons(item.id, generation));
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
      JellyfinLibraryItem? firstSeason;
      for (final season in seasons) {
        if (season.id.isNotEmpty) {
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

  void _play(String itemId) {
    final callback = widget.onPlayItem;
    if (callback != null) return callback(context, itemId);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerRoute(client: widget.client, itemId: itemId)));
  }

  void _openEpisode(JellyfinLibraryItem item) {
    if (item.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailsScreen(client: widget.client, itemId: item.id, onPlayItem: widget.onPlayItem)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Scaffold(
      backgroundColor: theme.obsidian,
      appBar: AppBar(title: Text(_item == null ? 'Details' : mediaItemTitle(_item!)), centerTitle: false),
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
                    seasonsError: _seasonsError,
                    episodesError: _episodesError,
                    onSeasonChanged: (seasonId) => unawaited(_loadEpisodes(seriesId: _item!.id, seasonId: seasonId)),
                    onRetrySeasons: () => unawaited(_loadSeasons(_item!.id, _generation)),
                    onRetryEpisodes: () {
                      final seasonId = _selectedSeasonId;
                      if (seasonId != null) unawaited(_loadEpisodes(seriesId: _item!.id, seasonId: seasonId));
                    },
                    onPlay: isDirectlyPlayable(_item!) ? () => _play(_item!.id) : null,
                    onEpisodeTap: _openEpisode,
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
    required this.seasonsError,
    required this.episodesError,
    required this.onSeasonChanged,
    required this.onRetrySeasons,
    required this.onRetryEpisodes,
    required this.onPlay,
    required this.onEpisodeTap,
  });

  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final List<JellyfinLibraryItem> seasons;
  final List<JellyfinLibraryItem> episodes;
  final String? selectedSeasonId;
  final bool loadingSeasons;
  final bool loadingEpisodes;
  final Object? seasonsError;
  final Object? episodesError;
  final ValueChanged<String> onSeasonChanged;
  final VoidCallback onRetrySeasons;
  final VoidCallback onRetryEpisodes;
  final VoidCallback? onPlay;
  final ValueChanged<JellyfinLibraryItem> onEpisodeTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 24, compact ? 20 : 36, 24),
            sliver: SliverToBoxAdapter(child: _Header(item: item, client: client, compact: compact, onPlay: onPlay)),
          ),
          if (item.kind == JellyfinItemKind.series)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(compact ? 20 : 36, 0, compact ? 20 : 36, 36),
              sliver: SliverToBoxAdapter(
                child: _SeriesSection(
                  client: client,
                  seasons: seasons,
                  episodes: episodes,
                  selectedSeasonId: selectedSeasonId,
                  loadingSeasons: loadingSeasons,
                  loadingEpisodes: loadingEpisodes,
                  seasonsError: seasonsError,
                  episodesError: episodesError,
                  onSeasonChanged: onSeasonChanged,
                  onRetrySeasons: onRetrySeasons,
                  onRetryEpisodes: onRetryEpisodes,
                  onEpisodeTap: onEpisodeTap,
                ),
              ),
            ),
        ]);
      });
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.client, required this.compact, required this.onPlay});
  final JellyfinLibraryItem item;
  final JellyfinApiClient client;
  final bool compact;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl(client.baseUrl, type: JellyfinImageType.primary, quality: 90);
    final poster = AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: imageUrl == null ? const ColoredBox(color: Colors.white10, child: Icon(Icons.movie_outlined, size: 56, color: Colors.white38)) : Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white10, child: SizedBox.expand())),
      ),
    );
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(mediaItemTitle(item), maxLines: compact ? 2 : 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineMedium),
      if (_subtitle(item).isNotEmpty) ...[const SizedBox(height: 8), Text(_subtitle(item), style: const TextStyle(color: Colors.white70))],
      if (item.tagline != null) ...[const SizedBox(height: 10), Text(item.tagline!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic))],
      if (item.overview != null) ...[const SizedBox(height: 14), Text(item.overview!, maxLines: compact ? 5 : 8, overflow: TextOverflow.ellipsis)],
      if (item.genres.isNotEmpty) ...[const SizedBox(height: 12), Text(item.genres.take(4).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70))],
      const SizedBox(height: 18),
      if (onPlay != null) FilledButton.icon(onPressed: onPlay, icon: const Icon(Icons.play_arrow), label: Text(hasMeaningfulResumeProgress(item) ? 'Resume' : 'Play')),
    ]);
    if (compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: SizedBox(width: 190, child: poster)), const SizedBox(height: 20), details]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 220, child: poster), const SizedBox(width: 28), Expanded(child: details)]);
  }

  String _subtitle(JellyfinLibraryItem item) => [
        item.kind == JellyfinItemKind.episode ? item.seriesName : null,
        item.productionYear?.toString(),
        item.officialRating,
        item.communityRating == null ? null : '★ ${item.communityRating}',
        if (item.runTime != null) _duration(item.runTime!),
      ].whereType<String>().where((part) => part.isNotEmpty).join(' · ');
}

class _SeriesSection extends StatelessWidget {
  const _SeriesSection({
    required this.client,
    required this.seasons,
    required this.episodes,
    required this.selectedSeasonId,
    required this.loadingSeasons,
    required this.loadingEpisodes,
    required this.seasonsError,
    required this.episodesError,
    required this.onSeasonChanged,
    required this.onRetrySeasons,
    required this.onRetryEpisodes,
    required this.onEpisodeTap,
  });

  final JellyfinApiClient client;
  final List<JellyfinLibraryItem> seasons;
  final List<JellyfinLibraryItem> episodes;
  final String? selectedSeasonId;
  final bool loadingSeasons;
  final bool loadingEpisodes;
  final Object? seasonsError;
  final Object? episodesError;
  final ValueChanged<String> onSeasonChanged;
  final VoidCallback onRetrySeasons;
  final VoidCallback onRetryEpisodes;
  final ValueChanged<JellyfinLibraryItem> onEpisodeTap;

  @override
  Widget build(BuildContext context) {
    if (loadingSeasons) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    if (seasonsError != null) return _Message(icon: Icons.cloud_off_outlined, title: 'Seasons unavailable', action: TextButton(onPressed: onRetrySeasons, child: const Text('Retry')));
    if (seasons.isEmpty) return const _Message(icon: Icons.tv_outlined, title: 'No seasons found');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Episodes', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(width: 12),
        Flexible(
          child: DropdownButton<String>(
            value: selectedSeasonId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: seasons.where((season) => season.id.isNotEmpty).map((season) => DropdownMenuItem<String>(value: season.id, child: Text(_seasonTitle(season), maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
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
      else if (episodes.isEmpty)
        const _Message(icon: Icons.video_library_outlined, title: 'No episodes found')
      else
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth < 540 ? 2 : constraints.maxWidth < 840 ? 3 : 4;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: episodes.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: .72, crossAxisSpacing: 14, mainAxisSpacing: 16),
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final code = episodeCode(episode);
              return FocusableMediaCard(
                title: mediaItemTitle(episode),
                subtitle: [code, episode.runTime == null ? null : _duration(episode.runTime!)].whereType<String>().where((part) => part.isNotEmpty).join(' · '),
                imageUrl: episode.imageUrl(client.baseUrl),
                progress: visualProgress(episode),
                onTap: () => onEpisodeTap(episode),
              );
            },
          );
        }),
    ]);
  }

  String _seasonTitle(JellyfinLibraryItem season) {
    if (season.seasonName != null && season.seasonName!.trim().isNotEmpty) return season.seasonName!;
    if (season.title.isNotEmpty) return season.title;
    return season.seasonNumber == null ? 'Season' : 'Season ${season.seasonNumber}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: Colors.white38), const SizedBox(height: 16), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), if (action != null) ...[const SizedBox(height: 12), action!]])));
}

String _duration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours <= 0) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
