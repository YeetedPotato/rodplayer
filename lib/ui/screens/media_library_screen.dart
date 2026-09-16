import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

typedef LibraryPlayItemCallback = void Function(BuildContext context, String itemId);

class MediaLibraryScreen extends StatefulWidget {
  const MediaLibraryScreen({
    required this.client,
    required this.kind,
    this.onPlayItem,
    this.onUserDataChanged,
    this.latestUserDataChange,
    this.userDataRevision = 0,
    super.key,
  });

  final JellyfinApiClient client;
  final JellyfinLibraryKind kind;
  final LibraryPlayItemCallback? onPlayItem;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final JellyfinUserDataChange? latestUserDataChange;
  final int userDataRevision;

  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen> {
  static const _pageSize = 48;
  final _scrollController = ScrollController();
  final _ids = <String>{};
  var _sort = JellyfinLibrarySort.title;
  var _filter = JellyfinLibraryFilter.all;
  var _items = <JellyfinLibraryItem>[];
  Object? _initialError;
  Object? _loadMoreError;
  int? _totalRecordCount;
  int _nextStartIndex = 0;
  int _generation = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    _reload();
  }

  @override
  void didUpdateWidget(covariant MediaLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client || oldWidget.kind != widget.kind) {
      _reload();
    } else if (oldWidget.userDataRevision != widget.userDataRevision) {
      _applyUserDataChange(widget.latestUserDataChange);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _reload() {
    _generation++;
    _ids.clear();
    setState(() {
      _items = const <JellyfinLibraryItem>[];
      _initialError = null;
      _loadMoreError = null;
      _totalRecordCount = null;
      _nextStartIndex = 0;
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadPage(initial: true, generation: _generation);
  }

  void _setSort(JellyfinLibrarySort sort) {
    if (sort == _sort) return;
    _sort = sort;
    _reload();
  }

  void _setFilter(JellyfinLibraryFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    _reload();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _loadingInitial || _loadingMore || !_hasMore || _loadMoreError != null) return;
    if (_scrollController.position.extentAfter < 700) _loadPage(generation: _generation);
  }

  Future<void> _loadPage({bool initial = false, required int generation}) async {
    if (!initial && (_loadingMore || !_hasMore)) return;
    final startIndex = initial ? 0 : _nextStartIndex;
    if (!initial) setState(() => _loadingMore = true);
    try {
      final page = await widget.client.getLibraryItemsPage(kind: widget.kind, sort: _sort, filter: _filter, startIndex: startIndex, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      final nextItems = initial ? <JellyfinLibraryItem>[] : List<JellyfinLibraryItem>.of(_items);
      if (initial) _ids.clear();
      for (final item in page.items) {
        if (item.id.isEmpty || _ids.add(item.id)) nextItems.add(item);
      }
      final consumedStart = page.startIndex ?? startIndex;
      final consumedNext = consumedStart + page.items.length;
      setState(() {
        _items = nextItems;
        _initialError = null;
        _loadMoreError = null;
        _totalRecordCount = page.totalRecordCount;
        _nextStartIndex = consumedNext;
        _loadingInitial = false;
        _loadingMore = false;
        _hasMore = page.totalRecordCount == null ? page.items.length >= _pageSize : consumedNext < page.totalRecordCount!;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (initial) {
          _initialError = error;
          _loadingInitial = false;
        } else {
          _loadMoreError = error;
          _loadingMore = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return ColoredBox(
      color: theme.obsidian,
      child: CustomScrollView(
        key: PageStorageKey<String>('${widget.kind.name}-library-scroll'),
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(child: _LibraryHeader(kind: widget.kind, total: _totalRecordCount, sort: _sort, filter: _filter, onSort: _setSort, onFilter: _setFilter, onRefresh: _reload)),
          if (_loadingInitial) const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else if (_initialError != null) SliverFillRemaining(hasScrollBody: false, child: _LibraryMessage(icon: Icons.cloud_off_outlined, title: '$_title unavailable', action: TextButton(onPressed: _reload, child: const Text('Retry'))))
          else if (_items.isEmpty) SliverFillRemaining(hasScrollBody: false, child: _LibraryMessage(icon: Icons.movie_filter_outlined, title: _filter == JellyfinLibraryFilter.all ? 'No $_emptyName found' : 'No ${_filter.label.toLowerCase()} $_emptyName'))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              sliver: SliverLayoutBuilder(builder: (context, constraints) {
                final columns = _columnsFor(constraints.crossAxisExtent);
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: .64, crossAxisSpacing: 16, mainAxisSpacing: 18),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = _items[index];
                    return FocusableMediaCard(title: mediaItemTitle(item), subtitle: item.productionYear?.toString() ?? item.rawType, imageUrl: item.imageUrl(widget.client.baseUrl), aspectRatio: 2 / 3, badge: userDataBadgeFor(item), onTap: () => _openDetails(item));
                  }, childCount: _items.length),
                );
              }),
            ),
            SliverToBoxAdapter(child: _LoadMoreFooter(loading: _loadingMore, error: _loadMoreError, onRetry: () => _loadPage(generation: _generation))),
          ],
        ],
      ),
    );
  }

