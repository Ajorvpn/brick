// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Raw color palette constants for the Brick VPN design system.
abstract final class BrickPalette {
  // Dark mode constants ("Obsidian Glass & Brick Ember")
  static const Color darkBackground = Color(0xFF07090F);
  static const Color darkSurface = Color(0xFF111521);
  static const Color darkSurfaceElevated = Color(0xFF181E2E);
  static const Color darkGlassBorder = Color(0x14FFFFFF);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFFCBD5E1);
  static const Color darkTextMuted = Color(0xFF8B98B0);
  static const Color darkBrandBrick = Color(0xFFF97316);
  static const Color darkBrandBrickSoft = Color(0x14F97316);
  static const Color darkStateDisconnected = Color(0xFF64748B);
  static const Color darkStateConnecting = Color(0xFFF59E0B);
  static const Color darkStateConnected = Color(0xFF10B981);
  static const Color darkStateConnectedGlow = Color(0x2910B981);
  static const Color darkStateReconnecting = Color(0xFFF59E0B);
  static const Color darkStateDisconnecting = Color(0xFF94A3B8);
  static const Color darkStateError = Color(0xFFEF4444);
  static const Color darkKillSwitchActive = Color(0xFFEF4444);
  static const Color darkTintedShadow = Color(0x6602040A);
  static const Color darkOnAccent = Color(0xFF07090F);

  // Light mode constants ("Ceramic Light & Brick Ember")
  static const Color lightBackground = Color(0xFFF4F6FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFEEF2F7);
  static const Color lightGlassBorder = Color(0x140F172A);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF334155);
  static const Color lightTextMuted = Color(0xFF475569);
  static const Color lightBrandBrick = Color(0xFFC2410C);
  static const Color lightBrandBrickSoft = Color(0x14C2410C);
  static const Color lightStateDisconnected = Color(0xFF64748B);
  static const Color lightStateConnecting = Color(0xFFB45309);
  static const Color lightStateConnected = Color(0xFF047857);
  static const Color lightStateConnectedGlow = Color(0x24047857);
  static const Color lightStateReconnecting = Color(0xFFB45309);
  static const Color lightStateDisconnecting = Color(0xFF64748B);
  static const Color lightStateError = Color(0xFFDC2626);
  static const Color lightKillSwitchActive = Color(0xFFDC2626);
  static const Color lightTintedShadow = Color(0x140F172A);
  static const Color lightOnAccent = Color(0xFFFFFFFF);
}

/// Semantic color tokens implementing [ThemeExtension] for dynamic theme switching.
@immutable
class BrickSemanticColors extends ThemeExtension<BrickSemanticColors> {
  const BrickSemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brandBrick,
    required this.brandBrickSoft,
    required this.stateDisconnected,
    required this.stateConnecting,
    required this.stateConnected,
    required this.stateConnectedGlow,
    required this.stateReconnecting,
    required this.stateDisconnecting,
    required this.stateError,
    required this.killSwitchActive,
    required this.tintedShadow,
    required this.onAccent,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color glassBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brandBrick;
  final Color brandBrickSoft;
  final Color stateDisconnected;
  final Color stateConnecting;
  final Color stateConnected;
  final Color stateConnectedGlow;
  final Color stateReconnecting;
  final Color stateDisconnecting;
  final Color stateError;
  final Color killSwitchActive;
  final Color tintedShadow;
  final Color onAccent;

  /// Dark mode palette ("Obsidian Glass & Brick Ember").
  static const BrickSemanticColors dark = BrickSemanticColors(
    background: BrickPalette.darkBackground,
    surface: BrickPalette.darkSurface,
    surfaceElevated: BrickPalette.darkSurfaceElevated,
    glassBorder: BrickPalette.darkGlassBorder,
    textPrimary: BrickPalette.darkTextPrimary,
    textSecondary: BrickPalette.darkTextSecondary,
    textMuted: BrickPalette.darkTextMuted,
    brandBrick: BrickPalette.darkBrandBrick,
    brandBrickSoft: BrickPalette.darkBrandBrickSoft,
    stateDisconnected: BrickPalette.darkStateDisconnected,
    stateConnecting: BrickPalette.darkStateConnecting,
    stateConnected: BrickPalette.darkStateConnected,
    stateConnectedGlow: BrickPalette.darkStateConnectedGlow,
    stateReconnecting: BrickPalette.darkStateReconnecting,
    stateDisconnecting: BrickPalette.darkStateDisconnecting,
    stateError: BrickPalette.darkStateError,
    killSwitchActive: BrickPalette.darkKillSwitchActive,
    tintedShadow: BrickPalette.darkTintedShadow,
    onAccent: BrickPalette.darkOnAccent,
  );

