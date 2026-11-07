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

  /// Reads the persisted active server ID, or `null` if none was selected.
  String? getActiveServerId();

  /// Persists [serverId], or clears it when `null` or empty.
  Future<void> setActiveServerId(String? serverId);

  /// Reads whether auto-reconnect on network change is enabled.
  /// Defaults to `true`.
  bool isAutoReconnectEnabled();

  /// Persists [enabled].
  Future<void> setAutoReconnectEnabled({required bool enabled});

  /// Reads whether kill switch protection is enabled.
  /// Defaults to `false`.
  bool isKillSwitchEnabled();

  /// Persists [enabled].
  Future<void> setKillSwitchEnabled({required bool enabled});
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

  /// Preference key for the selected active server ID.
  static const String keyActiveServerId = 'brick.preferences.active_server_id';

  /// Preference key for whether auto-reconnect on network change is enabled.
  static const String keyAutoReconnectEnabled =
      'brick.preferences.auto_reconnect_enabled';

  /// Preference key for whether kill switch protection is enabled.
  static const String keyKillSwitchEnabled =
      'brick.preferences.kill_switch_enabled';

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

  @override
  String? getActiveServerId() {
    final value = _prefs.getString(keyActiveServerId);
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  @override
  Future<void> setActiveServerId(String? serverId) async {
    if (serverId == null || serverId.isEmpty) {
      await _prefs.remove(keyActiveServerId);
    } else {
      await _prefs.setString(keyActiveServerId, serverId);
    }
  }

  @override
  bool isAutoReconnectEnabled() {
    return _prefs.getBool(keyAutoReconnectEnabled) ?? true;
  }

  @override
  Future<void> setAutoReconnectEnabled({required bool enabled}) async {
    await _prefs.setBool(keyAutoReconnectEnabled, enabled);
  }

  @override
  bool isKillSwitchEnabled() {
    return _prefs.getBool(keyKillSwitchEnabled) ?? false;
  }

  @override
  Future<void> setKillSwitchEnabled({required bool enabled}) async {
    await _prefs.setBool(keyKillSwitchEnabled, enabled);
  }
}

/// In-memory fake implementation of [AppPreferencesRepository] for unit/widget
/// tests.
class FakeAppPreferencesRepository implements AppPreferencesRepository {
  /// Creates a fake repository with optional initial [initialThemeMode],
  /// [initialLocale], [initialActiveServerId],
  /// [initialAutoReconnectEnabled], and [initialKillSwitchEnabled].
  FakeAppPreferencesRepository({
    ThemeMode initialThemeMode = ThemeMode.system,
    Locale? initialLocale,
    String? initialActiveServerId,
    bool initialAutoReconnectEnabled = true,
    bool initialKillSwitchEnabled = false,
  }) : _themeMode = initialThemeMode,
       _locale = initialLocale,
       _activeServerId = initialActiveServerId,
       _autoReconnectEnabled = initialAutoReconnectEnabled,
       _killSwitchEnabled = initialKillSwitchEnabled;

  ThemeMode _themeMode;
  Locale? _locale;
  String? _activeServerId;
  bool _autoReconnectEnabled;
  bool _killSwitchEnabled;

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

  @override
  String? getActiveServerId() => _activeServerId;

  @override
  Future<void> setActiveServerId(String? serverId) async {
    _activeServerId = (serverId != null && serverId.isNotEmpty)
        ? serverId
        : null;
  }

  @override
  bool isAutoReconnectEnabled() => _autoReconnectEnabled;

  @override
  Future<void> setAutoReconnectEnabled({required bool enabled}) async {
    _autoReconnectEnabled = enabled;
  }

  @override
  bool isKillSwitchEnabled() => _killSwitchEnabled;

  @override
  Future<void> setKillSwitchEnabled({required bool enabled}) async {
    _killSwitchEnabled = enabled;
  }
}
