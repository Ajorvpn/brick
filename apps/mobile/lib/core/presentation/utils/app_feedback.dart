// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

/// Centralized presentation utility for transient user feedback (e.g.
/// snackbars).
///
/// In accordance with P4-T3 and `CODING_STANDARDS.md` Section 5.1, all
/// transient notifications, banners, and snackbars must be presented via this
/// helper. Features must never invent ad-hoc snackbars or error presentation
/// UI.
///
/// This implementation is visually minimal, adhering to Material 3 semantics.
class AppFeedback {
  AppFeedback._();

  /// Displays an error feedback message in a floating [SnackBar].
  ///
  /// Clears any currently visible snackbar before presenting the error.
  static void showError(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final theme = Theme.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: theme.colorScheme.onError),
          ),
          backgroundColor: theme.colorScheme.error,
          behavior: SnackBarBehavior.floating,
          action: action,
          duration: duration,
        ),
      );
  }

  /// Displays a success feedback message in a floating [SnackBar].
  static void showSuccess(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: action,
          duration: duration,
        ),
      );
  }

  /// Displays an informational feedback message in a floating [SnackBar].
  static void showInfo(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: action,
          duration: duration,
        ),
      );
  }
}
