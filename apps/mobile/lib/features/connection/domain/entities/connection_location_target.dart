// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// User-selected connection target in the simplified Smart Auto /
/// Country-Only UX.
///
/// Serialized cleanly into non-secret `SharedPreferences` as `'auto'` or
/// `'country:<ISO2>'` (e.g. `'country:GB'`, `'country:DE'`, `'country:ZZ'`).
@immutable
sealed class ConnectionLocationTarget {
  /// Const constructor for subclasses.
  const ConnectionLocationTarget();

  /// Restores a [ConnectionLocationTarget] from its stored preference string.
  ///
  /// Null, empty, or malformed values safely fall back to [SmartAutoTarget].
  factory ConnectionLocationTarget.fromStorageKey(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'auto') {
      return const SmartAutoTarget();
    }
    const prefix = 'country:';
    if (trimmed.startsWith(prefix)) {
      final code = trimmed.substring(prefix.length).trim().toUpperCase();
      if (code.isNotEmpty) {
        return CountryTarget(code);
      }
    }
    return const SmartAutoTarget();
  }

  /// Canonical storage representation (`'auto'` or `'country:<CODE>'`).
  String get storageKey;
}

/// Global Smart Auto target — lets sing-box `urltest` probe diversified
/// candidates across all available countries and pick the fastest node.
@immutable
final class SmartAutoTarget extends ConnectionLocationTarget {
  /// Creates a Smart Auto target.
  const SmartAutoTarget();

  @override
  String get storageKey => 'auto';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SmartAutoTarget;

  @override
  int get hashCode => (SmartAutoTarget).hashCode;
}

/// Country-scoped target — lets sing-box `urltest` probe servers within a
/// single country code ([countryCode], e.g. `'GB'`, `'DE'`, `'ZZ'`).
@immutable
final class CountryTarget extends ConnectionLocationTarget {
  /// Creates a country-scoped target for normalized [countryCode].
  CountryTarget(String countryCode)
    : countryCode = countryCode.trim().toUpperCase();

  /// Canonical uppercase ISO-3166 alpha-2 code (or `'ZZ'` for Other Locations).
  final String countryCode;

  @override
  String get storageKey => 'country:$countryCode';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryTarget && other.countryCode == countryCode;

  @override
  int get hashCode => Object.hash(CountryTarget, countryCode);
}
