import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/jellyfin_api_client.dart';
import 'package:rodplayer/core/models/jellyfin_library_item.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/player/player_route.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({required this.client, this.onLogout = _defaultLogout, super.key});
  final JellyfinApiClient client;
  final Future<void> Function() onLogout;
  static Future<void> _defaultLogout() async {}
  @override State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final Future<List<ResumableItem>> _resumeItems = widget.client.getResumeItems();
  late final Future<List<NextUpItem>> _nextUp = widget.client.getNextUp();

  Widget _feed<T extends JellyfinLibraryItem>(String title, Future<List<T>> future) => FutureBuilder<List<T>>(future: future, builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return _status(title, 'Loading…'); if (snapshot.hasError) return _status(title, 'Unable to load this shelf'); final items = snapshot.data ?? const <T>[]; if (items.isEmpty) return _status(title, 'Nothing here yet'); return SmartShelf(title: title, itemCount: items.length, aspectRatio: 16 / 9, itemCountBadge: true, autofocusFirstItem: true, itemBuilder: (context, index) { final item = items[index]; return FocusableMediaCard(title: item.title.isEmpty ? 'Untitled' : item.title, subtitle: title, imageUrl: item.imageUrl(widget.client.baseUrl), aspectRatio: 16 / 9, onTap: () => _showDetails(item.title.isEmpty ? 'Untitled' : item.title, item.id.isEmpty ? null : item.id)); }); });
  Widget _status(String title, String message) => Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), child: Row(children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const Spacer(), Text(message, style: const TextStyle(color: Colors.white70))]));
  void _showDetails(String title, String? itemId) => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 16), FilledButton.icon(onPressed: itemId == null ? null : () => _play(itemId), icon: const Icon(Icons.play_arrow), label: const Text('Play'))]))));
  void _play(String itemId) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerRoute(client: widget.client, itemId: itemId)));
  }
  @override Widget build(BuildContext context) { final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme(); return Scaffold(backgroundColor: theme.obsidian, appBar: AppBar(title: const Text('RodPlayer'), actions: [IconButton(tooltip: 'Search', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchScreen(client: widget.client))), icon: const Icon(Icons.search)), IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout))]), body: ListView(children: [_feed('Continue Watching', _resumeItems), _feed('Next Up', _nextUp)])); }
}
