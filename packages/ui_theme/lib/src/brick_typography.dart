// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import 'brick_colors.dart';

/// Typography definitions, scales, and monospace telemetry styles for Brick VPN.
///
/// **GPL-3.0 Compatibility Verification:**
/// - Primary UI Font: 'Inter' with fallback ['Roboto', 'sans-serif']
///   - Inter: SIL Open Font License 1.1 (100% GPL-3.0-compatible).
///   - Roboto: Apache License 2.0 (100% GPL-3.0-compatible).
/// - Telemetry & Logs Monospace Font: 'JetBrains Mono' with fallback
///   ['RobotoMono', 'monospace']
///   - JetBrains Mono: SIL Open Font License 1.1 (100% GPL-3.0-compatible).
///   - Roboto Mono: Apache License 2.0 (100% GPL-3.0-compatible).
/// - Zero proprietary fonts; zero dynamic network font fetching at runtime.
///
/// **Bundled assets (P11-T5):** both families are shipped inside the app as
/// SIL OFL-1.1 `.ttf` assets under `apps/mobile/assets/fonts/` and registered
/// in `apps/mobile/pubspec.yaml`, whose `family:` names must stay identical to
/// [primaryFontFamily] and [monoFontFamily]. Nothing is downloaded at runtime
/// (Invariant 37), and the license notices live beside the fonts as
/// `OFL-Inter.txt` / `OFL-JetBrainsMono.txt`.
///
/// Inter is bundled as a single **variable** font (`InterVariable.ttf`), so
/// each optical weight is selected through the `wght` design axis via
/// [TextStyle.fontVariations] rather than through one static file per weight.
/// Without those variations the engine would synthesize fake bolding from the
/// default instance. JetBrains Mono is bundled as three static instances, so
/// its weights come from the real [`FontWeight`] already declared below.
abstract final class BrickTypography {
  static const String primaryFontFamily = 'Inter';
  static const List<String> primaryFontFallbacks = <String>[
    'Roboto',
    'sans-serif',
  ];

  static const String monoFontFamily = 'JetBrains Mono';
  static const List<String> monoFontFallbacks = <String>[
    'RobotoMono',
    'monospace',
  ];

  // 4-Size Disciplined UI Hierarchy:
  // 1. Display: 28sp w700
  // 2. Title: 18sp w700 / w500
  // 3. Body: 14sp w500 / w400
  // 4. Label: 12sp w500 / w400
  static const double sizeDisplay = 28.0;
  static const double sizeTitle = 18.0;
  static const double sizeBody = 14.0;
  static const double sizeLabel = 12.0;

  // Monospace Telemetry Sizes:
  static const double sizeMonoMetricLarge = 22.0;
  static const double sizeMonoMetric = 16.0;
  static const double sizeMonoLog = 12.0;

  /// `InterVariable.ttf` `wght` axis value for [FontWeight.w400].
  static const List<FontVariation> regularWeight = <FontVariation>[
    FontVariation('wght', 400),
  ];

  /// `InterVariable.ttf` `wght` axis value for [FontWeight.w500].
  static const List<FontVariation> mediumWeight = <FontVariation>[
    FontVariation('wght', 500),
  ];

  /// `InterVariable.ttf` `wght` axis value for [FontWeight.w700].
  static const List<FontVariation> boldWeight = <FontVariation>[
    FontVariation('wght', 700),
  ];

