import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/screens/playback_callbacks.dart';
import 'package:rodplayer/ui/screens/surprise_me_dialog.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    required this.client,
    this.active = true,
    this.onPlayItem,
    this.onResumeItem,
    this.onUserDataChanged,
    this.latestUserDataChange,
    this.userDataRevision = 0,
    this.serverDataRevision,
    super.key,
  });

  final JellyfinApiClient client;
  final bool active;
  final DetailPlayItemCallback? onPlayItem;
  final ResumeItemCallback? onResumeItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final JellyfinUserDataChange? latestUserDataChange;
  final int userDataRevision;
  final ValueListenable<int>? serverDataRevision;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  static const _shelves = <_DiscoverShelfSpec>[
    _DiscoverShelfSpec(
      'Top rated movies',
      JellyfinDiscoveryKind.movies,
      JellyfinDiscoverySort.topRated,
    ),
    _DiscoverShelfSpec(
      'Recently added movies',
      JellyfinDiscoveryKind.movies,
      JellyfinDiscoverySort.recentlyAdded,
    ),
    _DiscoverShelfSpec(
      'Top rated shows',
      JellyfinDiscoveryKind.tvShows,
      JellyfinDiscoverySort.topRated,
    ),
    _DiscoverShelfSpec(
      'Recently added shows',
      JellyfinDiscoveryKind.tvShows,
      JellyfinDiscoverySort.recentlyAdded,
    ),
  ];

  final Map<_DiscoverShelfSpec, List<JellyfinLibraryItem>> _items = {};
  final Map<_DiscoverShelfSpec, Object> _errors = {};
  final Set<_DiscoverShelfSpec> _loading = {};
  int _generation = 0;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    widget.serverDataRevision?.addListener(_onServerDataInvalidated);
    if (widget.active) _reloadAll();
  }

  @override
  void didUpdateWidget(covariant DiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revisionSourceChanged =
        oldWidget.serverDataRevision != widget.serverDataRevision;
    if (revisionSourceChanged) {
      oldWidget.serverDataRevision?.removeListener(_onServerDataInvalidated);
      widget.serverDataRevision?.addListener(_onServerDataInvalidated);
    }
    if (oldWidget.client != widget.client) {
      _generation++;
      _hasLoaded = false;
      _items.clear();
      _errors.clear();
      _loading.clear();
      if (widget.active) _reloadAll();
    } else if (revisionSourceChanged) {
      _items.clear();
      _errors.clear();
      _loading.clear();
      _hasLoaded = false;
      if (widget.active) {
        _reloadAll();
      } else {
        setState(() {});
      }
    } else if (!oldWidget.active && widget.active && !_hasLoaded) {
      _reloadAll();
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
    if (!mounted) return;
    if (widget.active) {
      _reloadAll();
    } else {
      setState(() {
        _items.clear();
        _errors.clear();
        _loading.clear();
        _hasLoaded = false;
      });
    }
  }

  void _reloadAll() {
    final generation = ++_generation;
    setState(() {
      _items.clear();
      _errors.clear();
      _loading
        ..clear()
        ..addAll(_shelves);
      _hasLoaded = true;
    });
    for (final shelf in _shelves) {
      unawaited(_load(shelf, generation));
    }
  }

  Future<void> _load(_DiscoverShelfSpec shelf, int generation) async {
    try {
      final page = await widget.client.getDiscoveryItemsPage(
        kind: shelf.kind,
        sort: shelf.sort,
        limit: 12,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items[shelf] = page.items
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false);
        _errors.remove(shelf);
        _loading.remove(shelf);
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _errors[shelf] = error;
        _loading.remove(shelf);
      });
    }
  }

  void _retry(_DiscoverShelfSpec shelf) {
    final generation = _generation;
    setState(() {
      _errors.remove(shelf);
      _loading.add(shelf);
    });
    unawaited(_load(shelf, generation));
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final hasItems = _items.values.any((items) => items.isNotEmpty);
    final allSettled = _loading.isEmpty;
    return ColoredBox(
      color: theme.obsidian,
      child: CustomScrollView(
        key: const PageStorageKey<String>('discover-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Discover',
                            style: Theme.of(context).textTheme.headlineMedium),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => showSurpriseMePicker(
                          context: context,
                          client: widget.client,
                          onPlayItem: widget.onPlayItem,
                          onResumeItem: widget.onResumeItem,
                          onUserDataChanged: widget.onUserDataChanged,
                          serverDataRevision: widget.serverDataRevision,
                        ),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Surprise Me'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Highly rated and recently added movies and shows.',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          for (final shelf in _shelves)
            _buildShelf(
              context,
              shelf,
              showEmpty: hasItems || (allSettled && _errors.isNotEmpty),
            ),
          if (allSettled && !hasItems && _errors.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'No movies or shows to discover yet.',
                  style: TextStyle(color: theme.textSecondary),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildShelf(
    BuildContext context,
    _DiscoverShelfSpec shelf, {
    required bool showEmpty,
  }) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final items = _items[shelf] ?? const <JellyfinLibraryItem>[];
    final error = _errors[shelf];
    final loading = _loading.contains(shelf);
    if (!loading && error == null && items.isEmpty && !showEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    if (!loading && error == null && items.isNotEmpty) {
      return SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth =
                (constraints.maxWidth / 4).clamp(144.0, 208.0).toDouble();
            return SmartShelf(
              title: shelf.title,
              itemCount: items.length,
              itemWidth: cardWidth,
              aspectRatio: 2 / 3,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemBuilder: (context, index, focusNode, {required autofocus}) {
                final item = items[index];
                return FocusableMediaCard(
                  title: mediaItemTitle(item),
                  subtitle: item.subtitle(),
                  imageUrl: item.imageUrl(widget.client.baseUrl),
                  imageClient: widget.client,
                  badge: userDataBadgeFor(item),
                  aspectRatio: 2 / 3,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  onTap: () => _openDetails(item),
                );
              },
            );
          },
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shelf.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (loading && items.isEmpty)
              const SizedBox(
                height: 56,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              SizedBox(
                height: 72,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Could not load ${shelf.title.toLowerCase()}.',
                        style: TextStyle(color: theme.textSecondary),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _retry(shelf),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 56,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'No titles available in this shelf.',
                    style: TextStyle(color: theme.textSecondary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetails(JellyfinLibraryItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ItemDetailsScreen(
        client: widget.client,
        itemId: item.id,
        onUserDataChanged: widget.onUserDataChanged,
        serverDataRevision: widget.serverDataRevision,
      ),
    ));
  }

  void _applyUserDataChange(JellyfinUserDataChange? change) {
    if (change == null) return;
    setState(() {
      for (final shelf in _items.keys.toList(growable: false)) {
        _items[shelf] = _items[shelf]!
            .map((item) => item.withUserDataChange(change))
            .toList(growable: false);
      }
    });
  }
}

class _DiscoverShelfSpec {
  const _DiscoverShelfSpec(this.title, this.kind, this.sort);

  final String title;
  final JellyfinDiscoveryKind kind;
  final JellyfinDiscoverySort sort;

  String get key => '${kind.name}-${sort.name}';

  @override
  bool operator ==(Object other) =>
      other is _DiscoverShelfSpec && other.kind == kind && other.sort == sort;

  @override
  int get hashCode => Object.hash(kind, sort);
}
