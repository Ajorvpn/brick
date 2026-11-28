// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart' show AmneziaWgOutbound;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/connection/domain/entities/connection_location_target.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';

/// Manages and persists the user-selected location target
/// (`SmartAutoTarget` `'auto'` or `CountryTarget` `'country:<ISO2>'`).
class SelectedLocationNotifier extends Notifier<ConnectionLocationTarget> {
  @override
  ConnectionLocationTarget build() {
    final repo = ref.watch(appPreferencesRepositoryProvider);
    return ConnectionLocationTarget.fromStorageKey(repo.getSelectedLocation());
  }

  /// Selects and persists [target] cleanly via [AppPreferencesRepository].
  Future<void> selectLocation(ConnectionLocationTarget target) async {
    state = target;
    final repo = ref.read(appPreferencesRepositoryProvider);
    await repo.setSelectedLocation(target.storageKey);
  }

  /// Selects the default Smart Auto global target.
  Future<void> selectAuto() => selectLocation(const SmartAutoTarget());

  /// Selects a country-scoped target for [countryCode].
  Future<void> selectCountry(String countryCode) =>
      selectLocation(CountryTarget(countryCode));
}

/// Provides the user-selected location target (`auto` or `country:<ISO2>`).
final selectedLocationProvider =
    NotifierProvider<SelectedLocationNotifier, ConnectionLocationTarget>(
      SelectedLocationNotifier.new,
    );

/// Resolves [selectedLocationProvider] against currently saved valid profiles,
/// falling back to [SmartAutoTarget] if a persisted country no longer has
/// any saved servers.
final resolvedLocationTargetProvider = Provider<ConnectionLocationTarget>((
  ref,
) {
  final selected = ref.watch(selectedLocationProvider);
  if (selected is SmartAutoTarget) {
    return selected;
  }
  final target = selected as CountryTarget;
  final serversAsync = ref.watch(savedServersProvider);
  final validProfiles =
      serversAsync.value?.whereType<SavedServerProfile>().toList(
        growable: false,
      ) ??
      const <SavedServerProfile>[];

  for (final server in validProfiles) {
    if (ServerLocationParser.parse(server.name).countryCode ==
        target.countryCode) {
      return target;
    }
  }
  return const SmartAutoTarget();
});

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

/// Resolves the representative [SavedServerProfile] for the current
/// [resolvedLocationTargetProvider] (preserving legacy `activeServerIdProvider`
/// selection when in Smart Auto for unit-test compatibility).
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

  final locationTarget = ref.watch(resolvedLocationTargetProvider);
  if (locationTarget is CountryTarget) {
    SavedServerProfile? firstFallback;
    for (final profile in validProfiles) {
      if (ServerLocationParser.parse(profile.name).countryCode ==
          locationTarget.countryCode) {
        firstFallback ??= profile;
        if (profile.profile.config is! AmneziaWgOutbound) {
          return profile;
        }
      }
    }
    if (firstFallback != null) {
      return firstFallback;
    }
  }

  final selectedId = ref.watch(activeServerIdProvider);
  if (selectedId != null) {
    for (final profile in validProfiles) {
      if (profile.id == selectedId) {
        return profile;
      }
    }
  }

  // Prefer a runtime-supported outbound as the Smart Auto representative.
  for (final profile in validProfiles) {
    if (profile.profile.config is! AmneziaWgOutbound) {
      return profile;
    }
  }
  return validProfiles.first;
});
