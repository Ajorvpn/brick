// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:mobile/features/connection/domain/entities/saved_server.dart';

/// The connection feature's contract for reading and writing saved servers.
///
/// Declared in `domain/` (not `data/`) so that `presentation/` depends only
/// on this interface and never names a concrete repository or a storage
/// technology — the rule in `features/README.md` Section 3. The
/// implementation lives in `data/repositories/` and is handed to the widget
/// tree through a Riverpod provider.
///
/// Deliberately URI-shaped rather than profile-shaped. `ServerProfile` has a
/// `toJson()` but **no `fromJson()`** anywhere in the codebase, and
/// `core_domain` is frozen, so this repository persists the source URI plus a
/// locally-generated `id` and `addedAt`, then rebuilds the profile by
/// re-running `parseUri()` on load. That keeps every `core_domain`
/// constructor read-only from this feature's point of view and avoids
/// inventing a second, competing serialization format for a type the frozen
/// package already owns.
abstract interface class ServerProfileRepository {
  /// Every saved entry, in insertion order.
  ///
  /// An entry whose stored URI no longer parses is returned as a
  /// [SavedServerBroken] rather than being dropped or throwing.
  Future<List<SavedServer>> loadServers();

  /// Persists [sourceUri] as a new entry.
  ///
  /// The URI is validated before being stored; an invalid one is rejected.
  Future<void> addServer(String sourceUri);

  /// Removes the entry with [id]. Unknown ids are ignored.
  Future<void> removeServer(String id);
}
