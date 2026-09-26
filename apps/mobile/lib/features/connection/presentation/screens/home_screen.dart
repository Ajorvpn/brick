// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Placeholder Home screen for the `connection` feature (P1-T8).
///
/// Intentionally minimal: a plain [Scaffold] with a text label and one
/// navigation button. Visual polish is out of scope until Phase 11
/// (ROADMAP P1-T8). This screen's only job is to prove the routing
/// skeleton works end to end.
///
/// Layering: this is a `presentation/` file. It may depend on `domain/`
/// but never on `data/` (CODING_STANDARDS.md Section 3.2).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Brick VPN')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Home'),
            const SizedBox(height: 16),
            TextButton(
              // `context.push` keeps the route on the navigation stack so
              // the Settings screen can pop back here.
              onPressed: () => context.push('/settings'),
              child: const Text('Go to Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
