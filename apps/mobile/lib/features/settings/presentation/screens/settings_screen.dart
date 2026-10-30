// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
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
/// Every user-facing string is looked up via `.tr()` from
/// `assets/translations/en.json`; hardcoded strings are forbidden
/// (CODING_STANDARDS.md).
///
/// Layering: this is a `presentation/` file. It may depend on `domain/`
/// but never on `data/` (CODING_STANDARDS.md Section 3.2).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text('settings.language'.tr()),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text('settings.theme'.tr()),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: Text('settings.live_logs'.tr()),
            subtitle: Text('settings.live_logs_subtitle'.tr()),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/logs'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: () => context.pop(),
              child: Text('settings.back_to_home'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
