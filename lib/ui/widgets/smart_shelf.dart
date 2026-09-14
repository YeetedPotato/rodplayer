import 'package:flutter/material.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class SmartShelf extends StatelessWidget {
  const SmartShelf({required this.title, required this.itemBuilder, required this.itemCount, this.subtitle, this.itemCountBadge = false, this.action, this.aspectRatio = 2 / 3, this.itemWidth, this.padding, this.itemSpacing = 14, this.autofocusFirstItem = false, super.key});
  final String title;
  final String? subtitle;
  final IndexedWidgetBuilder itemBuilder;
  final int itemCount;
  final bool itemCountBadge;
  final Widget? action;
  final double aspectRatio;
  final double? itemWidth;
  final EdgeInsetsGeometry? padding;
  final double itemSpacing;
  final bool autofocusFirstItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final shelfPadding = padding ?? const EdgeInsets.symmetric(horizontal: 24);
    final resolvedItemWidth = itemWidth ?? _defaultItemWidth(aspectRatio);
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: DecoratedBox(
        decoration: BoxDecoration(color: theme.obsidian),
        child: Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: shelfPadding, child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: theme.textPrimary, fontWeight: FontWeight.w700, letterSpacing: 0.1))),
                  if (itemCountBadge) ...[const SizedBox(width: 10), _CountBadge(count: itemCount, theme: theme)],
                ]),
                if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: theme.textMuted))],
              ])),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ])),
            const SizedBox(height: 14),
            SizedBox(
              height: _itemHeight(resolvedItemWidth, aspectRatio),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: shelfPadding,
                physics: const BouncingScrollPhysics(),
                itemCount: itemCount,
                itemBuilder: (context, index) => SizedBox(width: resolvedItemWidth, child: _ShelfItem(autofocus: autofocusFirstItem && index == 0, child: itemBuilder(context, index))),
                separatorBuilder: (_, __) => SizedBox(width: itemSpacing),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  double _defaultItemWidth(double ratio) => ratio >= 1.5 ? 280 : 176;
  double _itemHeight(double width, double ratio) => width / ratio + 86;
}

class _ShelfItem extends StatelessWidget {
  const _ShelfItem({required this.child, required this.autofocus});
  final Widget child;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
        autofocus: autofocus,
        onFocusChange: (focused) {
          if (!focused) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
          });
        },
        child: child,
      );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.theme});
  final int count;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: theme.gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(theme.radiusPill), border: Border.all(color: theme.gold.withValues(alpha: 0.34))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: theme.goldBright, fontWeight: FontWeight.w700)),
        ),
      );
}
