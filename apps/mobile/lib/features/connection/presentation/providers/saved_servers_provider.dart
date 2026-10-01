// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/domain/usecases/build_server_profile.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

part 'saved_servers_provider.g.dart';

/// The user's saved servers, loaded from the repository on startup.
///
/// An `AsyncNotifier` so the three states a storage read can be in —
/// loading, failed, loaded — are represented rather than being faked with an
/// empty list (`CODING_STANDARDS.md` Section 4).
///
/// Depends only on the `ServerProfileRepository` **interface** from
/// `domain/`; it never imports `data/` (see `features/README.md` Section 3).
///
/// `keepAlive: true` because this is app-scoped shared state, not per-screen
/// state: both `HomeScreen` and `AddServerScreen` use it, and `AddServerScreen`
/// mutates it while `HomeScreen` observes it. A bare `@riverpod` would
/// auto-dispose the notifier the moment the last watcher navigated away,
/// disposing the `Ref` out from under an in-flight `addServer()`.
@Riverpod(keepAlive: true)
class SavedServers extends _$SavedServers {
  /// Parses pasted URIs. Domain use case, injected for testability.
  static const BuildServerProfile _buildProfile = BuildServerProfile();

  @override
  FutureOr<List<SavedServer>> build() async {
    final repository = await ref.watch(serverProfileRepositoryProvider.future);
    return await repository.loadServers();
  }

  /// Checks [sourceUri] without persisting it.
  ///
  /// Returns an [UriValidation] carrying either the parsed summary (safe to
  /// display: protocol, endpoint, and label only) or the
  /// `ConfigParseError.message` to show. Used by the Add Server screen's
  /// Parse step so the user sees what was understood *before* anything is
  /// written to disk, and so the credential-bearing remainder of the URI is
  /// never echoed back.
  ///
  /// Kept separate from [addServer] so validation and persistence are two
  /// observable steps rather than one.
  Future<UriValidation> validateUri(String sourceUri) async {
    final result = _buildProfile(
      uri: sourceUri,
      id: '',
      addedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    return switch (result) {
      Ok(:final value) => UriValidation.parsed(
        ParsedUriSummary(
          protocol: value.config.protocol.scheme,
          endpoint: '${value.config.server}:${value.config.serverPort}',
          name: value.name,
        ),
      ),
      // `error.message` never interpolates the offending input, so it is
      // safe to show while the raw URI stays hidden in the text field.
      Err(:final error) => UriValidation.failed(error.message),
    };
  }

  /// Adds [sourceUri] to the saved list.
  ///
  /// Returns `null` on success, or the parse error's message on failure, so
  /// the screen can display `ConfigParseError.message` — which never
  /// interpolates the offending input, so a pasted credential cannot be
  /// echoed back.
  ///
  /// [DateTime.now] is injected for deterministic tests.
  Future<String?> addServer(String sourceUri, {DateTime? addedAt}) async {
    final probe = _buildProfile(
      uri: sourceUri,
      id: '',
      addedAt: addedAt ?? DateTime.now(),
    );
    switch (probe) {
      case Err(:final error):
        return error.message;
      case Ok():
        break;
    }

    final repository = await ref.read(serverProfileRepositoryProvider.future);
    await repository.addServer(sourceUri);
    await _reload();
    return null;
  }

  /// Removes the entry with [id] and refreshes the list.
  Future<void> removeServer(String id) async {
    final repository = await ref.read(serverProfileRepositoryProvider.future);
    await repository.removeServer(id);
    await _reload();
  }

  /// Re-reads the saved list from storage.
  ///
  /// Guards on [Ref.mounted] after the await: a container can be disposed
  /// (or a test's provider scope torn down) while the storage read is in
  /// flight, and touching `ref` afterwards throws `UnmountedRefException`.
  Future<void> _reload() async {
    final repository = await ref.read(serverProfileRepositoryProvider.future);
    final loaded = await repository.loadServers();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData<List<SavedServer>>(loaded);
  }
}
