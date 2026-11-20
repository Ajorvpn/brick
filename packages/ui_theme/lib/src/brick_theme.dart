// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import 'brick_colors.dart';
import 'brick_tokens.dart';
import 'brick_typography.dart';

/// Builder class for Material 3 [ThemeData] in Dark and Light modes.
abstract final class BrickTheme {
  /// Dark Theme ("Obsidian Glass & Brick Ember").
  static ThemeData dark() => _buildTheme(
    brightness: Brightness.dark,
    colors: BrickSemanticColors.dark,
  );

  /// Light Theme ("Ceramic Light & Brick Ember").
  static ThemeData light() => _buildTheme(
    brightness: Brightness.light,
    colors: BrickSemanticColors.light,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required BrickSemanticColors colors,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.brandBrick,
      onPrimary: colors.onAccent,
      secondary: colors.stateConnecting,
      onSecondary: colors.onAccent,
      error: colors.stateError,
      onError: colors.onAccent,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceElevated,
      outline: colors.glassBorder,
      shadow: colors.tintedShadow,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      fontFamily: BrickTypography.primaryFontFamily,
      fontFamilyFallback: BrickTypography.primaryFontFallbacks,
      textTheme: BrickTypography.textTheme(colors),
      extensions: <ThemeExtension<dynamic>>[colors],
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrickRadius.card),
          side: BorderSide(color: colors.glassBorder, width: 1.0),
        ),
        elevation: 0.0,
        color: colors.surface,
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        elevation: 0.0,
        indicatorColor: colors.brandBrickSoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontFamily: BrickTypography.primaryFontFamily,
              fontSize: BrickTypography.sizeLabel,
              fontWeight: FontWeight.w500,
              color: colors.brandBrick,
            );
          }
          return TextStyle(
            fontFamily: BrickTypography.primaryFontFamily,
            fontSize: BrickTypography.sizeLabel,
            fontWeight: FontWeight.w500,
            color: colors.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colors.brandBrick, size: 24.0);
          }
          return IconThemeData(color: colors.textMuted, size: 24.0);
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64.0, BrickSpacing.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BrickRadius.md),
          ),
          backgroundColor: colors.brandBrick,
          foregroundColor: colors.onAccent,
          elevation: 0.0,
          textStyle: const TextStyle(
            fontFamily: BrickTypography.primaryFontFamily,
            fontSize: BrickTypography.sizeBody,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64.0, BrickSpacing.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BrickRadius.md),
          ),
          side: BorderSide(color: colors.glassBorder),
          foregroundColor: colors.textPrimary,
          textStyle: const TextStyle(
            fontFamily: BrickTypography.primaryFontFamily,
            fontSize: BrickTypography.sizeBody,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.onAccent;
          }
          return colors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.brandBrick;
          }
          return colors.surfaceElevated;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return colors.glassBorder;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: BrickSpacing.md,
          vertical: BrickSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrickRadius.md),
          borderSide: BorderSide(color: colors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrickRadius.md),
          borderSide: BorderSide(color: colors.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BrickRadius.md),
          borderSide: BorderSide(color: colors.brandBrick, width: 1.5),
        ),
        hintStyle: TextStyle(
          color: colors.textMuted,
          fontSize: BrickTypography.sizeBody,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.glassBorder,
        thickness: 1.0,
        space: 1.0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrickRadius.sheet),
          side: BorderSide(color: colors.glassBorder),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        foregroundColor: colors.textPrimary,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: BrickTypography.primaryFontFamily,
          fontSize: BrickTypography.sizeTitle,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

/// Backward compatibility layer delegating to [BrickTheme].
abstract final class AppTheme {
  static ThemeData light() => BrickTheme.light();
  static ThemeData dark() => BrickTheme.dark();
}
