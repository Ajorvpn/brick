// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
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
    return repo.getLocale();
  }

  /// Updates and persists the selected [locale], or `null` for system default.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setLocale(locale);
  }
}
