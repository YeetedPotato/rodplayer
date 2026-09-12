import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_bar.dart';
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
  final _scrollController = ScrollController();
  static const _posters = ['https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg', 'https://image.tmdb.org/t/p/w500/1XDDXPXGI7p8DhvjniLyrzsyVSj.jpg'];

  @override
  void initState() {
    super.initState();
    widget.client.getItems().then<void>((_) {}, onError: (Object error, StackTrace stackTrace) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to load library: $error'))); });
  }
  @override void dispose() { _scrollController.dispose(); super.dispose(); }

  Widget _card(String title, int i, {double aspectRatio = 2 / 3}) => FocusableMediaCard(title: title, subtitle: aspectRatio > 1 ? '${(i + 1) * 12}% watched' : 'Movie', imageUrl: _posters[i % _posters.length], aspectRatio: aspectRatio, mediaInfo: const MediaIntelligence(width: 1920, height: 1080, video: StreamIntelligence(type: 'Video', codec: 'hevc', videoRange: 'HDR10'), audio: StreamIntelligence(type: 'Audio', codec: 'truehd', channels: 8, channelLayout: '7.1')), onTap: () {});
  Widget _shelf(String title, List<String> items, {double aspectRatio = 2 / 3}) => SmartShelf(title: title, itemCount: items.length, aspectRatio: aspectRatio, itemCountBadge: true, autofocusFirstItem: true, itemBuilder: (context, index) => _card(items[index], index, aspectRatio: aspectRatio));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return PopScope(canPop: true, child: Scaffold(backgroundColor: theme.obsidian, body: FocusTraversalGroup(policy: OrderedTraversalPolicy(), child: CustomScrollView(controller: _scrollController, slivers: [
      SliverAppBar(pinned: true, expandedHeight: 128, backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: theme.glassBlur, sigmaY: theme.glassBlur), child: DecoratedBox(decoration: BoxDecoration(color: theme.surface3.withValues(alpha: 0.86), border: Border(bottom: BorderSide(color: theme.borderColor()))), child: FlexibleSpaceBar(titlePadding: const EdgeInsetsDirectional.only(start: 24, bottom: 16), title: const Text('Browse'), background: Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 52), child: Row(children: const [RemuxLogo(size: 34, glow: true), SizedBox(width: 10), Text('Remux', style: TextStyle(color: Color(0xFFEBCF52), fontWeight: FontWeight.w700)), Spacer(), Icon(Icons.circle, size: 8, color: Color(0xFFEBCF52))])))))), actions: [IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout), tooltip: 'Log out / switch server')]),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: ClipRRect(borderRadius: BorderRadius.circular(theme.radiusLarge), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: theme.glassBlur, sigmaY: theme.glassBlur), child: Container(height: 280, decoration: BoxDecoration(color: theme.surface2.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(theme.radiusLarge), border: Border.all(color: theme.borderColor()), boxShadow: theme.glassShadow), child: Stack(fit: StackFit.expand, children: [DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [theme.surface1, theme.surface3]))), const Positioned(left: 24, bottom: 24, child: Text('Featured collection', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))), const Positioned(top: 16, right: 16, child: MediaBar())])))))),
      SliverToBoxAdapter(child: _shelf('Continue Watching', ['The Last Voyage', 'Shoreline', 'Night Shift'], aspectRatio: 16 / 9)),
      SliverToBoxAdapter(child: _shelf('Next Up', ['The Archive', 'Horizon', 'The Long Road', 'Northbound'])),
      SliverToBoxAdapter(child: _shelf('Top Picks', ['Afterlight', 'Signal Fire', 'Open Water', 'The Crossing'])),
      const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
    ]))));
  }
}
