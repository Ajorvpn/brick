// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';

/// Parsed country and city/state location metadata extracted from server remark.
@immutable
final class ParsedServerLocation {
  /// Creates parsed server location metadata.
  const ParsedServerLocation({
    required this.countryCode,
    required this.countryName,
    required this.flagEmoji,
    this.cityOrState,
  });

  /// ISO-2 uppercase country code (e.g. 'DE', 'US') or 'ZZ' for unknown.
  final String countryCode;

  /// Canonical English country name (e.g. 'Germany') or 'Other Locations'.
  final String countryName;

  /// Visual flag emoji (e.g. '🇩🇪') or '🌐' for unknown.
  final String flagEmoji;

  /// Specific city or state (e.g. 'Frankfurt', 'New York') or null.
  final String? cityOrState;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedServerLocation &&
          runtimeType == other.runtimeType &&
          countryCode == other.countryCode &&
          countryName == other.countryName &&
          flagEmoji == other.flagEmoji &&
          cityOrState == other.cityOrState;

  @override
  int get hashCode =>
      Object.hash(countryCode, countryName, flagEmoji, cityOrState);

  @override
  String toString() =>
      'ParsedServerLocation($countryCode, $countryName, $flagEmoji, '
      'city: $cityOrState)';
}

/// A collection of servers within a specific city/state (or unspecified city).
@immutable
final class CityLocationGroup {
  /// Creates a city location group.
  const CityLocationGroup({required this.cityOrState, required this.servers});

  /// Specific city or state, or null for general/unspecified country servers.
  final String? cityOrState;

  /// Servers assigned to this city or state.
  final List<SavedServerProfile> servers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CityLocationGroup &&
          runtimeType == other.runtimeType &&
          cityOrState == other.cityOrState &&
          _listEquals(servers, other.servers);

  @override
  int get hashCode =>
      Object.hash(cityOrState, Object.hashAll(servers.map((s) => s.id)));

  static bool _listEquals(
    List<SavedServerProfile> a,
    List<SavedServerProfile> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }
}

/// A collection of city groups and servers within a specific country.
@immutable
final class CountryLocationGroup {
  /// Creates a country location group.
  const CountryLocationGroup({
    required this.countryCode,
    required this.countryName,
    required this.flagEmoji,
    required this.cities,
    required this.totalServerCount,
  });

  /// ISO-2 uppercase country code (e.g. 'DE', 'US') or 'ZZ'.
  final String countryCode;

  /// Canonical English country name (e.g. 'Germany') or 'Other Locations'.
  final String countryName;

  /// Visual flag emoji (e.g. '🇩🇪') or '🌐'.
  final String flagEmoji;

  /// Cities grouped within this country.
  final List<CityLocationGroup> cities;

  /// Total number of servers across all cities in this country.
  final int totalServerCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CountryLocationGroup &&
          runtimeType == other.runtimeType &&
          countryCode == other.countryCode &&
          countryName == other.countryName &&
          flagEmoji == other.flagEmoji &&
          totalServerCount == other.totalServerCount &&
          _listEquals(cities, other.cities);

  @override
  int get hashCode => Object.hash(
    countryCode,
    countryName,
    flagEmoji,
    totalServerCount,
    Object.hashAll(cities),
  );

