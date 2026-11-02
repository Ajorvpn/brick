// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';

/// Manages and persists the user-selected active server ID.
///
/// Holds `null` if no server has been explicitly selected by the user.
/// Persists the selected ID via [AppPreferencesRepository].
class ActiveServerIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return repo.getActiveServerId();
  }

  /// Selects [serverId] as the active server and persists it to preferences.
  ///
  /// Passing `null` clears the explicit selection.
  Future<void> selectServer(String? serverId) async {
    state = serverId;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setActiveServerId(serverId);
  }
}

/// Provides the user-selected active server ID.
final activeServerIdProvider =
    NotifierProvider<ActiveServerIdNotifier, String?>(
      ActiveServerIdNotifier.new,
    );

/// Resolves the currently active [SavedServerProfile], applying the
/// auto-fallback policy:
/// 1. If an active server ID is persisted and matches a valid
///    [SavedServerProfile] in [savedServersProvider], that server is returned.
/// 2. If the persisted active server ID is `null` or no longer exists in the
///    valid server list (e.g. server was deleted), falls back to the FIRST
///    valid [SavedServerProfile] in [savedServersProvider].
/// 3. If there are no valid [SavedServerProfile]s, returns `null`.
final activeServerProvider = Provider<SavedServerProfile?>((ref) {
  final serversAsync = ref.watch(savedServersProvider);
  final validProfiles =
      serversAsync.value?.whereType<SavedServerProfile>().toList(
        growable: false,
      ) ??
      const <SavedServerProfile>[];

  if (validProfiles.isEmpty) {
    return null;
  }

  final selectedId = ref.watch(activeServerIdProvider);
  if (selectedId != null) {
    for (final profile in validProfiles) {
      if (profile.id == selectedId) {
        return profile;
      }
    }
  }

  // Auto-fallback: return first valid profile when no valid selection exists.
  return validProfiles.first;
});
