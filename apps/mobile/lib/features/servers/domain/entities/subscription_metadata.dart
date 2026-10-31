// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';

/// Metadata for a subscription source.
///
/// Security note: there is intentionally no `toString()` override —
/// [url] carries sensitive parameters/tokens (see SECURITY.md).
final class SubscriptionMetadata {
  /// Creates a subscription metadata instance.
  const SubscriptionMetadata({
    required this.id,
    required this.url,
    required this.name,
    this.lastRefreshedAt,
    this.associatedServerIds = const <String>[],
    this.userInfo,
    this.schemaVersion = 1,
  });

  /// Stable unique identifier for this subscription.
  final String id;

  /// Subscription URL (HTTP/HTTPS). Sensitive.
  final String url;

  /// User-facing display name.
  final String name;

  /// When this subscription was last successfully refreshed.
  final DateTime? lastRefreshedAt;

  /// IDs of [ServerProfile] instances generated from this subscription.
  final List<String> associatedServerIds;

  /// Usage/quota statistics, if returned by the provider.
  final SubscriptionUserInfo? userInfo;

  /// Storage schema version.
  final int schemaVersion;

  /// Returns a copy with the given fields replaced.
  SubscriptionMetadata copyWith({
    String? id,
    String? url,
    String? name,
    DateTime? lastRefreshedAt,
    List<String>? associatedServerIds,
    SubscriptionUserInfo? userInfo,
    int? schemaVersion,
  }) {
    return SubscriptionMetadata(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
      associatedServerIds: associatedServerIds ?? this.associatedServerIds,
      userInfo: userInfo ?? this.userInfo,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  /// Serializes to the storage shape.
  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'name': name,
    if (lastRefreshedAt != null)
      'last_refreshed_at': lastRefreshedAt!.toIso8601String(),
    'associated_server_ids': associatedServerIds,
    if (userInfo != null)
      'user_info': {
        if (userInfo!.uploadBytes != null)
          'upload_bytes': userInfo!.uploadBytes,
        if (userInfo!.downloadBytes != null)
          'download_bytes': userInfo!.downloadBytes,
        if (userInfo!.totalBytes != null) 'total_bytes': userInfo!.totalBytes,
        if (userInfo!.expiresAt != null)
          'expires_at': userInfo!.expiresAt!.toIso8601String(),
      },
    'schema_version': schemaVersion,
  };

  /// Rebuilds metadata from stored JSON, or returns `null` if invalid.
  static SubscriptionMetadata? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final url = raw['url'];
    final name = raw['name'];
    if (id is! String || id.isEmpty) return null;
    if (url is! String || url.isEmpty) return null;
    if (name is! String) return null;

    final lastRefreshedAtRaw = raw['last_refreshed_at'];
    final lastRefreshedAt = (lastRefreshedAtRaw is String)
        ? DateTime.tryParse(lastRefreshedAtRaw)
        : null;

    final serverIdsRaw = raw['associated_server_ids'];
    final associatedServerIds = (serverIdsRaw is List)
        ? serverIdsRaw.whereType<String>().toList(growable: false)
        : const <String>[];

    final userInfoRaw = raw['user_info'];
    SubscriptionUserInfo? userInfo;
    if (userInfoRaw is Map) {
      final uploadBytes = userInfoRaw['upload_bytes'] as int?;
      final downloadBytes = userInfoRaw['download_bytes'] as int?;
      final totalBytes = userInfoRaw['total_bytes'] as int?;
      final expiresAtRaw = userInfoRaw['expires_at'];
      final expiresAt = (expiresAtRaw is String)
          ? DateTime.tryParse(expiresAtRaw)
          : null;
      userInfo = SubscriptionUserInfo(
        uploadBytes: uploadBytes,
        downloadBytes: downloadBytes,
        totalBytes: totalBytes,
        expiresAt: expiresAt,
      );
    }

    final schemaVersion = (raw['schema_version'] is int)
        ? raw['schema_version'] as int
        : 1;

    return SubscriptionMetadata(
      id: id,
      url: url,
      name: name,
      lastRefreshedAt: lastRefreshedAt,
      associatedServerIds: associatedServerIds,
      userInfo: userInfo,
      schemaVersion: schemaVersion,
    );
  }

  @override
  // Value equality on immutable model without dragging
  // meta package into domain.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SubscriptionMetadata) return false;
    if (other.id != id ||
        other.url != url ||
        other.name != name ||
        other.lastRefreshedAt != lastRefreshedAt ||
        other.userInfo != userInfo ||
        other.schemaVersion != schemaVersion ||
        other.associatedServerIds.length != associatedServerIds.length) {
      return false;
    }
    for (var i = 0; i < associatedServerIds.length; i++) {
      if (associatedServerIds[i] != other.associatedServerIds[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  // Hash code implementation matching value equality.
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(
    id,
    url,
    name,
    lastRefreshedAt,
    Object.hashAll(associatedServerIds),
    userInfo,
    schemaVersion,
  );
}
