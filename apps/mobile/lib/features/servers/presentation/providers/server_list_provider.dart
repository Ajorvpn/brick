// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';

/// Grouped representation of saved servers for presentation on the server list.
class GroupedServerList {
  /// Creates a grouped server list snapshot.
  const GroupedServerList({
    required this.standalone,
    required this.subscriptionGroups,
    required this.broken,
  });

  /// Standalone servers (not tied to any subscription).
  final List<SavedServerProfile> standalone;

  /// Subscription servers grouped by their [SubscriptionMetadata].
  final Map<SubscriptionMetadata, List<SavedServerProfile>> subscriptionGroups;

  /// Broken or unparseable server entries.
  final List<SavedServerBroken> broken;

  /// Whether no servers of any type exist.
  bool get isEmpty =>
      standalone.isEmpty && subscriptionGroups.isEmpty && broken.isEmpty;

  /// Total count of all servers across all groups.
  int get totalCount =>
      standalone.length +
      subscriptionGroups.values.fold<int>(0, (sum, l) => sum + l.length) +
      broken.length;
}

/// Provides the grouped server list computed from [savedServersProvider] and
/// the repository's subscriptions.
final groupedServerListProvider = FutureProvider<GroupedServerList>((
  ref,
) async {
  final servers = await ref.watch(savedServersProvider.future);
  final repo = await ref.watch(serverProfileRepositoryProvider.future);
  final subscriptions = await repo.getAllSubscriptions();
  final subsMap = {for (final s in subscriptions) s.id: s};

  final standalone = <SavedServerProfile>[];
  final subscriptionMap = <String, List<SavedServerProfile>>{};
  final broken = <SavedServerBroken>[];

  for (final server in servers) {
    switch (server) {
      case SavedServerProfile(:final profile):
        final subId = profile.subscriptionId;
        if (subId == null || subId.isEmpty) {
          standalone.add(server);
        } else {
          subscriptionMap.putIfAbsent(subId, () => []).add(server);
        }
      case SavedServerBroken():
        broken.add(server);
    }
  }

  final subscriptionGroups = <SubscriptionMetadata, List<SavedServerProfile>>{};
  subscriptionMap.forEach((subId, profiles) {
    final meta =
        subsMap[subId] ??
        SubscriptionMetadata(
          id: subId,
          url: '',
          name: 'servers.subscription_badge'.tr(),
          lastRefreshedAt: DateTime.fromMillisecondsSinceEpoch(0),
          associatedServerIds: profiles.map((p) => p.id).toList(),
        );
    subscriptionGroups[meta] = profiles;
  });

  return GroupedServerList(
    standalone: List.unmodifiable(standalone),
    subscriptionGroups: Map.unmodifiable(subscriptionGroups),
    broken: List.unmodifiable(broken),
  );
});
