import 'package:flutter/material.dart';
import 'package:rodplayer/core/models/media_intelligence.dart';
import 'package:rodplayer/core/theme/remux_theme.dart';
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
  @override void dispose() { _focusNode.dispose(); super.dispose(); }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      widget.onTap?.call();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RemuxTheme>() ?? const RemuxTheme();
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(aspectRatio: widget.aspectRatio, child: Stack(fit: StackFit.expand, children: [
                _MediaImage(imageUrl: widget.imageUrl, theme: theme),
                if (widget.mediaInfo != null) Positioned(top: 10, left: 10, right: 10, child: MediaBadgeOverlay(mediaInfo: widget.mediaInfo!)),
                if (widget.badge != null) Positioned(top: 10, right: 10, child: widget.badge!),
              ])),
              Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: theme.textPrimary, fontWeight: FontWeight.w700)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.textSecondary)),
                ],
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MediaImage extends StatelessWidget {
  const _MediaImage({required this.imageUrl, required this.theme});
  final String? imageUrl;
  final RemuxTheme theme;
  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return _placeholder();
    return Image.network(url, fit: BoxFit.cover, filterQuality: FilterQuality.medium, errorBuilder: (_, __, ___) => _placeholder(), loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder());
  }
  Widget _placeholder() => ColoredBox(color: theme.obsidianRaised, child: Icon(Icons.movie_outlined, color: theme.textMuted, size: 36));
}
