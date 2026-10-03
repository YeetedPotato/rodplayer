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

typedef SmartShelfTerminalBuilder = Widget Function(
  BuildContext context,
  FocusNode focusNode,
);

// Mirrors the 1.045 card scale and 12px focus shadow blur.
const double _focusScaleOverhangRatio = 0.045;
const double _focusGlowBlurAllowance = 12;

class SmartShelf extends StatefulWidget {
  const SmartShelf(
      {required this.title,
      required this.itemBuilder,
      required this.itemCount,
      this.terminalItemBuilder,
      this.subtitle,
      this.itemCountBadge = false,
      this.action,
      this.aspectRatio = 2 / 3,
      this.itemWidth,
      this.padding,
      this.itemSpacing = 16,
      this.autofocusFirstItem = false,
      super.key});
  final String title;
  final String? subtitle;
  final SmartShelfItemBuilder itemBuilder;
  final SmartShelfTerminalBuilder? terminalItemBuilder;
  final int itemCount;
  final bool itemCountBadge;
  final Widget? action;
  final double aspectRatio;
  final double? itemWidth;
  final EdgeInsetsGeometry? padding;
  final double itemSpacing;
  final bool autofocusFirstItem;

  @override
  State<SmartShelf> createState() => _SmartShelfState();
}

class _SmartShelfState extends State<SmartShelf> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _pointerOverShelf = false;
  bool _focusedInShelf = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollControls);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateScrollControls());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollControls)
      ..dispose();
    super.dispose();
  }

  void _updateScrollControls() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.extentBefore > 0.5;
    final canRight = position.extentAfter > 0.5;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  Future<void> _scrollByPage(double direction) async {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target =
        (position.pixels + direction * position.viewportDimension * .72)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    final shelfPadding =
        widget.padding ?? const EdgeInsets.symmetric(horizontal: 24);
    final resolvedItemWidth =
        widget.itemWidth ?? _defaultItemWidth(widget.aspectRatio);
    final focusPaintGutter = resolvedItemWidth * _focusScaleOverhangRatio / 2 +
        _focusGlowBlurAllowance;
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _pointerOverShelf = true),
        onExit: (_) => setState(() => _pointerOverShelf = false),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.obsidian),
          child: Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: shelfPadding,
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Flexible(
                                child: Text(widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            color: theme.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.1))),
                            if (widget.itemCountBadge) ...[
                              const SizedBox(width: 10),
                              _CountBadge(count: widget.itemCount, theme: theme)
                            ],
                          ]),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(widget.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: theme.textMuted))
                          ],
                        ])),
                    if (widget.action != null) ...[
                      const SizedBox(width: 12),
                      widget.action!
                    ],
                  ])),
              const SizedBox(height: 12),
              SizedBox(
                height: _itemHeight(resolvedItemWidth, widget.aspectRatio) + 16,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ListView.separated(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      padding: shelfPadding
                          .add(EdgeInsets.symmetric(
                              horizontal: focusPaintGutter))
                          .add(const EdgeInsets.symmetric(vertical: 8)),
                      clipBehavior: Clip.none,
                      physics: const BouncingScrollPhysics(),
                      itemCount: widget.itemCount +
                          (widget.terminalItemBuilder == null ? 0 : 1),
                      itemBuilder: (context, index) => SizedBox(
                        width: resolvedItemWidth,
                        child: _ShelfItem(
                          index: index,
                          itemBuilder: widget.itemBuilder,
                          terminalItemBuilder: widget.terminalItemBuilder,
                          terminal: index == widget.itemCount,
                          autofocus: widget.autofocusFirstItem && index == 0,
                          paintGutter: focusPaintGutter,
                          onFocusChanged: (focused) =>
                              setState(() => _focusedInShelf = focused),
                        ),
                      ),
                      separatorBuilder: (_, __) =>
                          SizedBox(width: widget.itemSpacing),
                    ),
                    if ((_pointerOverShelf || _focusedInShelf) &&
                        _canScrollLeft)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _ShelfScrollButton(
                            tooltip: 'Scroll left',
                            icon: Icons.chevron_left,
                            theme: theme,
                            onPressed: () => unawaited(_scrollByPage(-1)),
                          ),
                        ),
                      ),
                    if ((_pointerOverShelf || _focusedInShelf) &&
                        _canScrollRight)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _ShelfScrollButton(
                            tooltip: 'Scroll right',
                            icon: Icons.chevron_right,
                            theme: theme,
                            onPressed: () => unawaited(_scrollByPage(1)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  double _defaultItemWidth(double ratio) => ratio >= 1.5 ? 280 : 176;
  double _itemHeight(double width, double ratio) => width / ratio + 86;
}

class _ShelfScrollButton extends StatelessWidget {
  const _ShelfScrollButton({
    required this.tooltip,
    required this.icon,
    required this.theme,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final RodPlayerTheme theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: theme.obsidianRaised.withValues(alpha: .92),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, color: theme.textPrimary),
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            maximumSize: const Size(44, 44),
            side: BorderSide(color: theme.borderColor(.18)),
          ),
        ),
      );
}

