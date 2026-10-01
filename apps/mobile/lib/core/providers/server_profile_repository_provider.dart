// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:mobile/features/connection/data/datasources/server_profile_local_data_source.dart';
import 'package:mobile/features/connection/data/repositories/local_server_profile_repository.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'server_profile_repository_provider.g.dart';

/// Binds the connection feature's [ServerProfileRepository] contract to its
/// concrete implementation.
///
/// This binding lives in `core/`, not in `features/connection/`, on purpose.
/// `features/README.md` Section 3 forbids `presentation/` from importing
/// `data/`, and putting this provider inside the feature would force exactly
/// that. `core/` is the app-wide composition root — the same role
/// `vpnEngineProvider` already plays by binding `MockVpnEngine` — so it may
/// name a concrete data class on the feature's behalf. The feature itself
/// only ever sees the [ServerProfileRepository] interface.
///
/// `Async` because `SharedPreferences.getInstance()` is asynchronous, and
/// returning a `Future` here lets `AsyncNotifier.build()` await the value and
/// inherit proper loading/error handling for free
/// (`CODING_STANDARDS.md` Section 4).
//
// TODO(Ajorvpn): swap the `SharedPreferences` data source for a
// `flutter_secure_storage`-backed one before Phase 11. Server config is
// High-sensitivity data (SECURITY.md Section 3) and plain
// `SharedPreferences` is not acceptable at release.
@Riverpod(keepAlive: true)
Future<ServerProfileRepository> serverProfileRepository(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  return LocalServerProfileRepository(
    SharedPreferencesServerProfileDataSource(prefs),
  );
}
