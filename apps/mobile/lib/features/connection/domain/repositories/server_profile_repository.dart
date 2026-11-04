// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';

/// App-wide repository contract for persistent storage of server profiles and
/// subscription sources.
///
/// Declared in `domain/` so that features depend only on this abstraction
/// rather than concrete storage mechanisms (e.g. JSON files or secure
/// keychains).
abstract interface class ServerProfileRepository {
  /// Returns all persisted [ServerProfile] instances in insertion order.
  Future<List<ServerProfile>> getAll();

  /// Returns the [ServerProfile] with [id], or null if not found.
  Future<ServerProfile?> getById(String id);

  /// Saves or updates [profile].
  Future<void> save(ServerProfile profile);

  /// Deletes the [ServerProfile] with [id]. Unknown IDs are ignored.
  Future<void> delete(String id);

  /// Returns all stored [SubscriptionMetadata] entries.
  Future<List<SubscriptionMetadata>> getAllSubscriptions();

  /// Returns the [SubscriptionMetadata] with [id], or null if not found.
  Future<SubscriptionMetadata?> getSubscriptionById(String id);

  /// Saves or updates [subscription].
  Future<void> saveSubscription(SubscriptionMetadata subscription);

  /// Atomically saves [subscription] and all associated [profiles] in a
  /// single persistence operation.
  Future<void> saveSubscriptionWithProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> profiles,
  );

  /// Atomically replaces all server profiles associated with [subscription]
  /// with [newProfiles] and updates the subscription record.
  Future<void> replaceSubscriptionProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> newProfiles,
  );

  /// Deletes the [SubscriptionMetadata] with [id]. Unknown IDs are ignored.
  Future<void> deleteSubscription(String id);

  /// Atomically deletes [subscriptionId] and all associated server profiles.
  Future<void> deleteSubscriptionCascade(String subscriptionId);

  /// Every saved entry, in insertion order.
  ///
  /// An entry whose stored configuration no longer parses is returned as a
  /// [SavedServerBroken] rather than being dropped or throwing.
  Future<List<SavedServer>> loadServers();

  /// Persists [sourceUri] as a new entry.
  ///
  /// The URI is validated before being stored; an invalid one is rejected.
  Future<void> addServer(String sourceUri);

  /// Removes the entry with [id]. Unknown IDs are ignored.
  Future<void> removeServer(String id);
}
