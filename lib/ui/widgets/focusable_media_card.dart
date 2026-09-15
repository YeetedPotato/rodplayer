import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';
import 'package:rodplayer/ui/widgets/media_badge_overlay.dart';

class FocusableMediaCard extends StatefulWidget {
  const FocusableMediaCard({required this.title, this.subtitle, this.imageUrl, this.aspectRatio = 2 / 3, this.badge, this.mediaInfo, this.onTap, this.autofocus = false, this.focusNode, super.key});
  final String title;
  final String? subtitle, imageUrl;
  final double aspectRatio;
  final Widget? badge;
  final MediaIntelligence? mediaInfo;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  @override State<FocusableMediaCard> createState() => _FocusableMediaCardState();
}

class _FocusableMediaCardState extends State<FocusableMediaCard> {
  late final FocusNode _focusNode;
  FocusNode get _effectiveFocusNode => widget.focusNode ?? _focusNode;
  @override void initState() { super.initState(); _focusNode = FocusNode(debugLabel: 'FocusableMediaCard: ${widget.title}'); }
  @override void dispose() { if (widget.focusNode == null) _focusNode.dispose(); super.dispose(); }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final focused = _effectiveFocusNode.hasFocus;
    final radius = BorderRadius.circular(theme.radiusMedium);
    return Focus(
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: _handleKey,
      child: AnimatedScale(
        scale: focused ? 1.045 : 1,
        duration: const Duration(milliseconds: 175), curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 175), curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: theme.obsidianGlass, borderRadius: radius,
            border: Border.all(color: focused ? theme.goldBright : theme.obsidianGlass, width: focused ? 2 : 1),
            boxShadow: focused ? [...theme.glassShadow, ...theme.goldGlow] : theme.glassShadow,
          ), clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap, borderRadius: radius, focusColor: Colors.transparent, hoverColor: Colors.transparent,
            splashColor: theme.gold.withValues(alpha: 0.16),
            child: LayoutBuilder(builder: (context, constraints) {
              final poster = _Poster(
                aspectRatio: widget.aspectRatio,
                imageUrl: widget.imageUrl,
                mediaInfo: widget.mediaInfo,
                badge: widget.badge,
                theme: theme,
              );
              final metadata = _Metadata(title: widget.title, subtitle: widget.subtitle, theme: theme);
              if (!constraints.hasBoundedHeight) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [poster, metadata]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 3, child: poster),
                Flexible(flex: 1, child: metadata),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.aspectRatio, required this.imageUrl, required this.mediaInfo, required this.badge, required this.theme});
  final double aspectRatio;
  final String? imageUrl;
  final MediaIntelligence? mediaInfo;
  final Widget? badge;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(fit: StackFit.expand, children: [
          _MediaImage(imageUrl: imageUrl, theme: theme),
          if (mediaInfo != null) Positioned(top: 10, left: 10, right: 10, child: MediaBadgeOverlay(mediaInfo: mediaInfo!)),
          if (badge != null) Positioned(top: 10, right: 10, child: badge!),
        ]),
      );
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.title, required this.subtitle, required this.theme});
  final String title;
  final String? subtitle;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final bounded = constraints.hasBoundedHeight;
          final maxHeight = constraints.maxHeight;
          final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
          if (bounded && maxHeight < 52 * textScale) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.textPrimary, fontWeight: FontWeight.w700)),
            );
          }
          final showSubtitle = subtitle != null && (!bounded || maxHeight >= 76 * textScale);
          final titleLines = showSubtitle && (!bounded || maxHeight >= 104 * textScale) ? 2 : 1;
          final titleText = Text(title, maxLines: titleLines, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: theme.textPrimary, fontWeight: FontWeight.w700));
          final subtitleText = showSubtitle ? Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.textSecondary)) : null;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min, children: [
              if (bounded) Flexible(child: titleText) else titleText,
              if (showSubtitle) ...[
                const SizedBox(height: 3),
                if (bounded) Flexible(child: subtitleText!) else subtitleText!,
              ],
            ]),
          );
        },
      );
}

class _MediaImage extends StatelessWidget {
  const _MediaImage({required this.imageUrl, required this.theme});
  final String? imageUrl;
  final RodPlayerTheme theme;
  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return _placeholder();
    return Image.network(url, fit: BoxFit.cover, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => _placeholder(), loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder());
  }
  Widget _placeholder() => ColoredBox(color: theme.obsidianRaised, child: Icon(Icons.movie_outlined, color: theme.textMuted, size: 36));
}
