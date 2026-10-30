// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';

/// Settings screen for configuring non-secret application preferences.
///
/// Manages theme mode, display language, and provides navigation to diagnostics
/// such as Live Logs.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider) ?? context.locale;

    final themeSubtitle = switch (themeMode) {
      ThemeMode.system => 'settings.theme_system'.tr(),
      ThemeMode.light => 'settings.theme_light'.tr(),
      ThemeMode.dark => 'settings.theme_dark'.tr(),
    };

    final langSubtitle = locale.languageCode == 'de'
        ? 'settings.lang_de'.tr()
        : 'settings.lang_en'.tr();

    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr())),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text('settings.language'.tr()),
            subtitle: Text(langSubtitle),
            onTap: () => _showLanguageDialog(context, ref),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text('settings.theme'.tr()),
            subtitle: Text(themeSubtitle),
            onTap: () => _showThemeDialog(context, ref),
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

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            title: Text('settings.theme'.tr()),
            children: [
              SimpleDialogOption(
                onPressed: () {
                  unawaited(
                    ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(ThemeMode.system),
                  );
                  Navigator.of(dialogContext).pop();
                },
                child: Text('settings.theme_system'.tr()),
              ),
              SimpleDialogOption(
                onPressed: () {
                  unawaited(
                    ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(ThemeMode.light),
                  );
                  Navigator.of(dialogContext).pop();
                },
                child: Text('settings.theme_light'.tr()),
              ),
              SimpleDialogOption(
                onPressed: () {
                  unawaited(
                    ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(ThemeMode.dark),
                  );
                  Navigator.of(dialogContext).pop();
                },
                child: Text('settings.theme_dark'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLanguageDialog(BuildContext context, WidgetRef ref) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return SimpleDialog(
            title: Text('settings.language'.tr()),
            children: [
              SimpleDialogOption(
                onPressed: () {
                  const newLocale = Locale('en');
                  unawaited(
                    ref.read(localeProvider.notifier).setLocale(newLocale),
                  );
                  unawaited(context.setLocale(newLocale));
                  Navigator.of(dialogContext).pop();
                },
                child: Text('settings.lang_en'.tr()),
              ),
              SimpleDialogOption(
                onPressed: () {
                  const newLocale = Locale('de');
                  unawaited(
                    ref.read(localeProvider.notifier).setLocale(newLocale),
                  );
                  unawaited(context.setLocale(newLocale));
                  Navigator.of(dialogContext).pop();
                },
                child: Text('settings.lang_de'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }
}
