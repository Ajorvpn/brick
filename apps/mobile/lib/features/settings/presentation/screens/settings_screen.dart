// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Placeholder Settings screen (P1-T8).
///
/// Intentionally minimal: a plain [Scaffold] with a text label and a
/// back-navigation button. Visual polish and real settings content are out
/// of scope until Phase 11 and the later feature tasks (ROADMAP P1-T8).
///
/// The `settings` feature folder exists only to the extent needed for this
/// placeholder; its `domain/` and `data/` layers follow the P1-T6
/// convention and are empty until Settings gains real functionality.
///
/// Layering: this is a `presentation/` file. It may depend on `domain/`
/// but never on `data/` (CODING_STANDARDS.md Section 3.2).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Settings'),
            const SizedBox(height: 16),
            TextButton(
              // `pop` returns to the previous route (Home), which is the
              // behaviour the placeholder is meant to demonstrate.
              onPressed: () => context.pop(),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
