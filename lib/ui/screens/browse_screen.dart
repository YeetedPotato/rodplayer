import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_badge.dart';
import 'package:rodplayer/ui/widgets/quick_actions_sheet.dart';
import 'package:rodplayer/ui/widgets/remux_logo.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({required this.client, this.onLogout = _defaultLogout, super.key});
  final RemuxClient client;
  final Future<void> Function() onLogout;
  static Future<void> _defaultLogout() async {}
  @override State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final ScrollController _scroll = ScrollController();
  late final Future<List<dynamic>> _nextUp;
  late final Future<List<dynamic>> _libraries;
  late final Future<List<dynamic>> _latestMovies;
  late final Future<List<dynamic>> _latestTvShows;
  final List<String> _posters = const ['https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg', 'https://image.tmdb.org/t/p/w500/1XDDXPXGI7p8DhvjniLyrzsyVSj.jpg'];
  final List<String> _tabs = const ['Home', 'Movies', 'TV Shows', 'Music', 'Live TV', 'Collections'];
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _nextUp = widget.client.getNextUp();
    _libraries = widget.client.getUserViews();
    _latestMovies = widget.client.getLatestMovies();
    _latestTvShows = widget.client.getLatestTvShows();
  }
  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  String _title(dynamic item, [String fallback = 'Untitled']) {
    if (item is! Map<String, dynamic>) return fallback;
    final value = item['Name'] ?? item['Title'];
    return value is String && value.trim().isNotEmpty ? value : fallback;
  }
  String? _imageUrl(dynamic item) {
    if (item is! Map<String, dynamic>) return null;
    final id = item['Id']; final images = item['ImageTags']; final tag = images is Map<String, dynamic> ? images['Primary'] : null;
    if (id is! String || id.isEmpty || tag is! String || tag.isEmpty) return null;
    return '${widget.client.baseUrl}/Items/$id/Images/Primary?tag=$tag&quality=90';
  }
  String? _backdropUrl(dynamic item) {
    if (item is! Map<String, dynamic>) return null;
    final id = item['Id'];
    return id is String && id.isNotEmpty ? '${widget.client.baseUrl}/Items/$id/Images/Backdrop' : null;
  }
  String _overview(dynamic item) {
    if (item is! Map<String, dynamic>) return 'A premium Jellyfin media experience with Remux playback intelligence.';
    final value = item['Overview'] ?? item['Tagline'];
    return value is String && value.trim().isNotEmpty ? value : 'A premium Jellyfin media experience with Remux playback intelligence.';
  }

  Widget _card(String title, int index, {double ratio = 2 / 3, String? imageUrl}) => GestureDetector(onLongPress: () => showQuickActionsSheet(context, title: title), child: FocusableMediaCard(title: title, subtitle: ratio > 1 ? 'Episode ${index + 1}' : 'Library', imageUrl: imageUrl ?? _posters[index % _posters.length], aspectRatio: ratio, mediaInfo: const MediaIntelligence(width: 3840, height: 2160, video: StreamIntelligence(type: 'Video', codec: 'hevc', videoRange: 'HDR10+'), audio: StreamIntelligence(type: 'Audio', codec: 'truehd', channels: 8, channelLayout: '7.1')), onTap: () => _showDetails(title)));
  Widget _shelf(String title, List<String> names, {double ratio = 2 / 3}) => SmartShelf(title: title, itemCount: names.length, aspectRatio: ratio, itemCountBadge: true, autofocusFirstItem: true, itemBuilder: (_, int index) => _card(names[index], index, ratio: ratio));
  Widget _dataShelf(String title, Future<List<dynamic>> future, {double ratio = 2 / 3}) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return _statusShelf(title, 'Loading…'); final items = snapshot.data ?? const <dynamic>[]; if (snapshot.hasError || items.isEmpty) return _statusShelf(title, 'Nothing here yet'); return SmartShelf(title: title, itemCount: items.length, aspectRatio: ratio, itemCountBadge: true, autofocusFirstItem: true, itemBuilder: (_, index) => _card(_title(items[index]), index, ratio: ratio, imageUrl: _imageUrl(items[index]))); });
  Widget _statusShelf(String title, String message) => Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), child: DecoratedBox(decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF333333))), child: Padding(padding: const EdgeInsets.all(20), child: Row(children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const Spacer(), Text(message, style: const TextStyle(color: Colors.white70))]))));

  Widget _hero(RemuxTheme theme) => FutureBuilder<List<dynamic>>(future: _nextUp.then((items) async => items.isNotEmpty ? items : _latestMovies), builder: (context, snapshot) { final item = snapshot.data?.isNotEmpty == true ? snapshot.data!.first : null; final title = item == null ? 'Featured collection' : _title(item); final backdrop = _backdropUrl(item); return SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 8), child: Container(height: 300, padding: const EdgeInsets.all(24), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: theme.obsidian, image: backdrop == null ? null : DecorationImage(image: NetworkImage(backdrop), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: .42), BlendMode.darken)), gradient: backdrop == null ? LinearGradient(colors: [theme.gold, theme.obsidian]) : null, boxShadow: theme.glassShadow), child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)), const SizedBox(height: 10), Text(_overview(item), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)), const SizedBox(height: 14), Row(children: [FilledButton.icon(onPressed: item == null ? null : () => _showDetails(title), icon: const Icon(Icons.play_arrow), label: const Text('Play')), const SizedBox(width: 8), OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.shuffle), label: const Text('Surprise Me'))])])))); });
  void _showSearch() => showSearch<void>(context: context, delegate: _MediaSearchDelegate(widget.client));
  void _showSettings() => showModalBottomSheet<void>(context: context, backgroundColor: Theme.of(context).colorScheme.surface, builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: [const ListTile(title: Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))), const ListTile(leading: Icon(Icons.play_circle_outline), title: Text('Playback')), const ListTile(leading: Icon(Icons.tune), title: Text('Appearance')), const ListTile(leading: Icon(Icons.info_outline), title: Text('Server Info'))])));
  void _showDetails(String title) => showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => Container(height: MediaQuery.sizeOf(context).height * .78, padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFF0D0F12), borderRadius: BorderRadius.vertical(top: Radius.circular(24))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Spacer(), Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('A premium Jellyfin media experience with Remux playback intelligence.', style: TextStyle(color: Colors.white70)), const SizedBox(height: 16), MediaBadges(labels: const ['4K', 'HDR10+', 'DV', 'Atmos']), const SizedBox(height: 18), Row(children: [FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.play_arrow), label: const Text('Play')), IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)), IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz))]), const Text('Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 8), const Text('Continue watching, explore seasons, cast and crew, or inspect direct-play compatibility from this detail surface.', style: TextStyle(color: Colors.white70)), const Spacer()])));

  @override
  Widget build(BuildContext context) {
    final RemuxTheme theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return PopScope(canPop: true, child: Scaffold(backgroundColor: theme.obsidian, drawer: Drawer(backgroundColor: theme.surface2, child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [const RemuxLogo(size: 44, glow: true), const SizedBox(height: 20), for (final String item in ['Home', 'Libraries', 'Settings', 'Server Info']) ListTile(leading: Icon(item == 'Home' ? Icons.home_outlined : Icons.folder_outlined), title: Text(item), onTap: () => Navigator.pop(context)), ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: widget.onLogout)]))), body: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: CustomScrollView(controller: _scroll, slivers: [SliverAppBar(pinned: true, backgroundColor: theme.obsidianGlassStrong, surfaceTintColor: Colors.transparent, leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer())), title: const Row(children: [RemuxLogo(size: 30, glow: true), SizedBox(width: 10), Text('Remux')]), actions: [IconButton(onPressed: _showSearch, tooltip: 'Search', icon: const Icon(Icons.search)), IconButton(onPressed: _showSettings, tooltip: 'Settings', icon: const Icon(Icons.settings_outlined)), const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: CircleAvatar(child: Text('R')))], bottom: PreferredSize(preferredSize: const Size.fromHeight(48), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (int index = 0; index < _tabs.length; index++) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(_tabs[index]), selected: _tab == index, onSelected: (_) => setState(() => _tab = index)))])))), _hero(theme), SliverToBoxAdapter(child: _dataShelf('My Media', _libraries, ratio: 1)), SliverToBoxAdapter(child: _shelf('Continue Watching', ['The Last Voyage', 'Shoreline', 'Night Shift'], ratio: 16 / 9)), SliverToBoxAdapter(child: _dataShelf('Next Up', _nextUp, ratio: 16 / 9)), SliverToBoxAdapter(child: _dataShelf('Latest Movies', _latestMovies)), SliverToBoxAdapter(child: _dataShelf('Latest TV Shows', _latestTvShows)), const SliverPadding(padding: EdgeInsets.only(bottom: 40))]))));
  }
}

class _MediaSearchDelegate extends SearchDelegate<void> {
  _MediaSearchDelegate(this.client);
  final RemuxClient client;
  @override List<Widget>? buildActions(BuildContext context) => [if (query.isNotEmpty) IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override Widget? buildLeading(BuildContext context) => IconButton(onPressed: () => close(context, null), icon: const Icon(Icons.arrow_back));
  @override Widget buildResults(BuildContext context) => FutureBuilder<List<dynamic>>(future: client.search(query), builder: (context, snapshot) { final items = snapshot.data ?? const <dynamic>[]; if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator()); if (items.isEmpty) return const Center(child: Text('No results')); return ListView.builder(itemCount: items.length, itemBuilder: (_, index) { final item = items[index]; final map = item is Map<String, dynamic> ? item : const <String, dynamic>{}; return ListTile(title: Text((map['Name'] ?? map['Title'] ?? 'Untitled').toString()), subtitle: Text((map['Type'] ?? '').toString())); }); });
  @override Widget buildSuggestions(BuildContext context) => const Center(child: Text('Search your library'));
}
