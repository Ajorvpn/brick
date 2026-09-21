// SPDX-License-Identifier: GPL-3.0-or-later

import 'outbound_config.dart';

/// One user-configured VPN server: identity metadata plus the polymorphic
/// [OutboundConfig] that dials it.
///
/// Why a container class: the UI, the storage layer (Phase 8), and the
/// engine (P1-T4 onward) all need a single stable handle for "a server"
/// that is independent of which protocol it speaks, of how it was parsed
/// (Phase 2's job), and of how it is stored (Phase 8's job).
///
/// Security note: there is intentionally no `toString` override —
/// [config] carries credentials (see SECURITY.md). `lastUsedAt` and
/// `subscriptionId` are nullable, and `copyWith` cannot clear them back to
/// null (a Dart limitation of optional named parameters); reconstruct the
/// instance instead when a clear-to-null is required.
final class ServerProfile {
  /// Creates an immutable server profile.
  const ServerProfile({
    required this.id,
    required this.name,
    required this.config,
    required this.addedAt,
    this.lastUsedAt,
    this.subscriptionId,
  });

  /// Unique identifier (UUID) of this profile.
  final String id;

  /// User-facing label, shown as-is in the UI.
  final String name;

  /// Polymorphic protocol configuration this profile dials.
  final OutboundConfig config;

  /// When the profile was created.
  final DateTime addedAt;

  /// When the profile was last connected; null means never used.
  final DateTime? lastUsedAt;

  /// Identifier of the subscription that produced this profile, if any.
  final String? subscriptionId;

  /// Storage schema version, consumed by Phase 8 secure storage.
  int get schemaVersion => 1;

  /// Returns a copy with the given fields replaced. Nullable fields cannot
  /// be cleared back to null through [copyWith]; see the class doc.
  ServerProfile copyWith({
    String? id,
    String? name,
    OutboundConfig? config,
    DateTime? addedAt,
    DateTime? lastUsedAt,
    String? subscriptionId,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      addedAt: addedAt ?? this.addedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      subscriptionId: subscriptionId ?? this.subscriptionId,
    );
  }

  /// Deterministic JSON mapping. The nested [config] serializes through
  /// its own polymorphic `toJson()` (including its `'type'` discriminator).
  /// Null optional fields are omitted.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'config': config.toJson(),
    'added_at': addedAt.toIso8601String(),
    if (lastUsedAt != null) 'last_used_at': lastUsedAt!.toIso8601String(),
    if (subscriptionId != null) 'subscription_id': subscriptionId,
    'schema_version': schemaVersion,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerProfile &&
          other.id == id &&
          other.name == name &&
          other.config == config &&
          other.addedAt == addedAt &&
          other.lastUsedAt == lastUsedAt &&
          other.subscriptionId == subscriptionId;

  @override
  int get hashCode =>
      Object.hash(id, name, config, addedAt, lastUsedAt, subscriptionId);
}
