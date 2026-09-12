import 'package:flutter/material.dart';
import 'package:rodplayer/core/api/remux_client.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
import 'package:rodplayer/ui/widgets/focusable_media_card.dart';
import 'package:rodplayer/ui/widgets/media_bar.dart';
import 'package:rodplayer/ui/widgets/smart_shelf.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({required this.client, super.key});

  final RemuxClient client;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _scrollController = ScrollController();
  static const _posters = <String>[
    'https://image.tmdb.org/t/p/w500/8cdWjvZQUExUUTzyp4t6EDMubfO.jpg',
    'https://image.tmdb.org/t/p/w500/1XDDXPXGI7p8DhvjniLyrzsyVSj.jpg',
    'https://image.tmdb.org/t/p/w500/qhb1qOilapbapxWQn9jtRCMwXJF.jpg',
    'https://image.tmdb.org/t/p/w500/9f6z1QJ7H0K7S0xP6YxX5xS5j3K.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _loadBrowseItems();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBrowseItems() async {
    try {
      await widget.client.getItems();
    } on Object catch (error) {
      if (mounted) _showBrowseError(error);
    }
  }

  void _showBrowseError(Object error) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    final message = switch (error) {
      RemuxAuthException(:final message) => message,
      RemuxConnectionException(:final message) => message,
      _ => 'Unable to load browse items: $error',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: theme.textPrimary)),
          backgroundColor: theme.obsidianRaised,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radiusMedium),
            side: BorderSide(color: theme.goldBright.withValues(alpha: 0.38)),
          ),
        ),
      );
  }

  Widget _card(String title, int index, {double aspectRatio = 2 / 3}) {
    return FocusableMediaCard(
      title: title,
      subtitle: aspectRatio > 1 ? '${(index + 1) * 12}% watched' : 'Movie',
      imageUrl: _posters[index % _posters.length],
      aspectRatio: aspectRatio,
      mediaInfo: MediaIntelligence(
        width: aspectRatio > 1 ? 1920 : 3840,
        height: aspectRatio > 1 ? 1080 : 2160,
        video: const StreamIntelligence(
          type: 'Video',
          codec: 'hevc',
          videoRange: 'HDR10',
        ),
        audio: const StreamIntelligence(
          type: 'Audio',
          codec: 'truehd',
          channels: 8,
          channelLayout: '7.1',
        ),
      ),
      onTap: () {},
    );
  }

  Widget _shelf(String title, List<String> titles, {double aspectRatio = 2 / 3}) {
    return SmartShelf(
      title: title,
      itemCount: titles.length,
      aspectRatio: aspectRatio,
      itemCountBadge: true,
      autofocusFirstItem: true,
      itemBuilder: (context, index) => _card(
        titles[index],
        index,
        aspectRatio: aspectRatio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: theme.obsidian,
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 128,
                backgroundColor: theme.obsidianGlassStrong,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsetsDirectional.only(start: 24, bottom: 16),
                  title: Text(
                    'Browse',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  background: DecoratedBox(
                    decoration: BoxDecoration(color: theme.obsidianGlassStrong),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 52),
                      child: Row(
                        children: [
                          Text(
                            'ELEGANTFIN',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: theme.goldBright,
                              letterSpacing: 2.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          _StatusBadge(theme: theme),
                          const SizedBox(width: 12),
                          Icon(Icons.person_outline, color: theme.textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.search),
                    tooltip: 'Search',
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: SizedBox(
                    height: 280,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(theme.radiusLarge),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [theme.obsidianRaised, theme.obsidianGlass],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 24,
                            bottom: 24,
                            child: Text(
                              'Featured collection',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: theme.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Positioned(top: 16, right: 16, child: MediaBar()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _shelf('Continue Watching', const ['The Last Voyage', 'Shoreline', 'Night Shift'], aspectRatio: 16 / 9)),
              SliverToBoxAdapter(child: _shelf('Next Up', const ['The Archive', 'Horizon', 'The Long Road', 'Northbound'])),
              SliverToBoxAdapter(child: _shelf('Top Picks', const ['Afterlight', 'Signal Fire', 'Open Water', 'The Crossing'])),
              SliverToBoxAdapter(child: _shelf('Recently Added', const ['Arrival Point', 'Glass House', 'Deep Space', 'The Garden'])),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.theme});

  final RemuxTheme theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.obsidianGlassStrong,
        borderRadius: BorderRadius.circular(theme.radiusPill),
        border: Border.all(color: theme.gold.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: theme.goldBright),
            const SizedBox(width: 6),
            Text(
              'Server online',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
