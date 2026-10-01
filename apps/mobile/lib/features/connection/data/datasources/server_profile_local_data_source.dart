// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The persisted form of one saved server.
///
/// **What is stored is the source URI plus a locally-generated `id` and
/// `addedAt` — nothing else.** There is no `ServerProfile.fromJson()` in
/// `core_domain` (and it is frozen), so persisting the profile's own JSON
/// would have required either editing the frozen package or inventing a
/// second, competing serialization format for a type that package owns.
/// Storing the URI instead means `parseUri()` is the single source of truth
/// for turning text into a config, on both the save and the load path.
///
/// Security note: `sourceUri` carries credentials (a UUID, a password) and
/// [SavedServerRecord] is written to **plain** `SharedPreferences`. This
/// violates SECURITY.md Section 3 and is accepted ONLY as a temporary
/// scaffold to prove the Riverpod/state-stream wiring before any native
/// engine exists. See the TODO on the datasource and the note in
/// `PROJECT_STATE.md`; it must move to `flutter_secure_storage` before
/// Phase 11.
final class SavedServerRecord {
  const SavedServerRecord({
    required this.id,
    required this.sourceUri,
    required this.addedAt,
  });

  /// Locally-generated identifier. Not secret, and never leaves the device.
  final String id;

  /// The original pasted URI. **Sensitive** — see the security note above.
  final String sourceUri;

  /// When the user added this entry.
  final DateTime addedAt;

  /// Serializes to the storage shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'uri': sourceUri,
    'added_at': addedAt.toIso8601String(),
  };

  /// Rebuilds a record from stored JSON, or returns `null` if the shape is
  /// not usable.
  ///
  /// Returns `null` rather than throwing so that one corrupt entry cannot
  /// take down the whole list on load.
  static SavedServerRecord? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final id = raw['id'];
    final uri = raw['uri'];
    final addedAt = raw['added_at'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    if (uri is! String || uri.isEmpty) {
      return null;
    }
    if (addedAt is! String) {
      return null;
    }
    final parsed = DateTime.tryParse(addedAt);
    if (parsed == null) {
      return null;
    }
    return SavedServerRecord(id: id, sourceUri: uri, addedAt: parsed);
  }
}

/// Local persistence for [SavedServerRecord]s.
///
/// Abstract so `data/repositories/` depends on this contract and the
/// `SharedPreferences` technology stays swappable (see `data/README.md`).
abstract interface class ServerProfileLocalDataSource {
  /// Every stored record, in insertion order. Never throws.
  List<SavedServerRecord> readAll();

  /// Replaces the stored set with [records].
  Future<void> writeAll(List<SavedServerRecord> records);
}

/// `SharedPreferences`-backed [ServerProfileLocalDataSource].
//
// TODO(Ajorvpn): replace with `flutter_secure_storage` before Phase 11 /
// any release build. `data/README.md` states server configuration "must be
// persisted only through the platform-native secure storage, never in plain
// `SharedPreferences`", and SECURITY.md Section 3 repeats it. This is a
// deliberate, flagged, temporary deviation.
final class SharedPreferencesServerProfileDataSource
    implements ServerProfileLocalDataSource {
  /// Creates the data source over the given [SharedPreferences] instance.
  const SharedPreferencesServerProfileDataSource(this._prefs);

  final SharedPreferences _prefs;

  /// Storage key. Versioned so a future schema change can migrate rather
  /// than misread an older blob.
  static const String storageKey = 'brick.connection.saved_servers.v1';

  @override
  List<SavedServerRecord> readAll() {
    final raw = _prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      return const <SavedServerRecord>[];
    }
    return _decode(raw);
  }

  /// Decodes a stored blob, degrading to an empty list rather than throwing.
  ///
  /// A decode failure means the blob is unusable as a whole. An empty list is
  /// the safe outcome: the user sees "no servers" and can re-add, rather
  /// than the app failing to start on a corrupt preference.
  List<SavedServerRecord> _decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <SavedServerRecord>[];
    }
    if (decoded is! List) {
      return const <SavedServerRecord>[];
    }
    return decoded
        .map(SavedServerRecord.tryParse)
        .whereType<SavedServerRecord>()
        .toList(growable: false);
  }

  @override
  Future<void> writeAll(List<SavedServerRecord> records) async {
    final encoded = jsonEncode(
      records.map((record) => record.toJson()).toList(growable: false),
    );
    await _prefs.setString(storageKey, encoded);
  }
}
