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
  final List<String> _posters = const [
    'https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
    'https://image.tmdb.org/t/p/w500/1XDDXPXGI7p8DhvjniLyrzsyVSj.jpg',
  ];
  final List<String> _tabs = const ['Home', 'Movies', 'TV Shows', 'Music', 'Live TV', 'Collections'];
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.client.getItems().catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to load library: $error')));
      }
      return <dynamic>[];
    });
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Widget _card(String title, int index, {double ratio = 2 / 3}) => GestureDetector(
    onLongPress: () => showQuickActionsSheet(context, title: title),
    child: FocusableMediaCard(
      title: title,
      subtitle: ratio > 1 ? 'Episode ${index + 1}  •  42%' : '2026  •  Movie',
      imageUrl: _posters[index % _posters.length],
      aspectRatio: ratio,
      mediaInfo: const MediaIntelligence(
        width: 3840, height: 2160,
        video: StreamIntelligence(type: 'Video', codec: 'hevc', videoRange: 'HDR10+'),
        audio: StreamIntelligence(type: 'Audio', codec: 'truehd', channels: 8, channelLayout: '7.1'),
      ),
      onTap: () => _showDetails(title),
    ),
  );

  Widget _shelf(String title, List<String> names, {double ratio = 2 / 3}) => SmartShelf(
    title: title, itemCount: names.length, aspectRatio: ratio, itemCountBadge: true,
    autofocusFirstItem: true, itemBuilder: (_, int index) => _card(names[index], index, ratio: ratio),
  );

  void _showDetails(String title) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.sizeOf(context).height * .78, padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Color(0xFF0D0F12), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Spacer(), Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8), const Text('A premium Jellyfin media experience with Remux playback intelligence.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16), MediaBadges(labels: const ['4K', 'HDR10+', 'DV', 'Atmos']),
          const SizedBox(height: 18), Row(children: [
            FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.play_arrow), label: const Text('Play')),
            IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)), IconButton(onPressed: () {}, icon: const Icon(Icons.more_horiz)),
          ]),
          const Text('Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 8),
          const Text('Continue watching, explore seasons, cast and crew, or inspect direct-play compatibility from this detail surface.', style: TextStyle(color: Colors.white70)), const Spacer(),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RemuxTheme theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return PopScope(canPop: true, child: Scaffold(
      backgroundColor: theme.obsidian,
      drawer: Drawer(backgroundColor: theme.surface2, child: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        const RemuxLogo(size: 44, glow: true), const SizedBox(height: 20),
        for (final String item in ['Home', 'Libraries', 'Settings', 'Server Info'])
          ListTile(leading: Icon(item == 'Home' ? Icons.home_outlined : Icons.folder_outlined), title: Text(item), onTap: () => Navigator.pop(context)),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: widget.onLogout),
      ]))),
      body: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: CustomScrollView(controller: _scroll, slivers: [
        SliverAppBar(
          pinned: true, backgroundColor: theme.obsidianGlassStrong, surfaceTintColor: Colors.transparent,
          leading: Builder(builder: (BuildContext context) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(context).openDrawer())),
          title: const Row(children: [RemuxLogo(size: 30, glow: true), SizedBox(width: 10), Text('Remux')]),
          actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.search)), IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined)), const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: CircleAvatar(child: Text('R')))],
          bottom: PreferredSize(preferredSize: const Size.fromHeight(48), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (int index = 0; index < _tabs.length; index++) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(_tabs[index]), selected: _tab == index, onSelected: (_) => setState(() => _tab = index))),
          ]))),
        ),
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(24, 24, 24, 8), child: Container(
          height: 300, padding: const EdgeInsets.all(24), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(colors: [theme.green, theme.surface2]), boxShadow: theme.glassShadow),
          child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Featured collection', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)), const SizedBox(height: 10), MediaBadges(labels: const ['4K', 'HDR10+', 'Atmos', 'HEVC']), const SizedBox(height: 14),
            Row(children: [
              FilledButton.icon(onPressed: null, icon: const Icon(Icons.play_arrow), label: const Text('Play')), const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.shuffle), label: const Text('Surprise Me')),
            ]),
          ]),
        ))),
        SliverToBoxAdapter(child: _shelf('My Media', ['Movies', 'TV Shows', 'Music', 'Live TV'], ratio: 1)),
        SliverToBoxAdapter(child: _shelf('Continue Watching', ['The Last Voyage', 'Shoreline', 'Night Shift'], ratio: 16 / 9)),
        SliverToBoxAdapter(child: _shelf('Next Up', ['The Crossing', 'Signal Fire', 'Afterlight'], ratio: 16 / 9)),
        SliverToBoxAdapter(child: _shelf('Latest Movies', ['The Archive', 'Horizon', 'Northbound'])),
        SliverToBoxAdapter(child: _shelf('Latest TV Shows', ['Dark Harbor', 'The Bureau', 'Open Water'])),
        const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
      ])),
    ));
  }
}
