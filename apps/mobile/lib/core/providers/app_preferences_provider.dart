// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_preferences_provider.g.dart';

/// Provides the active [AppPreferencesRepository] instance.
///
/// Defaults to [FakeAppPreferencesRepository] so tests and detached widgets
/// function without platform channel setup, and overridden with
/// [SharedPreferencesAppPreferencesRepository] in production `main()`.
@Riverpod(keepAlive: true)
AppPreferencesRepository appPreferencesRepository(Ref ref) {
  return FakeAppPreferencesRepository();
}

/// Manages and persists the active [ThemeMode].
@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier {
  @override
  ThemeMode build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return repo.getThemeMode();
  }

  /// Updates and persists the selected [mode].
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setThemeMode(mode);
  }
}

/// Manages and persists the active [Locale].
@Riverpod(keepAlive: true)
class LocaleNotifier extends _$LocaleNotifier {
  @override
  Locale? build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    // Normalized so a legacy stored code (`de`) falls back to `en` instead of
    // asking easy_localization for a bundle that no longer exists.
    return normalizeAppLocale(repo.getLocale());
  }

  /// Updates and persists the selected [locale], or `null` for system default.
  Future<void> setLocale(Locale? locale) async {
    final normalized = normalizeAppLocale(locale);
    state = normalized;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setLocale(normalized);
  }
}

/// Manages and persists whether auto-reconnect is enabled.
class AutoReconnectEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return repo.isAutoReconnectEnabled();
  }

  /// Updates and persists the preference.
  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setAutoReconnectEnabled(enabled: enabled);
  }
}

/// Provides whether auto-reconnect on network change is enabled.
final autoReconnectEnabledProvider =
    NotifierProvider<AutoReconnectEnabledNotifier, bool>(
      AutoReconnectEnabledNotifier.new,
    );

/// Manages and persists whether kill switch protection is enabled.
class KillSwitchEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return repo.isKillSwitchEnabled();
  }

  /// Updates and persists the preference.
  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setKillSwitchEnabled(enabled: enabled);
  }
}

/// Provides whether kill switch protection is enabled.
final killSwitchEnabledProvider =
    NotifierProvider<KillSwitchEnabledNotifier, bool>(
      KillSwitchEnabledNotifier.new,
    );

/// Manages and persists whether the first-run onboarding was completed.
///
/// Deliberately a plain [Notifier] rather than a `@Riverpod` annotation so no
/// code generation is required; it mirrors [AutoReconnectEnabledNotifier].
class OnboardingCompletedNotifier extends Notifier<bool> {
  @override
  bool build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return repo.hasCompletedOnboarding();
  }

  /// Marks onboarding as completed in state and in storage.
  Future<void> markCompleted() async {
    state = true;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setOnboardingCompleted(completed: true);
  }
}

/// Provides whether the first-run onboarding flow was completed.
final onboardingCompletedProvider =
    NotifierProvider<OnboardingCompletedNotifier, bool>(
      OnboardingCompletedNotifier.new,
    );

/// Manages and persists the opt-in for anonymous server-health diagnostics.
///
/// Mirrors [KillSwitchEnabledNotifier]: the default is `false`, so diagnostics
/// stay strictly opt-in, and flipping the switch writes through to storage
/// immediately.
class AnonymousProbeReportingEnabledNotifier extends Notifier<bool> {
  @override
  bool build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return repo.isAnonymousProbeReportingEnabled();
  }

  /// Updates and persists the preference.
  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setAnonymousProbeReportingEnabled(enabled: enabled);
  }
}

/// Provides whether anonymous server-health diagnostics are enabled.
final anonymousProbeReportingEnabledProvider =
    NotifierProvider<AnonymousProbeReportingEnabledNotifier, bool>(
      AnonymousProbeReportingEnabledNotifier.new,
    );
