// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_colors.dart';
import '../brick_tokens.dart';

/// Architectural tactile glass card surface inspired by precision dark surfaces.
///
/// Features chamfered specular top-edge sheen, dual-tier surface elevation,
/// dynamic accent ambient halo when selected, and smooth tactile micro-scale
/// press feedback adhering to WCAG 2.1 touch target requirements.
class BrickGlassCard extends StatefulWidget {
  const BrickGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BrickSpacing.cardPaddingCompact),
    this.borderRadius = BrickRadius.card,
    this.elevated = false,
    this.isSelected = false,
    this.accentColor,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool elevated;
  final bool isSelected;
  final Color? accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  State<BrickGlassCard> createState() => _BrickGlassCardState();
}

class _BrickGlassCardState extends State<BrickGlassCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveAccent = widget.accentColor ?? colors.brandBrick;
    final isInteractive = widget.onTap != null || widget.onLongPress != null;

    final topSheenColor = widget.isSelected
        ? effectiveAccent.withValues(alpha: 0.08)
        : (isDark ? const Color(0x0BFFFFFF) : const Color(0x1AFFFFFF));

    final baseShadow = BoxShadow(
      color: colors.tintedShadow,
      blurRadius: widget.elevated ? 20.0 : 12.0,
      offset: Offset(0, widget.elevated ? 8.0 : 4.0),
    );

    final selectedHalo = BoxShadow(
      color: effectiveAccent.withValues(alpha: isDark ? 0.14 : 0.10),
      blurRadius: 18.0,
      spreadRadius: -2.0,
    );

    Widget innerContent = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: BrickSpacing.minTouchTarget),
      child: Padding(padding: widget.padding, child: widget.child),
    );

    if (isInteractive) {
      innerContent = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (highlighted) {
            setState(() {
              _isPressed = highlighted;
            });
          },
          splashColor: effectiveAccent.withValues(alpha: 0.10),
          highlightColor: effectiveAccent.withValues(alpha: 0.05),
          child: innerContent,
        ),
      );
    }

    final cardBody = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.elevated ? colors.surfaceElevated : colors.surface,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          width: widget.isSelected ? 1.25 : 1.0,
          color: widget.isSelected
              ? effectiveAccent.withValues(alpha: isDark ? 0.55 : 0.45)
              : colors.glassBorder,
        ),
        boxShadow: [baseShadow, if (widget.isSelected) selectedHalo],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            innerContent,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.28],
                      colors: [topSheenColor, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget result = cardBody;

    if (isInteractive) {
      result = AnimatedScale(
        scale: _isPressed ? 0.985 : 1.0,
        duration: BrickMotion.fast,
        curve: BrickMotion.curveStandard,
        child: result,
      );
    }

    if (widget.semanticLabel != null) {
      result = Semantics(
        label: widget.semanticLabel,
        selected: widget.isSelected,
        button: widget.onTap != null,
        child: result,
      );
    }

    return result;
  }
}
