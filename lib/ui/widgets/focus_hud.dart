import 'package:flutter/material.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class FocusHud extends StatelessWidget {
  const FocusHud({required this.child, required this.visible, this.alignment = Alignment.bottomCenter, super.key});
  final Widget child;
  final bool visible;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.16),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.obsidianGlassStrong, borderRadius: BorderRadius.circular(theme.radiusLarge), boxShadow: theme.glassShadow),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
