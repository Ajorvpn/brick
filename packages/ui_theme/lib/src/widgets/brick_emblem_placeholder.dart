// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_colors.dart';

/// Temporary programmatic geometric Brick emblem placeholder mark.
///
/// **Design Note:**
/// Per human architectural direction (2026-11-18), this widget provides a clean,
/// lightweight geometric staggered-masonry "brick shield" motif for Phase 11.
/// Bespoke professional iconography and illustration assets are explicitly deferred
/// to a later dedicated brand-asset pass. This widget is structured for a drop-in swap
/// once final vector brand assets are produced.
class BrickEmblemPlaceholder extends StatelessWidget {
  const BrickEmblemPlaceholder({
    super.key,
    this.size = 48.0,
    this.isConnected = false,
    this.color,
  });

  /// The width and height of the square emblem bounding box.
  final double size;

  /// Whether the emblem reflects the connected peak state.
  final bool isConnected;

  /// Optional color override. When null, defaults to [BrickSemanticColors.stateConnected]
  /// if [isConnected] is true, or [BrickSemanticColors.brandBrick] if false.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;
    final effectiveColor =
        color ?? (isConnected ? colors.stateConnected : colors.brandBrick);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _BrickEmblemPainter(color: effectiveColor)),
    );
  }
}

class _BrickEmblemPainter extends CustomPainter {
  const _BrickEmblemPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // 3-row staggered masonry grid with gap
    final gap = w * 0.06;
    final cornerRadius = Radius.circular(w * 0.08);

    // Row heights
    final rowHeight = (h - (gap * 2)) / 3.0;

    // Row 1 (Top): 2 equal bricks
    final r1BrickWidth = (w - gap) / 2.0;
    final r1b1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, r1BrickWidth, rowHeight),
      cornerRadius,
    );
    final r1b2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(r1BrickWidth + gap, 0, r1BrickWidth, rowHeight),
      cornerRadius,
    );
    canvas.drawRRect(r1b1, paint);
    canvas.drawRRect(r1b2, paint);

    // Row 2 (Middle): Staggered masonry (half-brick, full-brick, half-brick)
    final y2 = rowHeight + gap;
    final r2HalfWidth = (w - (gap * 2)) * 0.25;
    final r2CenterWidth = (w - (gap * 2)) * 0.5;

    final r2b1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y2, r2HalfWidth, rowHeight),
      cornerRadius,
    );
    final r2b2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(r2HalfWidth + gap, y2, r2CenterWidth, rowHeight),
      cornerRadius,
    );
    final r2b3 = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        r2HalfWidth + gap + r2CenterWidth + gap,
        y2,
        r2HalfWidth,
        rowHeight,
      ),
      cornerRadius,
    );
    canvas.drawRRect(r2b1, paint);
    canvas.drawRRect(r2b2, paint);
    canvas.drawRRect(r2b3, paint);

    // Row 3 (Bottom): 2 equal bricks (tapered base)
    final y3 = (rowHeight + gap) * 2;
    final inset = w * 0.08;
    final r3TotalWidth = w - (inset * 2);
    final r3BrickWidth = (r3TotalWidth - gap) / 2.0;

    final r3b1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, y3, r3BrickWidth, rowHeight),
      cornerRadius,
    );
    final r3b2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset + r3BrickWidth + gap, y3, r3BrickWidth, rowHeight),
      cornerRadius,
    );
    canvas.drawRRect(r3b1, paint);
    canvas.drawRRect(r3b2, paint);
  }

  @override
  bool shouldRepaint(covariant _BrickEmblemPainter oldDelegate) =>
      oldDelegate.color != color;
}
