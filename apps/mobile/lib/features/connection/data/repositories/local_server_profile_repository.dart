// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:mobile/features/connection/data/datasources/server_profile_local_data_source.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/connection/domain/usecases/build_server_profile.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

/// Implements [ServerProfileRepository] over a
/// [ServerProfileLocalDataSource].
///
/// The load path is where this class earns its keep: every stored URI is
/// re-parsed through [BuildServerProfile], so a saved entry always yields a
/// freshly-built, fully-typed [SavedServerProfile] rather than a partially
/// reconstructed one.
///
/// A record whose URI no longer parses becomes a [SavedServerBroken]. It is
/// deliberately **kept**, not dropped: silently deleting a user's saved
/// server because an app update tightened a parser would be a data-loss bug.
/// The entry stays visible, shows only a safe error message, and can be
/// removed explicitly. It is also never rendered as a connectable profile,
/// so a broken entry can never reach the engine.
///
/// This class holds no business rules beyond I/O and mapping; the parse
/// decision itself belongs to the [BuildServerProfile] use case in `domain/`.
final class LocalServerProfileRepository implements ServerProfileRepository {
  /// Creates the repository over the given [ServerProfileLocalDataSource].
  LocalServerProfileRepository(this._dataSource);

  final ServerProfileLocalDataSource _dataSource;

  /// Injected so the use case stays a single decision point; also lets a
  /// test substitute a different implementation.
  static const BuildServerProfile _buildProfile = BuildServerProfile();

  @override
  Future<List<SavedServer>> loadServers() async {
    return _dataSource.readAll().map(_toSavedServer).toList(growable: false);
  }

  /// Rebuilds one record, degrading to [SavedServerBroken] on a parse error.
  SavedServer _toSavedServer(SavedServerRecord record) {
    final result = _buildProfile(
      uri: record.sourceUri,
      id: record.id,
      addedAt: record.addedAt,
    );
    return switch (result) {
      Ok(:final value) => SavedServerProfile(value),
      // `error.message` is documented by `config_parser` as safe to display:
      // no variant interpolates the offending input, so a credential inside
      // a URI can never reach the screen through this path.
      Err(:final error) => SavedServerBroken(
        id: record.id,
        reason: error.message,
      ),
    };
  }

  @override
  Future<void> addServer(String sourceUri) async {
    // Validate before persisting, so a bad entry can never reach disk and
    // then come back as a `SavedServerBroken` on the next load. Parsing is
    // pure, so validating and discarding the built profile costs nothing —
    // the entry is rebuilt from the stored URI on load regardless.
    //
    // The screen parses before it ever offers Save, so reaching this throw
    // means a caller bypassed its own validation; failing loudly is better
    // than writing an unusable entry to disk.
    final validated = _buildProfile(
      uri: sourceUri,
      id: '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    if (validated case Err(:final error)) {
      throw ArgumentError.value(
        sourceUri,
        'sourceUri',
        'Refusing to persist an unparseable server URI: ${error.message}',
      );
    }

    final existing = _dataSource.readAll();
    final records = <SavedServerRecord>[
      ...existing,
      SavedServerRecord(
        id: _generateId(existing),
        sourceUri: sourceUri,
        addedAt: DateTime.now(),
      ),
    ];
    await _dataSource.writeAll(records);
  }

  @override
  Future<void> removeServer(String id) async {
    final remaining = _dataSource
        .readAll()
        .where((record) => record.id != id)
        .toList(growable: false);
    await _dataSource.writeAll(remaining);
  }

  /// A locally-generated id, unique among [existing].
  ///
  /// Deliberately not a UUID: there is no `uuid` dependency, and this id is
  /// never transmitted, so a timestamp plus a collision-avoiding suffix is
  /// sufficient and keeps the id out of the credential-bearing surface.
  String _generateId(List<SavedServerRecord> existing) {
    final taken = existing.map((record) => record.id).toSet();
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
