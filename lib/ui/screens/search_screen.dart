import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/screens/item_details_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_item_helpers.dart';
import 'package:rodplayer/ui/widgets/user_data_badge.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({required this.client, this.embedded = false, this.focusNode, this.autofocus = true, this.onUserDataChanged, this.latestUserDataChange, this.userDataRevision = 0, super.key});
  final JellyfinApiClient client;
  final bool embedded;
  final FocusNode? focusNode;
  final bool autofocus;
  final JellyfinUserDataChangedCallback? onUserDataChanged;
  final JellyfinUserDataChange? latestUserDataChange;
  final int userDataRevision;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _pageSize = 48;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final FocusNode _focusNode;
  bool get _ownsFocusNode => widget.focusNode == null;
  Timer? _debounce;
  var _searchType = JellyfinSearchType.all;
  var _discoveryKind = JellyfinDiscoveryKind.movies;
  var _discoverySort = JellyfinDiscoverySort.topRated;
  String? _genre;
  var _genres = const <String>[];
  var _recent = const <String>[];
  var _items = <JellyfinLibraryItem>[];
  final _ids = <String>{};
  String _query = '';
  Object? _initialError;
  Object? _loadMoreError;
  Object? _genresError;
  int _nextStartIndex = 0;
  int _generation = 0;
  int _genreGeneration = 0;
  int _recentGeneration = 0;
  Future<void> _recentWrite = Future<void>.value();
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _loadingGenres = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _scrollController.addListener(_maybeLoadMore);
    unawaited(_loadRecent());
    _loadGenres();
    _reload();
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _genre = null;
      _loadGenres();
      _reload();
    } else if (oldWidget.userDataRevision != widget.userDataRevision) {
      _applyUserDataChange(widget.latestUserDataChange);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final generation = _recentGeneration;
    final preferences = await SharedPreferences.getInstance();
    if (mounted && generation == _recentGeneration) setState(() => _recent = preferences.getStringList('rodplayer_recent_searches') ?? const <String>[]);
  }

  void _loadGenres() {
    final generation = ++_genreGeneration;
    setState(() {
      _loadingGenres = true;
      _genresError = null;
    });
    unawaited(() async {
      try {
        final genres = await widget.client.getGenres();
        if (!mounted || generation != _genreGeneration) return;
        setState(() {
          _genres = genres;
          if (_genre != null && !genres.contains(_genre)) _genre = null;
          _loadingGenres = false;
        });
      } catch (error) {
        if (!mounted || generation != _genreGeneration) return;
        setState(() {
          _genresError = error;
          _genres = const <String>[];
          _genre = null;
          _loadingGenres = false;
        });
      }
    }());
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _query = query;
      _reload();
    });
    if (query.isEmpty && _query.isNotEmpty) {
      _query = '';
      _reload();
    }
  }

  void _submit(String value) {
    _debounce?.cancel();
    _query = value.trim();
    _reload();
  }

  Future<void> _saveRecent(String query) async {
    if (query.isEmpty) return;
    _recentGeneration++;
    final updated = [query, ..._recent.where((item) => item.toLowerCase() != query.toLowerCase())].take(6).toList();
    if (mounted) setState(() => _recent = updated);

    final previousWrite = _recentWrite;
    final write = () async {
      try {
        await previousWrite;
      } catch (_) {}
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList('rodplayer_recent_searches', updated);
    }();

    _recentWrite = write;
    await write;
  }

  void _selectRecent(String value) {
    _controller.text = value;
    _query = value.trim();
    _reload();
  }

  void _reload() {
    final generation = ++_generation;
    _ids.clear();
    setState(() {
      _items = const <JellyfinLibraryItem>[];
      _initialError = null;
      _loadMoreError = null;
      _nextStartIndex = 0;
      _loadingInitial = true;
      _loadingMore = false;
      _hasMore = true;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    unawaited(_loadPage(initial: true, generation: generation));
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients || _loadingInitial || _loadingMore || !_hasMore || _loadMoreError != null) return;
    if (_scrollController.position.extentAfter < 700) unawaited(_loadPage(generation: _generation));
  }

  Future<void> _loadPage({bool initial = false, required int generation}) async {
    if (!initial && (_loadingMore || !_hasMore)) return;
    final startIndex = initial ? 0 : _nextStartIndex;
    if (!initial) setState(() => _loadingMore = true);
    try {
      final page = _query.isEmpty
          ? await widget.client.getDiscoveryItemsPage(kind: _discoveryKind, sort: _discoverySort, genre: _genre, startIndex: startIndex, limit: _pageSize)
          : await widget.client.getSearchItemsPage(query: _query, type: _searchType, genre: _genre, startIndex: startIndex, limit: _pageSize);
      if (!mounted || generation != _generation) return;
      final nextItems = initial ? <JellyfinLibraryItem>[] : List<JellyfinLibraryItem>.of(_items);
      if (initial) _ids.clear();
      for (final item in page.items) {
        if (item.id.isEmpty || _ids.add(item.id)) nextItems.add(item);
      }
      final consumedStart = page.startIndex ?? startIndex;
      final consumedNext = consumedStart + page.items.length;
      if (_query.isNotEmpty) unawaited(_saveRecent(_query));
      setState(() {
        _items = nextItems;
        _initialError = null;
        _loadMoreError = null;
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
    final content = ColoredBox(
      color: theme.obsidian,
      child: CustomScrollView(
        key: const PageStorageKey<String>('search-scroll'),
        controller: _scrollController,
        slivers: [
          SliverPadding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 10), sliver: SliverToBoxAdapter(child: _SearchField(controller: _controller, focusNode: _focusNode, autofocus: widget.autofocus, onChanged: _onChanged, onSubmitted: _submit, onClear: () { _controller.clear(); _query = ''; _reload(); }))),
          SliverPadding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 12), sliver: SliverToBoxAdapter(child: _Controls(query: _query, searchType: _searchType, discoveryKind: _discoveryKind, discoverySort: _discoverySort, genre: _genre, genres: _genres, loadingGenres: _loadingGenres, genresError: _genresError, recent: _recent, onRecent: _selectRecent, onRetryGenres: _loadGenres, onSearchType: (value) { _searchType = value; if (_query.isNotEmpty) _reload(); }, onDiscoveryKind: (value) { _discoveryKind = value; if (_query.isEmpty) _reload(); }, onDiscoverySort: (value) { _discoverySort = value; if (_query.isEmpty) _reload(); }, onGenre: (value) { _genre = value; _reload(); }))),
          if (_loadingInitial)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
          else if (_initialError != null)
            SliverFillRemaining(hasScrollBody: false, child: _Message(icon: Icons.cloud_off_outlined, title: _query.isEmpty ? 'Discover unavailable' : 'Search unavailable', action: TextButton(onPressed: _reload, child: const Text('Retry'))))
          else if (_items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _Message(icon: _query.isEmpty ? Icons.explore_outlined : Icons.search_off, title: _query.isEmpty ? 'No discovery results' : 'No results'))
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              sliver: SliverLayoutBuilder(builder: (context, constraints) {
                final columns = _columnsFor(constraints.crossAxisExtent);
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, childAspectRatio: .64, crossAxisSpacing: 16, mainAxisSpacing: 18),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = _items[index];
                    return FocusableMediaCard(title: mediaItemTitle(item), subtitle: item.subtitle(), imageUrl: item.imageUrl(widget.client.baseUrl), aspectRatio: item.kind == JellyfinItemKind.episode ? 16 / 9 : 2 / 3, badge: userDataBadgeFor(item), onTap: () => _openDetails(item));
                  }, childCount: _items.length),
                );
              }),
            ),
            SliverToBoxAdapter(child: _LoadMoreFooter(loading: _loadingMore, error: _loadMoreError, onRetry: () => unawaited(_loadPage(generation: _generation)))),
          ],
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(backgroundColor: theme.obsidian, appBar: AppBar(title: const Text('Search'), centerTitle: false), body: content);
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemDetailsScreen(client: widget.client, itemId: item.id, onUserDataChanged: widget.onUserDataChanged)));
  }

  void _applyUserDataChange(JellyfinUserDataChange? change) {
    if (change == null) return;
    setState(() => _items = _items.map((item) => item.withUserDataChange(change)).toList(growable: false));
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.autofocus, required this.onChanged, required this.onSubmitted, required this.onClear});
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(hintText: 'Search movies, shows, episodes, and music...', prefixIcon: const Icon(Icons.search), suffixIcon: controller.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: onClear)),
      );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.query, required this.searchType, required this.discoveryKind, required this.discoverySort, required this.genre, required this.genres, required this.loadingGenres, required this.genresError, required this.recent, required this.onRecent, required this.onRetryGenres, required this.onSearchType, required this.onDiscoveryKind, required this.onDiscoverySort, required this.onGenre});
  final String query;
  final JellyfinSearchType searchType;
  final JellyfinDiscoveryKind discoveryKind;
  final JellyfinDiscoverySort discoverySort;
  final String? genre;
  final List<String> genres;
  final bool loadingGenres;
  final Object? genresError;
  final List<String> recent;
  final ValueChanged<String> onRecent;
  final VoidCallback onRetryGenres;
  final ValueChanged<JellyfinSearchType> onSearchType;
  final ValueChanged<JellyfinDiscoveryKind> onDiscoveryKind;
  final ValueChanged<JellyfinDiscoverySort> onDiscoverySort;
  final ValueChanged<String?> onGenre;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    final controlWidth = compact ? double.infinity : 220.0;
    final children = <Widget>[
      if (query.isEmpty) Text('Discover', style: Theme.of(context).textTheme.titleLarge),
      if (query.isEmpty && recent.isNotEmpty) _RecentSearches(items: recent, onSelect: onRecent),
      if (query.isEmpty) _ChoiceRow<JellyfinDiscoveryKind>(values: JellyfinDiscoveryKind.values, selected: discoveryKind, labelOf: (value) => value.label, onSelected: onDiscoveryKind),
      if (query.isEmpty) _Menu<JellyfinDiscoverySort>(label: 'Sort', width: controlWidth, value: discoverySort, values: JellyfinDiscoverySort.values, titleOf: (value) => value.label, onChanged: onDiscoverySort),
      if (query.isNotEmpty) _ChoiceRow<JellyfinSearchType>(values: JellyfinSearchType.values, selected: searchType, labelOf: (value) => value.label, onSelected: onSearchType),
      _GenreControl(width: controlWidth, genre: genre, genres: genres, loading: loadingGenres, error: genresError, onRetry: onRetryGenres, onChanged: onGenre),
    ];
    return Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({required this.values, required this.selected, required this.labelOf, required this.onSelected});
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: values.map((value) => ChoiceChip(label: Text(labelOf(value), overflow: TextOverflow.ellipsis), selected: value == selected, onSelected: (_) => onSelected(value))).toList());
}

