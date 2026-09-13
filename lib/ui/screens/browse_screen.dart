import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/screens/search_screen.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({required this.client, this.onLogout = _defaultLogout, super.key});
  final RemuxClient client;
  final Future<void> Function() onLogout;
  static Future<void> _defaultLogout() async {}
  @override State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late final Future<List<dynamic>> _resumeItems = widget.client.getResumeItems();
  late final Future<List<dynamic>> _nextUp = widget.client.getNextUp();

  String _title(dynamic item) => item is Map<String, dynamic> && item['Name'] is String ? item['Name'] as String : 'Untitled';
  String? _image(dynamic item) { if (item is! Map<String, dynamic>) return null; final id = item['Id']; final tags = item['ImageTags']; final tag = tags is Map<String, dynamic> ? tags['Primary'] : null; if (id is! String || tag is! String) return null; return '${widget.client.baseUrl}/Items/$id/Images/Primary?tag=$tag&quality=90'; }
  Widget _feed(String title, Future<List<dynamic>> future) => FutureBuilder<List<dynamic>>(future: future, builder: (context, snapshot) { if (snapshot.connectionState == ConnectionState.waiting) return _status(title, 'Loading…'); if (snapshot.hasError) return _status(title, 'Unable to load this shelf'); final items = snapshot.data ?? const <dynamic>[]; if (items.isEmpty) return _status(title, 'Nothing here yet'); return SmartShelf(title: title, itemCount: items.length, aspectRatio: 16 / 9, itemCountBadge: true, autofocusFirstItem: true, itemBuilder: (context, index) { final item = items[index]; final id = item is Map<String, dynamic> && item['Id'] is String ? item['Id'] as String : null; return FocusableMediaCard(title: _title(item), subtitle: title, imageUrl: _image(item), aspectRatio: 16 / 9, onTap: () => _showDetails(_title(item), id)); }); });
  Widget _status(String title, String message) => Padding(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), child: Row(children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const Spacer(), Text(message, style: const TextStyle(color: Colors.white70))]));
  void _showDetails(String title, String? itemId) => showModalBottomSheet<void>(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), const SizedBox(height: 16), FilledButton.icon(onPressed: itemId == null ? null : () => _play(itemId), icon: const Icon(Icons.play_arrow), label: const Text('Play'))]))));
  void _play(String itemId) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playing item $itemId')));
  @override Widget build(BuildContext context) { final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme(); return Scaffold(backgroundColor: theme.obsidian, appBar: AppBar(title: const Text('Remux'), actions: [IconButton(tooltip: 'Search', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SearchScreen(client: widget.client))), icon: const Icon(Icons.search)), IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout))]), body: ListView(children: [_feed('Continue Watching', _resumeItems), _feed('Next Up', _nextUp)])); }
}
