import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({required this.client, this.embedded = false, this.focusNode, this.autofocus = true, super.key});
  final JellyfinApiClient client;
  final bool embedded;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  late final FocusNode _focusNode;
  bool get _ownsFocusNode => widget.focusNode == null;
  Timer? _debounce;
  List<JellyfinSearchHint> _results = const [];
  List<String> _recent = const [];
  String _query = '';
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final preferences = await SharedPreferences.getInstance();
    if (mounted) setState(() => _recent = preferences.getStringList('rodplayer_recent_searches') ?? const []);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() { _query = ''; _results = const []; _error = null; _loading = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (!mounted) return;
    setState(() { _query = query; _loading = true; _error = null; });
    try {
      final results = await widget.client.search(query: query);
      if (!mounted || _query != query) return;
      await _saveRecent(query);
      setState(() { _results = results; _loading = false; });
    } catch (error) {
      if (mounted && _query == query) setState(() { _loading = false; _error = error; });
    }
  }

  Future<void> _saveRecent(String query) async {
    final updated = [query, ..._recent.where((item) => item.toLowerCase() != query.toLowerCase())].take(6).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList('rodplayer_recent_searches', updated);
    if (mounted) setState(() => _recent = updated);
  }

  String _title(JellyfinSearchHint item) => item.title.isEmpty ? 'Untitled' : item.title;

  @override
  void dispose() { _debounce?.cancel(); _controller.dispose(); if (_ownsFocusNode) _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1200 ? 6 : width >= 850 ? 4 : width >= 560 ? 3 : 2;
    final content = CustomScrollView(key: const PageStorageKey<String>('search-scroll'), slivers: [
        SliverPadding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 12), sliver: SliverToBoxAdapter(child: TextField(
          controller: _controller, focusNode: _focusNode, autofocus: widget.autofocus, textInputAction: TextInputAction.search,
          onChanged: _onChanged, onSubmitted: (value) { _debounce?.cancel(); if (value.trim().isNotEmpty) _search(value.trim()); },
          decoration: InputDecoration(hintText: 'Search movies, shows, and music...', prefixIcon: const Icon(Icons.search), suffixIcon: _controller.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { _controller.clear(); _onChanged(''); setState(() {}); })),
        ))),
        if (_loading) const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
        else if (_error != null) SliverFillRemaining(hasScrollBody: false, child: _Message(icon: Icons.cloud_off_outlined, title: 'Search unavailable', detail: 'Check your RodPlayer connection and try again.'))
        else if (_query.isEmpty) SliverFillRemaining(hasScrollBody: false, child: _RecentSearches(items: _recent, onSelect: (value) { _controller.text = value; _search(value); }))
        else if (_results.isEmpty) SliverFillRemaining(hasScrollBody: false, child: _Message(icon: Icons.search_off, title: 'No results', detail: 'Try a different title, artist, or keyword.'))
        else SliverPadding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 32), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((context, index) { final item = _results[index]; return FocusableMediaCard(title: _title(item), subtitle: item.subtitle(), imageUrl: item.imageUrl(widget.client.baseUrl), onTap: () => _showDetails(item)); }, childCount: _results.length), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: 16, mainAxisSpacing: 18, childAspectRatio: .68))),
      ]);
    if (widget.embedded) return ColoredBox(color: theme.obsidian, child: content);
    return Scaffold(backgroundColor: theme.obsidian, appBar: AppBar(title: const Text('Search'), centerTitle: false), body: content);
  }

  void _showDetails(JellyfinSearchHint item) { final id = item.id.isEmpty ? null : item.id; showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_title(item), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text(item.subtitle()), const SizedBox(height: 20), FilledButton.icon(onPressed: id == null ? null : () => Navigator.pop(context), icon: const Icon(Icons.play_arrow), label: const Text('Play'))])))); }
}

class _Message extends StatelessWidget { const _Message({required this.icon, required this.title, required this.detail}); final IconData icon; final String title, detail; @override Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 52, color: Colors.white38), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const SizedBox(height: 8), Text(detail, style: const TextStyle(color: Colors.white60))])); }
class _RecentSearches extends StatelessWidget { const _RecentSearches({required this.items, required this.onSelect}); final List<String> items; final ValueChanged<String> onSelect; @override Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.manage_search, size: 56, color: Colors.white38), const SizedBox(height: 16), const Text('Search movies, shows, and music...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), if (items.isNotEmpty) ...[const SizedBox(height: 24), const Text('Recent searches', style: TextStyle(color: Colors.white60)), const SizedBox(height: 8), Wrap(spacing: 8, children: items.map((item) => ActionChip(label: Text(item), onPressed: () => onSelect(item))).toList())]])); }
