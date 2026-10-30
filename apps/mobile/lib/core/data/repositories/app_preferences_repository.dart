// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository contract for non-secret, local application preferences.
///
/// ============================================================================
/// CRITICAL SECURITY BOUNDARY — NON-SECRET PREFERENCES ONLY (SECURITY.md)
/// ============================================================================
/// Per `SECURITY.md` Section 2 (Data Classification), this repository and its
/// underlying plaintext storage (e.g., `SharedPreferences`) are STRICTLY
/// RESTRICTED to `None`- and `Low`-sensitivity data (e.g., selected ThemeMode,
/// selected Locale, non-secret UI flags).
///
/// UNDER NO CIRCUMSTANCES may this repository or any class implementing it be
/// used to store `High`-sensitivity data, including:
///  - Server configurations (VLESS, VMess, Trojan, Shadowsocks, TUIC,
///    Hysteria2)
///  - Credentials, passwords, keys, private UUIDs, or subscription URLs
///  - Diagnostic logs containing server hostnames, IPs, or credentials
///  - Any user-identifying data
///
/// Storing server credentials in plaintext storage is a severe security
/// violation. Sensitive data MUST wait for Phase 8 platform-native encrypted
/// storage (Android Keystore / EncryptedSharedPreferences).
/// ============================================================================
abstract class AppPreferencesRepository {
  /// Reads the persisted theme mode. Defaults to [ThemeMode.system].
  ThemeMode getThemeMode();

  /// Persists [themeMode].
  Future<void> setThemeMode(ThemeMode themeMode);

  /// Reads the persisted locale, or returns `null` if using system default.
  Locale? getLocale();

  /// Persists [locale], or clears it when `null` to follow system default.
  Future<void> setLocale(Locale? locale);
}

/// Concrete implementation of [AppPreferencesRepository] backed by
/// [SharedPreferences].
///
/// Strictly stores `None`-sensitivity preferences only.
class SharedPreferencesAppPreferencesRepository
    implements AppPreferencesRepository {
  /// Creates a repository backed by the given [SharedPreferences] instance.
  SharedPreferencesAppPreferencesRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Preference key for the selected theme mode.
  static const String keyThemeMode = 'app_theme_mode';

  /// Preference key for the selected language code.
  static const String keyLocale = 'app_locale';

  @override
  ThemeMode getThemeMode() {
    final value = _prefs.getString(keyThemeMode);
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> setThemeMode(ThemeMode themeMode) async {
    final value = switch (themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(keyThemeMode, value);
  }

  @override
  Locale? getLocale() {
    final value = _prefs.getString(keyLocale);
    if (value == null || value.isEmpty) {
      return null;
    }
    return Locale(value);
  }

  @override
  Future<void> setLocale(Locale? locale) async {
    if (locale == null) {
      await _prefs.remove(keyLocale);
    } else {
      await _prefs.setString(keyLocale, locale.languageCode);
    }
  }
}

/// In-memory fake implementation of [AppPreferencesRepository] for unit/widget
/// tests.
class FakeAppPreferencesRepository implements AppPreferencesRepository {
  /// Creates a fake repository with optional initial [initialThemeMode] and
  /// [initialLocale].
  FakeAppPreferencesRepository({
    ThemeMode initialThemeMode = ThemeMode.system,
    Locale? initialLocale,
  }) : _themeMode = initialThemeMode,
       _locale = initialLocale;

  ThemeMode _themeMode;
  Locale? _locale;

  @override
  ThemeMode getThemeMode() => _themeMode;

  @override
  Future<void> setThemeMode(ThemeMode themeMode) async {
    _themeMode = themeMode;
  }

  @override
  Locale? getLocale() => _locale;

  @override
  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
  }
}