  /// Light mode palette ("Ceramic Light & Brick Ember").
  static const BrickSemanticColors light = BrickSemanticColors(
    background: BrickPalette.lightBackground,
    surface: BrickPalette.lightSurface,
    surfaceElevated: BrickPalette.lightSurfaceElevated,
    glassBorder: BrickPalette.lightGlassBorder,
    textPrimary: BrickPalette.lightTextPrimary,
    textSecondary: BrickPalette.lightTextSecondary,
    textMuted: BrickPalette.lightTextMuted,
    brandBrick: BrickPalette.lightBrandBrick,
    brandBrickSoft: BrickPalette.lightBrandBrickSoft,
    stateDisconnected: BrickPalette.lightStateDisconnected,
    stateConnecting: BrickPalette.lightStateConnecting,
    stateConnected: BrickPalette.lightStateConnected,
    stateConnectedGlow: BrickPalette.lightStateConnectedGlow,
    stateReconnecting: BrickPalette.lightStateReconnecting,
    stateDisconnecting: BrickPalette.lightStateDisconnecting,
    stateError: BrickPalette.lightStateError,
    killSwitchActive: BrickPalette.lightKillSwitchActive,
    tintedShadow: BrickPalette.lightTintedShadow,
    onAccent: BrickPalette.lightOnAccent,
  );

  @override
  BrickSemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? glassBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? brandBrick,
    Color? brandBrickSoft,
    Color? stateDisconnected,
    Color? stateConnecting,
    Color? stateConnected,
    Color? stateConnectedGlow,
    Color? stateReconnecting,
    Color? stateDisconnecting,
    Color? stateError,
    Color? killSwitchActive,
    Color? tintedShadow,
    Color? onAccent,
  }) {
    return BrickSemanticColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      glassBorder: glassBorder ?? this.glassBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      brandBrick: brandBrick ?? this.brandBrick,
      brandBrickSoft: brandBrickSoft ?? this.brandBrickSoft,
      stateDisconnected: stateDisconnected ?? this.stateDisconnected,
      stateConnecting: stateConnecting ?? this.stateConnecting,
      stateConnected: stateConnected ?? this.stateConnected,
      stateConnectedGlow: stateConnectedGlow ?? this.stateConnectedGlow,
      stateReconnecting: stateReconnecting ?? this.stateReconnecting,
      stateDisconnecting: stateDisconnecting ?? this.stateDisconnecting,
      stateError: stateError ?? this.stateError,
      killSwitchActive: killSwitchActive ?? this.killSwitchActive,
      tintedShadow: tintedShadow ?? this.tintedShadow,
      onAccent: onAccent ?? this.onAccent,
    );
  }

  @override
  BrickSemanticColors lerp(
    ThemeExtension<BrickSemanticColors>? other,
    double t,
  ) {
    if (other is! BrickSemanticColors) return this;
    return BrickSemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      brandBrick: Color.lerp(brandBrick, other.brandBrick, t)!,
      brandBrickSoft: Color.lerp(brandBrickSoft, other.brandBrickSoft, t)!,
      stateDisconnected: Color.lerp(
        stateDisconnected,
        other.stateDisconnected,
        t,
      )!,
      stateConnecting: Color.lerp(stateConnecting, other.stateConnecting, t)!,
      stateConnected: Color.lerp(stateConnected, other.stateConnected, t)!,
      stateConnectedGlow: Color.lerp(
        stateConnectedGlow,
        other.stateConnectedGlow,
        t,
      )!,
      stateReconnecting: Color.lerp(
        stateReconnecting,
        other.stateReconnecting,
        t,
      )!,
      stateDisconnecting: Color.lerp(
        stateDisconnecting,
        other.stateDisconnecting,
        t,
      )!,
      stateError: Color.lerp(stateError, other.stateError, t)!,
      killSwitchActive: Color.lerp(
        killSwitchActive,
        other.killSwitchActive,
        t,
      )!,
      tintedShadow: Color.lerp(tintedShadow, other.tintedShadow, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

/// Convenience extension for fast access to [BrickSemanticColors].
extension BrickThemeContext on BuildContext {
  BrickSemanticColors get brickColors =>
      Theme.of(this).extension<BrickSemanticColors>() ??
      BrickSemanticColors.dark;
}
