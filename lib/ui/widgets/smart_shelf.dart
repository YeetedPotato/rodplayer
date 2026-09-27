import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

/// Builds an item using [focusNode] as its single focus target.
typedef SmartShelfItemBuilder = Widget Function(
  BuildContext context,
  int index,
  FocusNode focusNode, {
  required bool autofocus,
});

// Mirrors the 1.045 card scale and 12px focus shadow blur.
const double _focusScaleOverhangRatio = 0.045;
const double _focusGlowBlurAllowance = 12;

class SmartShelf extends StatelessWidget {
  const SmartShelf({required this.title, required this.itemBuilder, required this.itemCount, this.subtitle, this.itemCountBadge = false, this.action, this.aspectRatio = 2 / 3, this.itemWidth, this.padding, this.itemSpacing = 16, this.autofocusFirstItem = false, super.key});
  final String title;
  final String? subtitle;
  final SmartShelfItemBuilder itemBuilder;
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
    final focusPaintGutter = resolvedItemWidth * _focusScaleOverhangRatio / 2 + _focusGlowBlurAllowance;
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
            const SizedBox(height: 12),
            SizedBox(
              height: _itemHeight(resolvedItemWidth, aspectRatio) + 16,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: shelfPadding.add(EdgeInsets.symmetric(horizontal: focusPaintGutter)).add(const EdgeInsets.symmetric(vertical: 8)),
                clipBehavior: Clip.none,
                physics: const BouncingScrollPhysics(),
                itemCount: itemCount,
                itemBuilder: (context, index) => SizedBox(
                  width: resolvedItemWidth,
                  child: _ShelfItem(
                    index: index,
                    itemBuilder: itemBuilder,
                    autofocus: autofocusFirstItem && index == 0,
                    paintGutter: focusPaintGutter,
                  ),
                ),
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

class _ShelfItem extends StatefulWidget {
  const _ShelfItem({required this.index, required this.itemBuilder, required this.autofocus, required this.paintGutter});
  final int index;
  final SmartShelfItemBuilder itemBuilder;
  final bool autofocus;
  final double paintGutter;

  @override
  State<_ShelfItem> createState() => _ShelfItemState();
}

class _ShelfItemState extends State<_ShelfItem> {
  late final FocusNode _focusNode;
  int _revealRequest = 0;
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'SmartShelf item');
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.itemBuilder(
        context,
        widget.index,
        _focusNode,
        autofocus: widget.autofocus,
      );

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused == _hadFocus) return;
    _hadFocus = focused;
    final request = ++_revealRequest;
    _stopShelfScroll();
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentRequest(request) && context.mounted) {
        unawaited(_revealWithPaintRoom(request));
      }
    });
  }

  bool _isCurrentRequest(int request) => mounted && _focusNode.hasFocus && request == _revealRequest;

  void _stopShelfScroll() {
    if (!mounted || !context.mounted) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.mounted) return;
    final position = scrollable.position;
    if (!position.hasContentDimensions || !position.isScrollingNotifier.value) return;
    if (position.axisDirection != AxisDirection.left && position.axisDirection != AxisDirection.right) return;
    position.jumpTo(position.pixels);
  }

  Future<void> _revealWithPaintRoom(int request) async {
    await Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    if (!mounted) return;
    if (!_isCurrentRequest(request)) return;

    final scrollable = Scrollable.maybeOf(context);
    final target = context.findRenderObject();
    if (scrollable == null || !scrollable.mounted || target is! RenderBox || !target.attached) return;
    final position = scrollable.position;
    if (!position.hasContentDimensions) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport is! RenderBox) return;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.attached || (position.axisDirection != AxisDirection.left && position.axisDirection != AxisDirection.right)) return;

    final targetRect = MatrixUtils.transformRect(target.getTransformTo(viewportBox), target.paintBounds);
    final viewportRect = Offset.zero & viewportBox.size;
    final leftGap = targetRect.left - viewportRect.left;
    final rightGap = viewportRect.right - targetRect.right;
    var scrollDelta = rightGap < widget.paintGutter ? widget.paintGutter - rightGap : leftGap < widget.paintGutter ? leftGap - widget.paintGutter : 0.0;
    if (position.axisDirection == AxisDirection.left) scrollDelta = -scrollDelta;
    final targetPixels = (position.pixels + scrollDelta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (!mounted) return;
    if (targetPixels == position.pixels || !_isCurrentRequest(request) || !scrollable.mounted || !target.attached || !viewportBox.attached || !position.hasContentDimensions) return;
    await position.animateTo(targetPixels, duration: const Duration(milliseconds: 120), curve: Curves.easeOutCubic);
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.theme});
  final int count;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(theme.radiusPill), border: Border.all(color: theme.accent.withValues(alpha: 0.34))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: theme.accentBright, fontWeight: FontWeight.w700)),
        ),
      );
}