class _GenreControl extends StatelessWidget {
  const _GenreControl({required this.width, required this.genre, required this.genres, required this.loading, required this.error, required this.onRetry, required this.onChanged});
  final double width;
  final String? genre;
  final List<String> genres;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2));
    if (error != null) return TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Genres'));
    return _Menu<String?>(label: 'Genre', width: width, value: genre, values: <String?>[null, ...genres], titleOf: (value) => value ?? 'All Genres', onChanged: onChanged);
  }
}

class _Menu<T> extends StatelessWidget {
  const _Menu({required this.label, required this.width, required this.value, required this.values, required this.titleOf, required this.onChanged});
  final String label;
  final double width;
  final T value;
  final List<T> values;
  final String Function(T) titleOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: values.map((item) => DropdownMenuItem<T>(value: item, child: Text('$label: ${titleOf(item)}', maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (value) {
            if (value != null || null is T) onChanged(value as T);
          },
        ),
      );
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.items, required this.onSelect});
  final List<String> items;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: items.map((item) => ActionChip(label: Text(item), onPressed: () => onSelect(item))).toList());
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.action});
  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: Colors.white38), const SizedBox(height: 16), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), if (action != null) ...[const SizedBox(height: 12), action!]])));
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
    return const SizedBox(height: 28);
  }
}
