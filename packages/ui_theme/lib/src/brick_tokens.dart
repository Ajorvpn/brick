// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/animation.dart';

/// Spacing and sizing tokens following a strict 8-point (divisible by 4/8) grid system.
abstract final class BrickSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double section = 64.0;
  static const double hero = 80.0;

  // Component-specific spatial tokens
  static const double screenHorizontal = 16.0;
  static const double cardPadding = 24.0;
  static const double cardPaddingCompact = 16.0;

  // Layout & accessibility geometry
  static const double minTouchTarget = 48.0;
  static const double maxReadableWidth = 600.0;
  static const double orbDiameter = 164.0;
}

/// Corner radius tokens for cards, sheets, buttons, and inputs.
abstract final class BrickRadius {
  static const double xs = 6.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double card = 16.0;
  static const double cardLarge = 20.0;
  static const double sheet = 24.0;
  static const double pill = 999.0;
}

/// Duration and curve tokens for consistent, purposeful motion and micro-interactions.
abstract final class BrickMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration stateTransition = Duration(milliseconds: 350);
  static const Duration orbPulse = Duration(milliseconds: 1800);

  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeInOutCubicEmphasized;
}