  /// Returns an `Inter` [TextStyle] carrying the matching `wght`
  /// [FontVariation], so `InterVariable.ttf` renders genuine optical
  /// Regular/Medium/Bold instances instead of synthesized bolding.
  ///
  /// Widgets that need a one-off `Inter` label must build it through this
  /// helper rather than a bare [TextStyle]: the bundled variable font has no
  /// static per-weight files, so a style without `fontVariations` would fall
  /// back to the default 400 instance for every weight.
  static TextStyle uiStyle({
    required double fontSize,
    required FontWeight fontWeight,
    required Color color,
    double? height,
    double? letterSpacing,
  }) {
    final variations = switch (fontWeight) {
      FontWeight.w700 => boldWeight,
      FontWeight.w500 => mediumWeight,
      _ => regularWeight,
    };
    return TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontVariations: variations,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// Dedicated Monospace telemetry style for large numeric gauges (e.g. throughput metrics).
  ///
  /// Always includes [FontFeature.tabularFigures()] so 1 Hz counters never jitter.
  static TextStyle monoMetricLarge({Color? color}) => TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallbacks,
    fontSize: sizeMonoMetricLarge,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: color,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Dedicated Monospace telemetry style for metric chips and ping counters.
  static TextStyle monoMetric({Color? color}) => TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallbacks,
    fontSize: sizeMonoMetric,
    fontWeight: FontWeight.w500,
    height: 1.25,
    color: color,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Dedicated Monospace style for live diagnostic logs.
  static TextStyle monoLog({Color? color}) => TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFontFallbacks,
    fontSize: sizeMonoLog,
    fontWeight: FontWeight.w400,
    height: 1.35,
    color: color,
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  /// Creates a Material 3 [TextTheme] mapped strictly to the 4-size / 3-weight hierarchy.
  static TextTheme textTheme(BrickSemanticColors colors) {
    final defaultTextStyle = TextStyle(
      fontFamily: primaryFontFamily,
      fontFamilyFallback: primaryFontFallbacks,
    );

    return TextTheme(
      // Display level (28sp w700)
      displayLarge: defaultTextStyle.copyWith(
        fontSize: sizeDisplay,
        fontWeight: FontWeight.w700,
        fontVariations: boldWeight,
        height: 1.2,
        color: colors.textPrimary,
      ),
      displayMedium: defaultTextStyle.copyWith(
        fontSize: sizeDisplay,
        fontWeight: FontWeight.w700,
        fontVariations: boldWeight,
        height: 1.2,
        color: colors.textPrimary,
      ),
      displaySmall: defaultTextStyle.copyWith(
        fontSize: sizeDisplay,
        fontWeight: FontWeight.w700,
        fontVariations: boldWeight,
        height: 1.2,
        color: colors.textPrimary,
      ),

      // Headline / Title level (18sp w700 / w500)
      headlineLarge: defaultTextStyle.copyWith(
        fontSize: sizeTitle,
        fontWeight: FontWeight.w700,
        fontVariations: boldWeight,
        height: 1.25,
        color: colors.textPrimary,
      ),
      headlineMedium: defaultTextStyle.copyWith(
        fontSize: sizeTitle,
        fontWeight: FontWeight.w700,
        fontVariations: boldWeight,
        height: 1.25,
        color: colors.textPrimary,
      ),
      headlineSmall: defaultTextStyle.copyWith(
        fontSize: sizeTitle,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.25,
        color: colors.textPrimary,
      ),

      titleLarge: defaultTextStyle.copyWith(
        fontSize: sizeTitle,
        fontWeight: FontWeight.w700,
        fontVariations: boldWeight,
        height: 1.3,
        color: colors.textPrimary,
      ),
      titleMedium: defaultTextStyle.copyWith(
        fontSize: sizeTitle,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.3,
        color: colors.textPrimary,
      ),
      titleSmall: defaultTextStyle.copyWith(
        fontSize: sizeBody,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.3,
        color: colors.textPrimary,
      ),

      // Body level (14sp w500 / w400)
      bodyLarge: defaultTextStyle.copyWith(
        fontSize: sizeBody,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.4,
        color: colors.textPrimary,
      ),
      bodyMedium: defaultTextStyle.copyWith(
        fontSize: sizeBody,
        fontWeight: FontWeight.w400,
        fontVariations: regularWeight,
        height: 1.4,
        color: colors.textSecondary,
      ),
      bodySmall: defaultTextStyle.copyWith(
        fontSize: sizeLabel,
        fontWeight: FontWeight.w400,
        fontVariations: regularWeight,
        height: 1.4,
        color: colors.textMuted,
      ),

      // Label level (14sp/12sp w500 / w400)
      labelLarge: defaultTextStyle.copyWith(
        fontSize: sizeBody,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.3,
        color: colors.textPrimary,
      ),
      labelMedium: defaultTextStyle.copyWith(
        fontSize: sizeLabel,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.3,
        color: colors.textSecondary,
      ),
      labelSmall: defaultTextStyle.copyWith(
        fontSize: sizeLabel,
        fontWeight: FontWeight.w500,
        fontVariations: mediumWeight,
        height: 1.3,
        color: colors.textMuted,
      ),
    );
  }
}
