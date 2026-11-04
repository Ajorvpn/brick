// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/connection/domain/usecases/build_server_profile.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

/// A persistent, atomic JSON-file-backed implementation of
/// [ServerProfileRepository].
///
/// Features:
/// - In-memory cache for sub-millisecond reads without hitting disk.
/// - Atomic write strategy: serializes payload to a `.tmp` file with `flush`,
///   then atomically renames over the target file to prevent corrupt state on
///   abrupt process termination or power loss.
/// - Canonical JSON envelope stamped with `"schema_version": 1`.
/// - Concurrency safety: re-entrant `_loadFuture` prevents multiple concurrent
///   initial reads, and `_writeLock` serializes concurrent disk writes.
/// - Graceful recovery: corrupt files or unsupported schema versions are logged
///   via [AppLogger] and cleanly recovered as empty stores rather than crashing
///   the app.
/// - Broken servers persistence: unparseable server profiles are remembered
///   and persisted across app restarts without being wiped on mutation.
final class FileServerProfileRepository implements ServerProfileRepository {
  /// Creates the repository targeting [storageFile].
  FileServerProfileRepository({required File storageFile, AppLogger? logger})
    : _file = storageFile,
      _logger = logger ?? AppLogger();

  final File _file;
  final AppLogger _logger;

  final Map<String, ServerProfile> _profiles = <String, ServerProfile>{};
  final Map<String, SubscriptionMetadata> _subscriptions =
      <String, SubscriptionMetadata>{};
  final Map<String, String> _brokenServers = <String, String>{};

  Future<void>? _loadFuture;
  Future<void> _writeLock = Future<void>.value();
  static const BuildServerProfile _buildProfile = BuildServerProfile();

  /// Eagerly initializes the repository and warms the in-memory cache.
  Future<void> init() => _ensureLoaded();

  Future<void> _ensureLoaded() => _loadFuture ??= _loadFromFile();

  Future<void> _loadFromFile() async {
    if (!_file.existsSync()) {
      return;
    }

    try {
      final content = await _file.readAsString();
      if (content.trim().isEmpty) {
        return;
      }

      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map) {
        _logger.w('Corrupt storage payload (not a Map); resetting to empty');
        return;
      }

      final schemaVersion = decoded['schema_version'];
      if (schemaVersion is! int || schemaVersion != 1) {
        _logger.w(
          'Unsupported storage schema: $schemaVersion; resetting to empty',
        );
        return;
      }

      _profiles.clear();
      _subscriptions.clear();
      _brokenServers.clear();

      final profilesRaw = decoded['server_profiles'];
      if (profilesRaw is List) {
        profilesRaw.forEach(_loadProfileEntry);
      }

      final brokenRaw = decoded['broken_servers'];
      if (brokenRaw is Map) {
        for (final entry in brokenRaw.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is String && value is String) {
            _brokenServers[key] = value;
          }
        }
      }

