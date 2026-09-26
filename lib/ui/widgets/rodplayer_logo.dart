import 'package:flutter/material.dart';
import 'package:rodplayer/core/theme/rodplayer_theme.dart';

class RodPlayerLogo extends StatelessWidget {
  const RodPlayerLogo({this.size = 42, this.glow = false, super.key});
  final double size;
  final bool glow;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<RodPlayerTheme>() ?? const RodPlayerTheme();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: theme.obsidian, borderRadius: BorderRadius.circular(size * .24), boxShadow: glow ? [BoxShadow(color: theme.accent.withValues(alpha: .28), blurRadius: 18)] : null),
      child: CustomPaint(painter: _RodPlayerLogoPainter(theme.accent)),
    );
  }
}
class _RodPlayerLogoPainter extends CustomPainter {
  const _RodPlayerLogoPainter(this.color);
  final Color color;
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = size.width * .12..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final x = size.width * .24; final y = size.height * .2; final w = size.width * .52; final h = size.height * .6;
    final path = Path()..moveTo(x, y + h)..lineTo(x, y)..lineTo(x + w * .58, y)..quadraticBezierTo(x + w, y, x + w, y + h * .27)..quadraticBezierTo(x + w, y + h * .48, x + w * .58, y + h * .48)..lineTo(x, y + h * .48)..moveTo(x + w * .48, y + h * .48)..lineTo(x + w, y + h);
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(covariant _RodPlayerLogoPainter oldDelegate) => color != oldDelegate.color;
}