  int _columnsFor(double width) {
    if (width < 520) return 2;
    if (width < 760) return 3;
    if (width < 980) return 4;
    if (width < 1250) return 5;
    return 6;
  }

  void _openDetails(JellyfinLibraryItem item) {
    if (item.id.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailsScreen(client: widget.client, itemId: item.id, onPlayItem: widget.onPlayItem, onUserDataChanged: widget.onUserDataChanged)));
  }

  void _applyUserDataChange(JellyfinUserDataChange? change) {
    if (change == null) return;
    final next = <JellyfinLibraryItem>[];
    for (final item in _items) {
      final patched = item.withUserDataChange(change);
      final removeFavorite = _filter == JellyfinLibraryFilter.favorites && change.itemId == item.id && change.isFavorite == false;
      final removePlayed = _filter == JellyfinLibraryFilter.unplayed && change.itemId == item.id && change.played == true;
      if (!removeFavorite && !removePlayed) next.add(patched);
    }
    setState(() => _items = next);
  }

  String get _title => widget.kind == JellyfinLibraryKind.movies ? 'Movies' : 'TV Shows';
  String get _emptyName => widget.kind == JellyfinLibraryKind.movies ? 'movies' : 'shows';
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.kind, required this.total, required this.sort, required this.filter, required this.onSort, required this.onFilter, required this.onRefresh});
  final JellyfinLibraryKind kind;
  final int? total;
  final JellyfinLibrarySort sort;
  final JellyfinLibraryFilter filter;
  final ValueChanged<JellyfinLibrarySort> onSort;
  final ValueChanged<JellyfinLibraryFilter> onFilter;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final title = kind == JellyfinLibraryKind.movies ? 'Movies' : 'TV Shows';
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      final availableWidth = compact ? (constraints.maxWidth - 48).clamp(0, double.infinity).toDouble() : constraints.maxWidth;
      final controlWidth = compact ? availableWidth : 210.0;
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
          SizedBox(
            width: compact ? availableWidth : 180,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall),
              if (total != null) Text('$total titles', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          SizedBox(width: controlWidth, child: _Menu<JellyfinLibrarySort>(label: 'Sort', value: sort, values: JellyfinLibrarySort.values, titleOf: (value) => value.label, onChanged: onSort)),
          SizedBox(width: controlWidth, child: _Menu<JellyfinLibraryFilter>(label: 'Filter', value: filter, values: JellyfinLibraryFilter.values, titleOf: (value) => value.label, onChanged: onFilter)),
          IconButton(tooltip: 'Refresh', onPressed: onRefresh, icon: const Icon(Icons.refresh)),
        ]),
      );
    });
  }
}

class _Menu<T> extends StatelessWidget {
  const _Menu({required this.label, required this.value, required this.values, required this.titleOf, required this.onChanged});
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) titleOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButton<T>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        hint: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        selectedItemBuilder: (context) => values.map((item) => Align(alignment: Alignment.centerLeft, child: Text('$label: ${titleOf(item)}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
        items: values.map((item) => DropdownMenuItem<T>(value: item, child: Text('$label: ${titleOf(item)}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      );
}

class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: Colors.white38), const SizedBox(height: 16), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), if (action != null) ...[const SizedBox(height: 12), action!]]));
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.loading, required this.error, required this.onRetry});
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    if (error != null) return Padding(padding: const EdgeInsets.all(24), child: Center(child: TextButton(onPressed: onRetry, child: const Text('Retry loading more'))));
    return const SizedBox(height: 24);
  }
}