class _ShelfItem extends StatefulWidget {
  const _ShelfItem(
      {required this.index,
      required this.itemBuilder,
      required this.terminalItemBuilder,
      required this.terminal,
      required this.autofocus,
      required this.paintGutter,
      required this.onFocusChanged});
  final int index;
  final SmartShelfItemBuilder itemBuilder;
  final SmartShelfTerminalBuilder? terminalItemBuilder;
  final bool terminal;
  final bool autofocus;
  final double paintGutter;
  final ValueChanged<bool> onFocusChanged;

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
  Widget build(BuildContext context) {
    if (widget.terminal && widget.terminalItemBuilder != null) {
      return widget.terminalItemBuilder!(context, _focusNode);
    }
    return widget.itemBuilder(context, widget.index, _focusNode,
        autofocus: widget.autofocus);
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (focused == _hadFocus) return;
    _hadFocus = focused;
    widget.onFocusChanged(focused);
    final request = ++_revealRequest;
    _stopShelfScroll();
    if (!focused) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrentRequest(request) && context.mounted) {
        unawaited(_revealWithPaintRoom(request));
      }
    });
  }

  bool _isCurrentRequest(int request) =>
      mounted && _focusNode.hasFocus && request == _revealRequest;

  void _stopShelfScroll() {
    if (!mounted || !context.mounted) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null || !scrollable.mounted) return;
    final position = scrollable.position;
    if (!position.hasContentDimensions || !position.isScrollingNotifier.value)
      return;
    if (position.axisDirection != AxisDirection.left &&
        position.axisDirection != AxisDirection.right) return;
    position.jumpTo(position.pixels);
  }

  Future<void> _revealWithPaintRoom(int request) async {
    await Scrollable.ensureVisible(context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    if (!mounted) return;
    if (!_isCurrentRequest(request)) return;

    final scrollable = Scrollable.maybeOf(context);
    final target = context.findRenderObject();
    if (scrollable == null ||
        !scrollable.mounted ||
        target is! RenderBox ||
        !target.attached) return;
    final position = scrollable.position;
    if (!position.hasContentDimensions) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport is! RenderBox) return;
    final viewportBox = viewport as RenderBox;
    if (!viewportBox.attached ||
        (position.axisDirection != AxisDirection.left &&
            position.axisDirection != AxisDirection.right)) return;

    final targetRect = MatrixUtils.transformRect(
        target.getTransformTo(viewportBox), target.paintBounds);
    final viewportRect = Offset.zero & viewportBox.size;
    final leftGap = targetRect.left - viewportRect.left;
    final rightGap = viewportRect.right - targetRect.right;
    var scrollDelta = rightGap < widget.paintGutter
        ? widget.paintGutter - rightGap
        : leftGap < widget.paintGutter
            ? leftGap - widget.paintGutter
            : 0.0;
    if (position.axisDirection == AxisDirection.left)
      scrollDelta = -scrollDelta;
    final targetPixels = (position.pixels + scrollDelta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (!mounted) return;
    if (targetPixels == position.pixels ||
        !_isCurrentRequest(request) ||
        !scrollable.mounted ||
        !target.attached ||
        !viewportBox.attached ||
        !position.hasContentDimensions) return;
    await position.animateTo(targetPixels,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic);
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.theme});
  final int count;
  final RodPlayerTheme theme;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(theme.radiusPill),
            border: Border.all(color: theme.accent.withValues(alpha: 0.34))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text('$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: theme.accentBright, fontWeight: FontWeight.w700)),
        ),
      );
}
