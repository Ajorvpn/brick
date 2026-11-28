// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:math' as math;

import 'package:core_domain/core_domain.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';

/// Builds a prioritized failover candidate pool for sing-box `urltest`.
///
/// Always places the user-selected primary server first, deduplicates by
/// profile ID, excludes runtime-unsupported `AmneziaWgOutbound` profiles, and
/// diversifies failover candidates by country and protocol up to
/// [defaultMaxCandidates].
final class ConnectionCandidatePoolBuilder {
  const ConnectionCandidatePoolBuilder._();

  /// Maximum candidate count matching sing-box `URLTestOutbounds` concurrency.
  static const int defaultMaxCandidates = 10;

  /// Builds an ordered failover pool starting with [primary].
  ///
  /// - Returns an empty list if [maxCandidates] <= 0 or [primary] itself uses
  ///   `AmneziaWgOutbound`.
  /// - When [restrictToCountryCode] is non-empty, only candidates matching that
  ///   ISO country code are selected, rotated across protocols (non-primary
  ///   protocols first).
  /// - Otherwise (global mode), picks up to 2 diverse-protocol siblings in
  ///   [primary]'s country first, then round-robins across remaining countries
  ///   prioritizing underrepresented protocols, and tops up from leftover
  ///   eligible servers up to [maxCandidates].
  static List<ServerProfile> buildCandidatePool({
    required ServerProfile primary,
    required List<ServerProfile> allServers,
    String? restrictToCountryCode,
    int maxCandidates = defaultMaxCandidates,
  }) {
    if (maxCandidates <= 0 || primary.config is AmneziaWgOutbound) {
      return const <ServerProfile>[];
    }

    final pool = <ServerProfile>[primary];
    if (maxCandidates == 1) {
      return List<ServerProfile>.unmodifiable(pool);
    }

    final seenIds = <String>{primary.id};
    final eligible = <_PoolCandidate>[];
    for (final server in allServers) {
      if (server.config is AmneziaWgOutbound) {
        continue;
      }
      if (!seenIds.add(server.id)) {
        continue;
      }
      final location = ServerLocationParser.parse(server.name);
      eligible.add(
        _PoolCandidate(
          profile: server,
          countryCode: location.countryCode,
          protocol: server.config.protocol,
        ),
      );
    }

    if (eligible.isEmpty) {
      return List<ServerProfile>.unmodifiable(pool);
    }

    final primaryLocation = ServerLocationParser.parse(primary.name);
    final primaryProtocol = primary.config.protocol;
    final remainingSlots = maxCandidates - 1;

    final normalizedCountryFilter = restrictToCountryCode?.trim().toUpperCase();
    if (normalizedCountryFilter != null && normalizedCountryFilter.isNotEmpty) {
      final matching = eligible
          .where((c) => c.countryCode == normalizedCountryFilter)
          .toList(growable: false);
      final selected = _takeProtocolRoundRobin(
        matching,
        primaryProtocol: primaryProtocol,
        limit: remainingSlots,
      );
      pool.addAll(selected.map((c) => c.profile));
      return List<ServerProfile>.unmodifiable(pool);
    }

    final pickedIds = <String>{};

    // 1. Up to 2 diverse-protocol siblings in primary's country.
    final sameCountry = eligible
        .where((c) => c.countryCode == primaryLocation.countryCode)
        .toList(growable: false);
    final sameCountryPicked = _takeProtocolRoundRobin(
      sameCountry,
      primaryProtocol: primaryProtocol,
      limit: math.min(2, remainingSlots),
    );
    for (final candidate in sameCountryPicked) {
      pickedIds.add(candidate.profile.id);
      pool.add(candidate.profile);
    }

    if (pool.length >= maxCandidates) {
      return List<ServerProfile>.unmodifiable(pool);
    }

    // 2. Round-robin across remaining countries, favoring protocols that appear
    // fewest times in `pool` (and non-primary protocols on ties).
    final protocolCounts = <ProtocolType, int>{primaryProtocol: 1};
    for (final candidate in sameCountryPicked) {
      protocolCounts.update(
        candidate.protocol,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final otherCountryQueues = <String, List<_PoolCandidate>>{};
    for (final candidate in eligible) {
      if (candidate.countryCode == primaryLocation.countryCode ||
          pickedIds.contains(candidate.profile.id)) {
        continue;
      }
      otherCountryQueues
          .putIfAbsent(candidate.countryCode, () => <_PoolCandidate>[])
          .add(candidate);
    }

    final countryKeys = otherCountryQueues.keys.toList(growable: false);
    while (pool.length < maxCandidates) {
      var progressed = false;
      for (final country in countryKeys) {
        if (pool.length >= maxCandidates) {
          break;
        }
        final queue = otherCountryQueues[country]!;
        if (queue.isEmpty) {
          continue;
        }
        final nextIndex = _pickMostDiverseIndex(
          queue,
          protocolCounts: protocolCounts,
          primaryProtocol: primaryProtocol,
        );
        final chosen = queue.removeAt(nextIndex);
        pickedIds.add(chosen.profile.id);
        pool.add(chosen.profile);
        protocolCounts.update(
          chosen.protocol,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        progressed = true;
      }
      if (!progressed) {
        break;
      }
    }

    // 3. Top up from any remaining eligible servers (e.g. small subscriptions).
    if (pool.length < maxCandidates) {
      for (final candidate in eligible) {
        if (pool.length >= maxCandidates) {
          break;
        }
        if (pickedIds.add(candidate.profile.id)) {
          pool.add(candidate.profile);
        }
      }
    }

    return List<ServerProfile>.unmodifiable(pool);
  }

  static List<_PoolCandidate> _takeProtocolRoundRobin(
    List<_PoolCandidate> items, {
    required ProtocolType primaryProtocol,
    required int limit,
  }) {
    if (items.isEmpty || limit <= 0) {
      return const <_PoolCandidate>[];
    }
    final buckets = <ProtocolType, Queue<_PoolCandidate>>{};
    for (final item in items) {
      buckets.putIfAbsent(item.protocol, Queue<_PoolCandidate>.new).add(item);
    }

    final orderedProtocols = <ProtocolType>[
      for (final protocol in buckets.keys)
        if (protocol != primaryProtocol) protocol,
      if (buckets.containsKey(primaryProtocol)) primaryProtocol,
    ];

    final picked = <_PoolCandidate>[];
    while (picked.length < limit) {
      var progressed = false;
      for (final protocol in orderedProtocols) {
        if (picked.length >= limit) {
          break;
        }
        final queue = buckets[protocol]!;
        if (queue.isEmpty) {
          continue;
        }
        picked.add(queue.removeFirst());
        progressed = true;
      }
      if (!progressed) {
        break;
      }
    }
    return picked;
  }

  static int _pickMostDiverseIndex(
    List<_PoolCandidate> candidates, {
    required Map<ProtocolType, int> protocolCounts,
    required ProtocolType primaryProtocol,
  }) {
    var bestIndex = 0;
    var bestScore = _diversityScore(
      candidates.first.protocol,
      protocolCounts: protocolCounts,
      primaryProtocol: primaryProtocol,
    );
    for (var i = 1; i < candidates.length; i++) {
      final score = _diversityScore(
        candidates[i].protocol,
        protocolCounts: protocolCounts,
        primaryProtocol: primaryProtocol,
      );
      if (score < bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  static int _diversityScore(
    ProtocolType protocol, {
    required Map<ProtocolType, int> protocolCounts,
    required ProtocolType primaryProtocol,
  }) {
    final count = protocolCounts[protocol] ?? 0;
    final sameAsPrimaryPenalty = protocol == primaryProtocol ? 1 : 0;
    return count * 2 + sameAsPrimaryPenalty;
  }
}

final class _PoolCandidate {
  const _PoolCandidate({
    required this.profile,
    required this.countryCode,
    required this.protocol,
  });

  final ServerProfile profile;
  final String countryCode;
  final ProtocolType protocol;
}