      final subscriptionsRaw = decoded['subscriptions'];
      if (subscriptionsRaw is List) {
        for (final raw in subscriptionsRaw) {
          final sub = SubscriptionMetadata.tryParse(raw);
          if (sub != null) {
            _subscriptions[sub.id] = sub;
          }
        }
      }
    } on Object catch (error, stackTrace) {
      _logger.e(
        'Failed to read storage file ${_file.path}; recovering cleanly',
        error,
        stackTrace,
      );
    }
  }

  void _loadProfileEntry(Object? raw) {
    if (raw is! Map) return;
    final id = raw['id'];
    final name = raw['name'];
    final configRaw = raw['config'];
    final addedAtRaw = raw['added_at'];

    if (id is! String || id.isEmpty) return;
    if (name is! String) return;
    if (addedAtRaw is! String) return;

    final addedAt = DateTime.tryParse(addedAtRaw);
    if (addedAt == null) return;

    if (configRaw is! Map<String, dynamic>) {
      _brokenServers[id] = 'Invalid outbound configuration format';
      return;
    }

    // Normalize protocol types for reader compatibility where needed
    final configMap = Map<String, dynamic>.from(configRaw);
    final rawType = configMap['type'];
    if (rawType == 'ss') {
      configMap['type'] = 'shadowsocks';
    } else if (rawType == 'amneziawg') {
      configMap['type'] = 'wireguard';
    }

    final parsedConfig = readSingBoxOutboundJson(configMap);
    switch (parsedConfig) {
      case Ok(:final value):
        final lastUsedAtRaw = raw['last_used_at'];
        final lastUsedAt = (lastUsedAtRaw is String)
            ? DateTime.tryParse(lastUsedAtRaw)
            : null;
        final subId = raw['subscription_id'] as String?;

        _profiles[id] = ServerProfile(
          id: id,
          name: name,
          config: value,
          addedAt: addedAt,
          lastUsedAt: lastUsedAt,
          subscriptionId: subId,
        );
      case Err(:final error):
        _brokenServers[id] = error.message;
    }
  }

  Future<void> _persist() {
    final next = _writeLock.then((_) => _performPersist());
    _writeLock = next.catchError((Object _) {});
    return next;
  }

  Future<void> _performPersist() async {
    final payload = <String, dynamic>{
      'schema_version': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'server_profiles': _profiles.values
          .map((profile) => profile.toJson())
          .toList(growable: false),
      'subscriptions': _subscriptions.values
          .map((sub) => sub.toJson())
          .toList(growable: false),
      'broken_servers': _brokenServers,
    };

    final parent = _file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }

    final tmpFile = File('${_file.path}.tmp');
    final encoded = const JsonEncoder.withIndent('  ').convert(payload);
    await tmpFile.writeAsString(encoded, flush: true);
    await tmpFile.rename(_file.path);
  }

  @override
  Future<List<ServerProfile>> getAll() async {
    await _ensureLoaded();
    return _profiles.values.toList(growable: false);
  }

  @override
  Future<ServerProfile?> getById(String id) async {
    await _ensureLoaded();
    return _profiles[id];
  }

  @override
  Future<void> save(ServerProfile profile) async {
    await _ensureLoaded();
    _profiles[profile.id] = profile;
    _brokenServers.remove(profile.id);
    await _persist();
  }

  @override
  Future<void> delete(String id) async {
    await _ensureLoaded();
    final removed = _profiles.remove(id) != null;
    final removedBroken = _brokenServers.remove(id) != null;
    if (removed || removedBroken) {
      await _persist();
    }
  }

  @override
  Future<List<SubscriptionMetadata>> getAllSubscriptions() async {
    await _ensureLoaded();
    return _subscriptions.values.toList(growable: false);
  }

  @override
  Future<SubscriptionMetadata?> getSubscriptionById(String id) async {
    await _ensureLoaded();
    return _subscriptions[id];
  }

  @override
  Future<void> saveSubscription(SubscriptionMetadata subscription) async {
    await _ensureLoaded();
    _subscriptions[subscription.id] = subscription;
    await _persist();
  }

  @override
  Future<void> saveSubscriptionWithProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> profiles,
  ) async {
    await _ensureLoaded();
    _subscriptions[subscription.id] = subscription;
    for (final profile in profiles) {
      _profiles[profile.id] = profile;
      _brokenServers.remove(profile.id);
    }
    await _persist();
  }

  @override
  Future<void> replaceSubscriptionProfiles(
    SubscriptionMetadata subscription,
    List<ServerProfile> newProfiles,
  ) async {
    await _ensureLoaded();
    final oldSub = _subscriptions[subscription.id];
    final oldAssociated = oldSub?.associatedServerIds ?? const <String>[];

    _profiles.removeWhere(
      (id, p) =>
          p.subscriptionId == subscription.id ||
          oldAssociated.contains(id) ||
          oldAssociated.contains(p.id),
    );
    _brokenServers.removeWhere((id, _) => oldAssociated.contains(id));

    _subscriptions[subscription.id] = subscription;
    for (final profile in newProfiles) {
      _profiles[profile.id] = profile;
      _brokenServers.remove(profile.id);
    }
    await _persist();
  }

  @override
  Future<void> deleteSubscription(String id) async {
    await _ensureLoaded();
    if (_subscriptions.remove(id) != null) {
      await _persist();
    }
  }

  @override
  Future<void> deleteSubscriptionCascade(String subscriptionId) async {
    await _ensureLoaded();
    final oldSub = _subscriptions.remove(subscriptionId);
    final oldAssociated = oldSub?.associatedServerIds ?? const <String>[];

    _profiles.removeWhere(
      (id, p) =>
          p.subscriptionId == subscriptionId ||
          oldAssociated.contains(id) ||
          oldAssociated.contains(p.id),
    );
    _brokenServers.removeWhere((id, _) => oldAssociated.contains(id));

    await _persist();
  }

  @override
  Future<List<SavedServer>> loadServers() async {
    await _ensureLoaded();
    final result = <SavedServer>[
      ..._profiles.values.map(SavedServerProfile.new),
      ..._brokenServers.entries.map(
        (entry) => SavedServerBroken(id: entry.key, reason: entry.value),
      ),
    ];
    return result;
  }

  @override
  Future<void> addServer(String sourceUri) async {
    await _ensureLoaded();
    final parsed = _buildProfile(
      uri: sourceUri,
      id: '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );

    if (parsed case Err(:final error)) {
      throw ArgumentError(
        'Refusing to persist an unparseable server URI: ${error.message}',
      );
    }

    final id = _generateId();
    final profile = (parsed as Ok<ServerProfile, ConfigParseError>).value
        .copyWith(id: id, addedAt: DateTime.now());

    await save(profile);
  }

  @override
  Future<void> removeServer(String id) => delete(id);

  String _generateId() {
    final taken = {..._profiles.keys, ..._brokenServers.keys};
    final base = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    var candidate = base;
    var suffix = 0;
    while (taken.contains(candidate)) {
      suffix++;
      candidate = '$base-${suffix.toRadixString(36)}';
    }
    return candidate;
  }
}
