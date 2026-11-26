// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/platform/battery_optimization_service.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:ui_theme/ui_theme.dart';

/// The application version shown on the About surface.
const String _appVersion = '0.4.0';

/// The license of the application, shown in the about/license surface.
const String _appLicense =
    'GNU General Public License v3.0 or later (GPL-3.0-or-later)';

/// Settings screen for configuring non-secret application preferences.
///
/// Rendered in the "Obsidian Glass & Brick Ember" language as three grouped
/// glass cards: Connection & Resilience, Appearance & Language, and
/// Diagnostics & About. Every provider binding, dialog and semantic key from
/// the pre-redesign implementation is preserved.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.brickColors;

    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider) ?? context.locale;

    final themeSubtitle = switch (themeMode) {
      ThemeMode.system => 'settings.theme_system'.tr(),
      ThemeMode.light => 'settings.theme_light'.tr(),
      ThemeMode.dark => 'settings.theme_dark'.tr(),
    };

    final langSubtitle = locale.languageCode == 'fa'
        ? 'settings.lang_fa'.tr()
        : 'settings.lang_en'.tr();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrickEmblemPlaceholder(size: 24),
            const SizedBox(width: BrickSpacing.xs),
            Flexible(
              child: Text(
                'settings.title'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: BrickSpacing.maxReadableWidth,
            ),
            child: SingleChildScrollView(
              // The floating dock overlays the body (`extendBody`), so this
              // inset keeps the last row reachable.
              padding: EdgeInsets.fromLTRB(
                BrickSpacing.md,
                BrickSpacing.xs,
                BrickSpacing.md,
                MediaQuery.paddingOf(context).bottom + BrickSpacing.xl,
              ),
              child: Column(
                children: [
                  _sectionHeader(
                    title: 'settings.section_connection'.tr(),
                    icon: Icons.security_rounded,
                    isFirst: true,
                  ),
                  BrickGlassCard(
                    padding: EdgeInsets.zero,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: _squircleIcon(
                              Icons.autorenew_rounded,
                              colors,
                            ),
                            title: Text('settings.auto_reconnect'.tr()),
                            subtitle: Text(
                              'settings.auto_reconnect_subtitle'.tr(),
                            ),
                            value: ref.watch(autoReconnectEnabledProvider),
                            onChanged: (value) {
                              // Preference feedback only: the tunnel state
                              // stays owned by the engine.
                              unawaited(HapticFeedback.selectionClick());
                              unawaited(
                                ref
                                    .read(autoReconnectEnabledProvider.notifier)
                                    .setEnabled(enabled: value),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            key: const ValueKey<String>(
                              'settings_kill_switch_tile',
                            ),
                            secondary: _squircleIcon(
                              Icons.gpp_good_outlined,
                              colors,
                            ),
                            title: Text('settings.kill_switch'.tr()),
                            subtitle: Text(
                              'settings.kill_switch_subtitle'.tr(),
                            ),
                            value: ref.watch(killSwitchEnabledProvider),
                            onChanged: (value) {
                              unawaited(HapticFeedback.selectionClick());
                              unawaited(
                                ref
                                    .read(killSwitchEnabledProvider.notifier)
                                    .setEnabled(enabled: value),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'settings_battery_optimization_tile',
                            ),
                            leading: _squircleIcon(
                              Icons.battery_saver_rounded,
                              colors,
                            ),
                            title: Text('settings.battery_optimization'.tr()),
                            subtitle: Text(
                              ref
                                          .watch(
                                            batteryOptimizationIgnoredProvider,
                                          )
                                          .value ==
                                      true
                                  ? 'settings.battery_optimization_unrestricted'
                                        .tr()
                                  : 'settings.battery_optimization_optimized'
                                        .tr(),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () {
                              unawaited(
                                ref
                                    .read(
                                      batteryOptimizationIgnoredProvider
                                          .notifier,
                                    )
                                    .requestExemption(),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  _sectionHeader(
                    title: 'settings.section_appearance'.tr(),
                    icon: Icons.palette_outlined,
                  ),
                  BrickGlassCard(
                    padding: EdgeInsets.zero,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          ListTile(
                            key: const ValueKey<String>('settings_theme_tile'),
                            leading: _squircleIcon(
                              Icons.contrast_rounded,
                              colors,
                            ),
                            title: Text('settings.theme'.tr()),
                            subtitle: Text(themeSubtitle),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _showThemeDialog(context, ref),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'settings_language_tile',
                            ),
                            leading: _squircleIcon(
                              Icons.translate_rounded,
                              colors,
                            ),
                            title: Text('settings.language'.tr()),
                            subtitle: Text(langSubtitle),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _showLanguageDialog(context, ref),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _sectionHeader(
                    title: 'settings.section_diagnostics_about'.tr(),
                    icon: Icons.info_outline_rounded,
                  ),
                  BrickGlassCard(
                    padding: EdgeInsets.zero,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        children: [
                          ListTile(
                            leading: _squircleIcon(
                              Icons.terminal_rounded,
                              colors,
                            ),
                            title: Text('settings.live_logs'.tr()),
                            subtitle: Text('settings.live_logs_subtitle'.tr()),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => context.go('/settings/logs'),
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            key: const ValueKey<String>(
                              'settings_anonymous_probe_tile',
                            ),
                            secondary: _squircleIcon(
                              Icons.insights_rounded,
                              colors,
                            ),
                            title: Text('settings.anonymous_probe'.tr()),
                            subtitle: Text(
                              'settings.anonymous_probe_subtitle'.tr(),
                            ),
                            value: ref.watch(
                              anonymousProbeReportingEnabledProvider,
                            ),
                            onChanged: (value) {
                              // Opt-in only: nothing is buffered or sent until
                              // this switch is on and a collector is compiled
                              // in.
                              unawaited(HapticFeedback.selectionClick());
                              unawaited(
                                ref
                                    .read(
                                      anonymousProbeReportingEnabledProvider
                                          .notifier,
                                    )
                                    .setEnabled(enabled: value),
                              );
                            },
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'settings_privacy_policy_tile',
                            ),
                            leading: _squircleIcon(
                              Icons.privacy_tip_outlined,
                              colors,
                            ),
                            title: Text('settings.privacy_policy'.tr()),
                            subtitle: Text(
                              'settings.privacy_policy_subtitle'.tr(),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _showPrivacyPolicySheet(context),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'settings_license_tile',
                            ),
                            leading: _squircleIcon(Icons.gavel_rounded, colors),
                            title: Text('settings.open_source_license'.tr()),
                            subtitle: Text(
                              'settings.open_source_license_subtitle'.tr(),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _showLicenseDialog(context),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            key: const ValueKey<String>(
                              'settings_version_tile',
                            ),
                            leading: _squircleIcon(
                              Icons.verified_outlined,
                              colors,
                            ),
                            title: Text('settings.about_version'.tr()),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: BrickSpacing.xs,
                                vertical: BrickSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceElevated,
                                borderRadius: BorderRadius.circular(
                                  BrickRadius.xs,
                                ),
                                border: Border.all(color: colors.glassBorder),
                              ),
                              child: Text(
                                _appVersion,
                                style: BrickTypography.monoLog(
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: BrickSpacing.md),
                  Center(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          BrickSpacing.minTouchTarget,
                          BrickSpacing.minTouchTarget,
                        ),
                      ),
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                      child: Text(
                        'settings.back_to_home'.tr(),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader({
    required String title,
    required IconData icon,
    bool isFirst = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        top: isFirst ? BrickSpacing.xs : BrickSpacing.lg,
        bottom: BrickSpacing.xs,
      ),
      child: BrickSectionHeader(title: title, icon: icon),
    );
  }

  /// Compact tinted squircle used as the leading affordance of each row.
  Widget _squircleIcon(IconData icon, BrickSemanticColors colors) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: colors.brandBrick.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BrickRadius.sm),
        border: Border.all(color: colors.glassBorder),
      ),
      child: Icon(icon, size: 18, color: colors.brandBrick),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final colors = dialogContext.brickColors;
          final activeMode = ref.read(themeModeProvider);
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: BrickSpacing.minTouchTarget,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('settings.theme_system'.tr())),
                      if (activeMode == ThemeMode.system)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.brandBrick,
                        ),
                    ],
                  ),
                ),
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: BrickSpacing.minTouchTarget,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('settings.theme_light'.tr())),
                      if (activeMode == ThemeMode.light)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.brandBrick,
                        ),
                    ],
                  ),
                ),
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: BrickSpacing.minTouchTarget,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('settings.theme_dark'.tr())),
                      if (activeMode == ThemeMode.dark)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.brandBrick,
                        ),
                    ],
                  ),
                ),
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
          final colors = dialogContext.brickColors;
          final activeLocale = ref.read(localeProvider) ?? dialogContext.locale;
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: BrickSpacing.minTouchTarget,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('settings.lang_en'.tr())),
                      if (activeLocale.languageCode == 'en')
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.brandBrick,
                        ),
                    ],
                  ),
                ),
              ),
              SimpleDialogOption(
                onPressed: () {
                  const newLocale = Locale('fa');
                  unawaited(
                    ref.read(localeProvider.notifier).setLocale(newLocale),
                  );
                  unawaited(context.setLocale(newLocale));
                  Navigator.of(dialogContext).pop();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: BrickSpacing.minTouchTarget,
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text('settings.lang_fa'.tr())),
                      if (activeLocale.languageCode == 'fa')
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.brandBrick,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPrivacyPolicySheet(BuildContext context) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          final colors = sheetContext.brickColors;
          final sheetTheme = Theme.of(sheetContext);

          return Align(
            key: const ValueKey<String>('settings_privacy_policy_sheet'),
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: BrickSpacing.maxReadableWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(BrickSpacing.md),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: BrickGlassCard(
                      padding: const EdgeInsets.all(BrickSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colors.glassBorder,
                                borderRadius: BorderRadius.circular(
                                  BrickRadius.pill,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: BrickSpacing.sm),
                          Row(
                            children: [
                              Icon(
                                Icons.privacy_tip_outlined,
                                size: 20,
                                color: colors.stateConnected,
                              ),
                              const SizedBox(width: BrickSpacing.xs),
                              Expanded(
                                child: Text(
                                  'settings.privacy_policy'.tr(),
                                  style: sheetTheme.textTheme.titleMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: BrickSpacing.sm),
                          Text(
                            'settings.privacy_policy_body'.tr(),
                            style: sheetTheme.textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: BrickSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            height: BrickSpacing.minTouchTarget,
                            child: FilledButton(
                              key: const ValueKey<String>(
                                'settings_privacy_policy_close_button',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.brandBrick,
                                foregroundColor: colors.onAccent,
                              ),
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: Text('settings.close'.tr()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showLicenseDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final colors = dialogContext.brickColors;
          final dialogTheme = Theme.of(dialogContext);

          return AlertDialog(
            key: const ValueKey<String>('settings_license_dialog'),
            title: Row(
              children: [
                Icon(Icons.gavel_rounded, size: 20, color: colors.brandBrick),
                const SizedBox(width: BrickSpacing.xs),
                Expanded(
                  child: Text(
                    'settings.open_source_license'.tr(),
                    style: dialogTheme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('app_title'.tr(), style: dialogTheme.textTheme.bodyLarge),
                const SizedBox(height: BrickSpacing.xxs),
                Text(
                  '$_appVersion — $_appLicense',
                  style: BrickTypography.monoLog(color: colors.textMuted),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(
                    BrickSpacing.minTouchTarget,
                    BrickSpacing.minTouchTarget,
                  ),
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('settings.close'.tr()),
              ),
              FilledButton(
                key: const ValueKey<String>('settings_view_licenses_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.brandBrick,
                  foregroundColor: colors.onAccent,
                  minimumSize: const Size(
                    BrickSpacing.minTouchTarget,
                    BrickSpacing.minTouchTarget,
                  ),
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  showLicensePage(
                    context: context,
                    useRootNavigator: true,
                    applicationName: 'app_title'.tr(),
                    applicationVersion: _appVersion,
                    applicationLegalese: _appLicense,
                  );
                },
                child: Text('settings.view_licenses'.tr()),
              ),
            ],
          );
        },
      ),
    );
  }
}
