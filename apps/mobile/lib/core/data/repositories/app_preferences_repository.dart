// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language codes Brick VPN ships translations for.
///
/// Persian (`fa`) renders right-to-left; English (`en`) is the fallback.
const Set<String> kSupportedLanguageCodes = <String>{'en', 'fa'};

/// The language code used when a stored preference is missing or unsupported.
const String kFallbackLanguageCode = 'en';

/// Normalizes [locale] to a shipped language code.
///
/// Returns `null` unchanged (system default). A legacy or unknown stored code
/// — including the retired `de` — maps to [kFallbackLanguageCode] so an
/// in-place app upgrade can never crash or render a missing translation.
Locale? normalizeAppLocale(Locale? locale) {
  if (locale == null) return null;
  final code = locale.languageCode.toLowerCase();
  return Locale(
    kSupportedLanguageCodes.contains(code) ? code : kFallbackLanguageCode,
  );
}

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

  /// Default value for persisted location selection when unset or empty.
  static const String defaultSelectedLocation = 'auto';

  /// Reads the persisted active server ID, or `null` if none was selected.
  String? getActiveServerId();

  /// Persists [serverId], or clears it when `null` or empty.
  Future<void> setActiveServerId(String? serverId);

  /// Reads the persisted location target (`'auto'` or `'country:<CODE>'`).
  /// Defaults to [defaultSelectedLocation] (`'auto'`).
  String getSelectedLocation();

  /// Persists the selected location target (`'auto'` or `'country:<CODE>'`).
  Future<void> setSelectedLocation(String value);

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

  /// Reads the timestamp when the current active VPN session started,
  /// or `null`.
  DateTime? getActiveSessionStartedAt();

  /// Persists the active session start timestamp, or clears it when `null`.
  Future<void> setActiveSessionStartedAt(DateTime? timestamp);

  /// Reads whether the first-run onboarding flow was completed.
  /// Defaults to `false` for a fresh install.
  bool hasCompletedOnboarding();

  /// Persists whether the first-run onboarding flow was completed.
  Future<void> setOnboardingCompleted({required bool completed});

  /// Reads whether anonymous server-health diagnostics are enabled.
  ///
  /// Defaults to `false`: strict opt-in. Nothing is buffered or transmitted
  /// until the user turns this on in Settings.
  bool isAnonymousProbeReportingEnabled();

  /// Persists [enabled].
  Future<void> setAnonymousProbeReportingEnabled({required bool enabled});

  /// Reads when the built-in official server directory last synced
  /// successfully, or `null` when it has never synced on this device.
  DateTime? getLastDirectorySyncAt();

  /// Persists the last successful directory sync timestamp, or clears it when
  /// [timestamp] is `null`.
  Future<void> setLastDirectorySyncAt(DateTime? timestamp);

  /// Reads whether the user accepted the server-directory sync disclosure.
  /// Defaults to `false` for a fresh install.
  bool hasAcceptedDirectorySync();

  /// Persists whether the server-directory sync disclosure was accepted.
  Future<void> setDirectorySyncAccepted({required bool accepted});
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

  /// Preference key for the selected connection location target.
  static const String keySelectedLocation =
      'brick.preferences.selected_location';

  /// Preference key for whether auto-reconnect on network change is enabled.
  static const String keyAutoReconnectEnabled =
      'brick.preferences.auto_reconnect_enabled';

  /// Preference key for whether kill switch protection is enabled.
  static const String keyKillSwitchEnabled =
      'brick.preferences.kill_switch_enabled';

  /// Preference key for the active session start timestamp (UTC epoch ms).
  static const String keyActiveSessionStartedAt =
      'brick.preferences.active_session_started_at';

  /// Preference key for whether first-run onboarding was completed.
  static const String keyOnboardingCompleted =
      'brick.preferences.onboarding_completed';

  /// Preference key for the opt-in anonymous server-health diagnostics.
  static const String keyAnonymousProbeReportingEnabled =
      'brick.preferences.anonymous_probe_reporting_enabled';

  /// Preference key for the last successful built-in directory sync.
  static const String keyLastDirectorySyncAt =
      'brick.preferences.last_directory_sync_at';

  /// Preference key for the accepted directory-sync disclosure.
  static const String keyDirectorySyncAccepted =
      'brick.preferences.directory_sync_accepted';

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
    // A device upgrading from a retired locale (e.g. `de`) must never be
    // handed a language the bundle no longer ships: normalize to `en`.
    return normalizeAppLocale(Locale(value));
  }

  @override
  Future<void> setLocale(Locale? locale) async {
    if (locale == null) {
      await _prefs.remove(keyLocale);
    } else {
      await _prefs.setString(
        keyLocale,
        normalizeAppLocale(locale)!.languageCode,
      );
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
  String getSelectedLocation() {
    final value = _prefs.getString(keySelectedLocation)?.trim();
    if (value == null || value.isEmpty) {
      return AppPreferencesRepository.defaultSelectedLocation;
    }
    return value;
  }

  @override
  Future<void> setSelectedLocation(String value) async {
    final trimmed = value.trim();
    final normalized = trimmed.isEmpty
        ? AppPreferencesRepository.defaultSelectedLocation
        : trimmed;
    await _prefs.setString(keySelectedLocation, normalized);
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

  @override
  DateTime? getActiveSessionStartedAt() {
    final ms = _prefs.getInt(keyActiveSessionStartedAt);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> setActiveSessionStartedAt(DateTime? timestamp) async {
    if (timestamp == null) {
      await _prefs.remove(keyActiveSessionStartedAt);
    } else {
      await _prefs.setInt(
        keyActiveSessionStartedAt,
        timestamp.toUtc().millisecondsSinceEpoch,
      );
    }
  }

  @override
  bool hasCompletedOnboarding() {
    return _prefs.getBool(keyOnboardingCompleted) ?? false;
  }

  @override
  Future<void> setOnboardingCompleted({required bool completed}) async {
    await _prefs.setBool(keyOnboardingCompleted, completed);
  }

  @override
  bool isAnonymousProbeReportingEnabled() {
    return _prefs.getBool(keyAnonymousProbeReportingEnabled) ?? false;
  }

  @override
  Future<void> setAnonymousProbeReportingEnabled({
    required bool enabled,
  }) async {
    await _prefs.setBool(keyAnonymousProbeReportingEnabled, enabled);
  }

  @override
  DateTime? getLastDirectorySyncAt() {
    final ms = _prefs.getInt(keyLastDirectorySyncAt);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> setLastDirectorySyncAt(DateTime? timestamp) async {
    if (timestamp == null) {
      await _prefs.remove(keyLastDirectorySyncAt);
    } else {
      await _prefs.setInt(
        keyLastDirectorySyncAt,
        timestamp.toUtc().millisecondsSinceEpoch,
      );
    }
  }

  @override
  bool hasAcceptedDirectorySync() {
    return _prefs.getBool(keyDirectorySyncAccepted) ?? false;
  }

  @override
  Future<void> setDirectorySyncAccepted({required bool accepted}) async {
    await _prefs.setBool(keyDirectorySyncAccepted, accepted);
  }
}

/// In-memory fake implementation of [AppPreferencesRepository] for unit/widget
/// tests.
class FakeAppPreferencesRepository implements AppPreferencesRepository {
  /// Creates a fake repository with optional initial [initialThemeMode],
  /// [initialLocale], [initialActiveServerId],
  /// [initialAutoReconnectEnabled], [initialKillSwitchEnabled], and
  /// [initialOnboardingCompleted].
  ///
  /// [initialOnboardingCompleted] defaults to `true` so every existing widget
  /// and end-to-end test boots straight into the app shell; only first-run
  /// onboarding tests opt into `false`.
  ///
  /// [initialAnonymousProbeReportingEnabled] defaults to `false`, mirroring the
  /// strict opt-in default of production storage.
  FakeAppPreferencesRepository({
    ThemeMode initialThemeMode = ThemeMode.system,
    Locale? initialLocale,
    String? initialActiveServerId,
    String initialSelectedLocation =
        AppPreferencesRepository.defaultSelectedLocation,
    bool initialAutoReconnectEnabled = true,
    bool initialKillSwitchEnabled = false,
    DateTime? initialActiveSessionStartedAt,
    bool initialOnboardingCompleted = true,
    bool initialAnonymousProbeReportingEnabled = false,
    DateTime? initialLastDirectorySyncAt,
    bool initialDirectorySyncAccepted = false,
  }) : _themeMode = initialThemeMode,
       _locale = initialLocale,
       _activeServerId = initialActiveServerId,
       _selectedLocation = initialSelectedLocation.trim().isEmpty
           ? AppPreferencesRepository.defaultSelectedLocation
           : initialSelectedLocation.trim(),
       _autoReconnectEnabled = initialAutoReconnectEnabled,
       _killSwitchEnabled = initialKillSwitchEnabled,
       _activeSessionStartedAt = initialActiveSessionStartedAt?.toUtc(),
       _onboardingCompleted = initialOnboardingCompleted,
       _anonymousProbeReportingEnabled = initialAnonymousProbeReportingEnabled,
       _lastDirectorySyncAt = initialLastDirectorySyncAt?.toUtc(),
       _directorySyncAccepted = initialDirectorySyncAccepted;

  ThemeMode _themeMode;
  Locale? _locale;
  String? _activeServerId;
  String _selectedLocation;
  bool _autoReconnectEnabled;
  bool _killSwitchEnabled;
  DateTime? _activeSessionStartedAt;
  bool _onboardingCompleted;
  bool _anonymousProbeReportingEnabled;
  DateTime? _lastDirectorySyncAt;
  bool _directorySyncAccepted;

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
  String getSelectedLocation() => _selectedLocation;

  @override
  Future<void> setSelectedLocation(String value) async {
    final trimmed = value.trim();
    _selectedLocation = trimmed.isEmpty
        ? AppPreferencesRepository.defaultSelectedLocation
        : trimmed;
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

  @override
  DateTime? getActiveSessionStartedAt() => _activeSessionStartedAt;

  @override
  Future<void> setActiveSessionStartedAt(DateTime? timestamp) async {
    _activeSessionStartedAt = timestamp?.toUtc();
  }

  @override
  bool hasCompletedOnboarding() => _onboardingCompleted;

  @override
  Future<void> setOnboardingCompleted({required bool completed}) async {
    _onboardingCompleted = completed;
  }

  @override
  bool isAnonymousProbeReportingEnabled() => _anonymousProbeReportingEnabled;

  @override
  Future<void> setAnonymousProbeReportingEnabled({
    required bool enabled,
  }) async {
    _anonymousProbeReportingEnabled = enabled;
  }

  @override
  DateTime? getLastDirectorySyncAt() => _lastDirectorySyncAt;

  @override
  Future<void> setLastDirectorySyncAt(DateTime? timestamp) async {
    _lastDirectorySyncAt = timestamp?.toUtc();
  }

  @override
  bool hasAcceptedDirectorySync() => _directorySyncAccepted;

  @override
  Future<void> setDirectorySyncAccepted({required bool accepted}) async {
    _directorySyncAccepted = accepted;
  }
}