  static bool _listEquals(
    List<CityLocationGroup> a,
    List<CityLocationGroup> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Pure-Dart parser that infers country and city/state from server remarks.
abstract final class ServerLocationParser {
  /// Sentinel country code assigned when no known ISO-2 country is inferred.
  static const String unknownCountryCode = 'ZZ';

  static const Map<String, String> _countryNames = {
    'DE': 'Germany',
    'US': 'United States',
    'NL': 'Netherlands',
    'GB': 'United Kingdom',
    'FR': 'France',
    'SG': 'Singapore',
    'JP': 'Japan',
    'FI': 'Finland',
    'TR': 'Turkey',
    'CA': 'Canada',
    'CH': 'Switzerland',
    'SE': 'Sweden',
    'PL': 'Poland',
    'AT': 'Austria',
    'HK': 'Hong Kong',
    'KR': 'South Korea',
    'AE': 'United Arab Emirates',
    'IE': 'Ireland',
    'ES': 'Spain',
    'IT': 'Italy',
    'AU': 'Australia',
    'BR': 'Brazil',
    'IN': 'India',
    'RU': 'Russia',
    'UA': 'Ukraine',
    'CY': 'Cyprus',
    'SK': 'Slovakia',
    'HR': 'Croatia',
    'SI': 'Slovenia',
    'GE': 'Georgia',
    'AM': 'Armenia',
    'AL': 'Albania',
    'MT': 'Malta',
    'PA': 'Panama',
    'CO': 'Colombia',
    'PH': 'Philippines',
    'SA': 'Saudi Arabia',
    'QA': 'Qatar',
    'NO': 'Norway',
    'DK': 'Denmark',
    'BE': 'Belgium',
    'CZ': 'Czech Republic',
    'RO': 'Romania',
    'BG': 'Bulgaria',
    'GR': 'Greece',
    'PT': 'Portugal',
    'IL': 'Israel',
    'ZA': 'South Africa',
    'MX': 'Mexico',
    'AR': 'Argentina',
    'CL': 'Chile',
    'ID': 'Indonesia',
    'MY': 'Malaysia',
    'TH': 'Thailand',
    'VN': 'Vietnam',
    'TW': 'Taiwan',
    'NZ': 'New Zealand',
    'IS': 'Iceland',
    'LU': 'Luxembourg',
    'EE': 'Estonia',
    'LV': 'Latvia',
    'LT': 'Lithuania',
    'HU': 'Hungary',
    'RS': 'Serbia',
    'KZ': 'Kazakhstan',
    'MD': 'Moldova',
  };

  static const Map<String, String> _codeAliases = {
    'UK': 'GB',
    'USA': 'US',
    'UAE': 'AE',
  };

  static const Set<String> _ignoredTokens = {
    'VLESS',
    'VMESS',
    'TROJAN',
    'SHADOWSOCKS',
    'SS',
    'HYSTERIA',
    'HYSTERIA2',
    'HY2',
    'TUIC',
    'WIREGUARD',
    'WG',
    'WEBSOCKET',
    'PREMIUM',
    'AWG',
    'AMNEZIAWG',
    'XHTTP',
    'SPLITHTTP',
    'HTTPUPGRADE',
    'VISION',
    'XTLS',
    'UDP',
    'IPV4',
    'IPV6',
    'CF',
    'CLOUDFLARE',
    'WORKER',
    'DIRECT',
    'PROXY',
    'VPN',
    'VIP',
    'PRO',
    'FREE',
    'FAST',
    'AUTO',
    'NEW',
    'TOP',
    'NODE',
    'SERVER',
    'MCI',
    'IRANCELL',
    'MTN',
    'SHATEL',
    'MOKHABERAT',
    'RELAY',
    'EDGE',
    'CDN',
    'WS',
    'GRPC',
    'TLS',
    'REALITY',
    'TCP',
    'HTTP',
    'QUIC',
    'BRICKVPN',
    'BRICK',
  };

  /// Parses [remark] into country and city/state location metadata.
  static ParsedServerLocation parse(String remark) {
    final trimmed = remark.trim();
    if (trimmed.isEmpty) {
      return _fallbackLocation();
    }

    // 1. Detect Unicode Regional Indicator flag emoji pairs (0x1F1E6..0x1F1FF).
    final flagRegex = RegExp(r'[\uD83C][\uDDE6-\uDDFF][\uD83C][\uDDE6-\uDDFF]');
    final flagMatch = flagRegex.firstMatch(trimmed);

    String? detectedCode;
    String? detectedName;
    String? detectedEmoji;

    if (flagMatch != null) {
      final flagStr = flagMatch.group(0)!;
      final runes = flagStr.runes.toList();
      if (runes.length >= 2) {
        final c1 = String.fromCharCode(65 + (runes[0] - 0x1F1E6));
        final c2 = String.fromCharCode(65 + (runes[1] - 0x1F1E6));
        var code = '$c1$c2';
        if (_codeAliases.containsKey(code)) {
          code = _codeAliases[code]!;
        }
        detectedCode = code;
        detectedName = _countryNames[code] ?? code;
        detectedEmoji = flagStr;
      }
    }

    // 2. Fallback: detect full English country names or ISO-2 codes.
    if (detectedCode == null) {
      for (final entry in _sortedCountryNames) {
        final nameRegex = RegExp(
          r'\b' + RegExp.escape(entry.value) + r'\b',
          caseSensitive: false,
        );
        if (nameRegex.hasMatch(trimmed)) {
          detectedCode = entry.key;
          detectedName = entry.value;
          detectedEmoji = emojiForCountryCode(entry.key);
          break;
        }
      }
    }

    if (detectedCode == null) {
      for (final alias in _codeAliases.entries) {
        final pattern = RegExp(
          r'(^|[\s_·|—–\-/,\[\]\(\)])' +
              RegExp.escape(alias.key) +
              r'([\s_·|—–\-/,\[\]\(\)]|$)',
        );
        if (pattern.hasMatch(trimmed)) {
          detectedCode = alias.value;
          detectedName = _countryNames[detectedCode] ?? detectedCode;
          detectedEmoji = emojiForCountryCode(detectedCode);
          break;
        }
      }
    }

    if (detectedCode == null) {
      for (final entry in _countryNames.entries) {
        final pattern = RegExp(
          r'(^|[\s_·|—–\-/,\[\]\(\)])' +
              RegExp.escape(entry.key) +
              r'([\s_·|—–\-/,\[\]\(\)]|$)',
        );
        if (pattern.hasMatch(trimmed)) {
          detectedCode = entry.key;
          detectedName = entry.value;
          detectedEmoji = emojiForCountryCode(entry.key);
          break;
        }
      }
    }

    // Unrecognized remark -> ZZ fallback
    if (detectedCode == null) {
      return _fallbackLocation();
    }

    // 3. Extract cityOrState.
    final city = _extractCity(trimmed, detectedCode, detectedName!);

    return ParsedServerLocation(
      countryCode: detectedCode,
      countryName: detectedName,
      flagEmoji: detectedEmoji!,
      cityOrState: city,
    );
  }

  static ParsedServerLocation _fallbackLocation() {
    return const ParsedServerLocation(
      countryCode: 'ZZ',
      countryName: 'Other Locations',
      flagEmoji: '🌐',
    );
  }

  /// Returns the canonical English country name for [code], or
  /// `'Other Locations'` for [unknownCountryCode].
  static String countryNameForCode(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty || normalized == unknownCountryCode) {
      return 'Other Locations';
    }
    return _countryNames[normalized] ?? normalized;
  }

  /// Converts a 2-letter ISO country code into Unicode flag emoji.
  static String emojiForCountryCode(String code) {
    if (code == 'ZZ' || code.length != 2) return '🌐';
    final upper = code.toUpperCase();
    final c1 = upper.codeUnitAt(0);
    final c2 = upper.codeUnitAt(1);
    if (c1 < 65 || c1 > 90 || c2 < 65 || c2 > 90) return '🌐';
    return String.fromCharCodes([0x1F1E6 + (c1 - 65), 0x1F1E6 + (c2 - 65)]);
  }

  static final List<MapEntry<String, String>> _sortedCountryNames = () {
    return _countryNames.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
  }();

  static String? _extractCity(
    String raw,
    String countryCode,
    String countryName,
  ) {
    // Strip flag emoji
    final s = raw.replaceAll(
      RegExp(r'[\uD83C][\uDDE6-\uDDFF][\uD83C][\uDDE6-\uDDFF]'),
      ' ',
    );

    // Split on delimiters (·, |, —, –, ' - ', _, /, \, ,, :)
    final rawTokens = s.split(RegExp(r'[\u00b7\|—–_/\\,]|\s+-\s+|\s*:\s*'));

    for (var token in rawTokens) {
      // Strip bracketed content like [vless], (vless), (1), [1], [DE], (US)
      token = token
          .replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ')
          .trim();

      // Strip trailing digits attached to words
      // (e.g. Frankfurt01 -> Frankfurt, Tokyo2 -> Tokyo)
      token = token.replaceAll(RegExp(r'(?<=[a-zA-Z])\d+$'), '').trim();

      // Strip trailing counters (#1, #02, -1, bare digits)
      token = token
          .replaceAll(RegExp(r'(?:#\s*\d+|-\d+|\b\d+\b)+$'), '')
          .trim();

      // Skip latency indicators (e.g. 45ms)
      if (RegExp(r'^\d+\s*ms$', caseSensitive: false).hasMatch(token)) {
        continue;
      }

      // Strip leading punctuation or counters (#1, 01 )
      token = token
          .replaceAll(RegExp(r'^(?:#\s*\d*|\d+\s+|[\s\-])+'), '')
          .trim();

      if (token.isEmpty) continue;

      // Skip if token matches country name (e.g. 'Germany')
      if (token.toLowerCase() == countryName.toLowerCase()) continue;

      // Skip if token is the country code or alias
      final upperToken = token.toUpperCase();
      if (upperToken == countryCode ||
          _codeAliases.containsKey(upperToken) ||
          _codeAliases[upperToken] == countryCode) {
        continue;
      }

      // Skip if token is country code + digits/hyphen (e.g. 'NL-04', 'DE01')
      if (RegExp(
        '^(?:$countryCode|UK|USA)[-_#\\s\\d]*\$',
        caseSensitive: false,
      ).hasMatch(token)) {
        continue;
      }

      // Skip if token is an ignored protocol tag
      if (_ignoredTokens.contains(upperToken)) continue;

      // Strip leading ISO-2 country code prefix followed by space or hyphen
      // (e.g. 'DE-Frankfurt', 'DE Frankfurt', 'US-East')
      final isoPrefixRe = RegExp(
        '^(${RegExp.escape(countryCode)}'
        '${countryCode == 'GB' ? '|UK' : ''}'
        '${countryCode == 'US' ? '|USA' : ''})[\\s\\-]+',
        caseSensitive: false,
      );
      token = token.replaceFirst(isoPrefixRe, '').trim();

      // Strip leading country name followed by space or hyphen
      // (e.g. 'Germany-Frankfurt', 'Germany Frankfurt')
      final countryNamePrefixRe = RegExp(
        '^${RegExp.escape(countryName)}[\\s\\-]+',
        caseSensitive: false,
      );
      token = token.replaceFirst(countryNamePrefixRe, '').trim();

      // Re-strip trailing digits attached to words and counters
      token = token.replaceAll(RegExp(r'(?<=[a-zA-Z])\d+$'), '').trim();
      token = token
          .replaceAll(RegExp(r'(?:#\s*\d+|-\d+|\b\d+\b)+$'), '')
          .trim();

      if (token.isEmpty) continue;
      if (token.toLowerCase() == countryName.toLowerCase()) continue;
      if (_ignoredTokens.contains(token.toUpperCase())) continue;

      // Validate length: 2 to 28 characters, strict alphabetic words
      if (token.length >= 2 &&
          token.length <= 28 &&
          RegExp(r'^[a-zA-Z\u00C0-\u024F]+(?:[\s\-][a-zA-Z\u00C0-\u024F]+)*$')
              .hasMatch(token)) {
        return token;
      }
    }

    return null;
  }
}

/// Pure-Dart utility for grouping saved servers into hierarchical locations.
abstract final class ServerLocationGrouper {
  static String _toTitleCase(String text) {
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  /// Groups [servers] into a hierarchical [CountryLocationGroup] structure.
  ///
  /// - If [searchQuery] is provided, servers are filtered case-insensitively
  ///   across server name, protocol label, endpoint, country name,
  ///   country code, and city/state.
  /// - Countries are sorted alphabetically by
  ///   [CountryLocationGroup.countryName], with 'ZZ' ('Other Locations')
  ///   always sorted last.
  /// - Inside each country, cities are sorted alphabetically by
  ///   [CityLocationGroup.cityOrState], with null city sorted last.
  static List<CountryLocationGroup> group(
    List<SavedServerProfile> servers, {
    String searchQuery = '',
  }) {
    final query = searchQuery.trim().toLowerCase();
    final countryMap =
        <
          String,
          ({
            ParsedServerLocation location,
            Map<
              String,
              ({String displayCity, List<SavedServerProfile> servers})
            >
            cities,
            List<SavedServerProfile> nullCityServers,
          })
        >{};

    for (final server in servers) {
      final parsed = ServerLocationParser.parse(server.name);

      if (query.isNotEmpty) {
        final matches =
            server.name.toLowerCase().contains(query) ||
            server.protocolLabel.toLowerCase().contains(query) ||
            server.endpoint.toLowerCase().contains(query) ||
            parsed.countryName.toLowerCase().contains(query) ||
            (parsed.countryCode != 'ZZ' &&
                parsed.countryCode.toLowerCase().contains(query)) ||
            (parsed.cityOrState?.toLowerCase().contains(query) ?? false);
        if (!matches) continue;
      }

      final entry = countryMap.putIfAbsent(
        parsed.countryCode,
        () => (
          location: parsed,
          cities:
              <
                String,
                ({String displayCity, List<SavedServerProfile> servers})
              >{},
          nullCityServers: <SavedServerProfile>[],
        ),
      );

      if (parsed.cityOrState != null) {
        final rawCity = parsed.cityOrState!;
        final cleanCity =
            (rawCity == rawCity.toUpperCase() ||
                rawCity == rawCity.toLowerCase())
            ? _toTitleCase(rawCity)
            : rawCity;
        final normCity = cleanCity.toLowerCase();
        entry.cities
            .putIfAbsent(
              normCity,
              () => (displayCity: cleanCity, servers: <SavedServerProfile>[]),
            )
            .servers
            .add(server);
      } else {
        entry.nullCityServers.add(server);
      }
    }

    if (countryMap.isEmpty) {
      return const <CountryLocationGroup>[];
    }

    final result = <CountryLocationGroup>[];

    for (final entry in countryMap.values) {
      final loc = entry.location;
      final cityGroups = <CityLocationGroup>[];

      for (final cityData in entry.cities.values) {
        cityGroups.add(
          CityLocationGroup(
            cityOrState: cityData.displayCity,
            servers: List<SavedServerProfile>.unmodifiable(cityData.servers),
          ),
        );
      }

      if (entry.nullCityServers.isNotEmpty) {
        cityGroups.add(
          CityLocationGroup(
            cityOrState: null,
            servers: List<SavedServerProfile>.unmodifiable(
              entry.nullCityServers,
            ),
          ),
        );
      }

      // Sort cities alphabetically, with null city last
      cityGroups.sort((a, b) {
        if (a.cityOrState == null && b.cityOrState != null) return 1;
        if (b.cityOrState == null && a.cityOrState != null) return -1;
        if (a.cityOrState == null && b.cityOrState == null) return 0;
        return a.cityOrState!.toLowerCase().compareTo(
          b.cityOrState!.toLowerCase(),
        );
      });

      final totalCount = cityGroups.fold<int>(
        0,
        (sum, group) => sum + group.servers.length,
      );

      result.add(
        CountryLocationGroup(
          countryCode: loc.countryCode,
          countryName: loc.countryName,
          flagEmoji: loc.flagEmoji,
          cities: List<CityLocationGroup>.unmodifiable(cityGroups),
          totalServerCount: totalCount,
        ),
      );
    }

    // Sort countries alphabetically, with 'ZZ' always last
    result.sort((a, b) {
      if (a.countryCode == 'ZZ' && b.countryCode != 'ZZ') return 1;
      if (b.countryCode == 'ZZ' && a.countryCode != 'ZZ') return -1;
      return a.countryName.toLowerCase().compareTo(b.countryName.toLowerCase());
    });

    return List<CountryLocationGroup>.unmodifiable(result);
  }
}
