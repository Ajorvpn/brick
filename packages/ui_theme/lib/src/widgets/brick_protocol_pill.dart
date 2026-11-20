// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../brick_colors.dart';
import '../brick_tokens.dart';
import '../brick_typography.dart';

/// Crisp, jewel-like monospace protocol badge for server cards and telemetry headers.
///
/// Maps protocol tags deterministically to semantic hues compliant with WCAG AA
/// contrast (>= 4.5:1) in both Dark ("Obsidian Glass") and Light ("Ceramic") modes.
class BrickProtocolPill extends StatelessWidget {
  const BrickProtocolPill({
    super.key,
    required this.label,
    this.accentColor,
    this.compact = false,
  });

  final String label;
  final Color? accentColor;
  final bool compact;

  /// Resolves the semantic hue for a given protocol identifier deterministically.
  static Color resolveHue(
    String label, {
    required BrickSemanticColors colors,
    required bool isDark,
  }) {
    final normalized = label.trim().toUpperCase();
    if (normalized == 'REALITY' ||
        normalized == 'XTLS-REALITY' ||
        normalized.contains('REALITY')) {
      return isDark ? const Color(0xFF34D399) : const Color(0xFF047857);
    }
    if (normalized == 'VLESS') {
      return colors.brandBrick;
    }
    if (normalized == 'WG' ||
        normalized == 'WIREGUARD' ||
        normalized == 'AWG' ||
        normalized == 'AMNEZIAWG') {
      return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0369A1);
    }
    if (normalized == 'HY2' ||
        normalized == 'HYSTERIA2' ||
        normalized == 'TUIC') {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    }
    // TROJAN, VMESS, SS, SHADOWSOCKS, and any other protocol
    return isDark ? const Color(0xFFA78BFA) : const Color(0xFF6D28D9);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.brickColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hue =
        accentColor ?? resolveHue(label, colors: colors, isDark: isDark);

    // Light mode uses 0.07 (~7% soft tint) to ensure
    // strict >= 4.5:1 WCAG AA contrast against composite card/surface backgrounds.
    final bgAlpha = isDark ? 0.14 : 0.07;
    final borderAlpha = isDark ? 0.32 : 0.24;

    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0)
          : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: hue.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(BrickRadius.xs),
        border: Border.all(
          color: hue.withValues(alpha: borderAlpha),
          width: 1.0,
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: BrickTypography.monoLog(color: hue)
            .copyWith(fontWeight: FontWeight.w500, letterSpacing: 0.4),
      ),
    );
  }
}
