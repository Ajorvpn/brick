// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_profile_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(serverProfileRepository)
final serverProfileRepositoryProvider = ServerProfileRepositoryProvider._();

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

final class ServerProfileRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<ServerProfileRepository>,
          ServerProfileRepository,
          FutureOr<ServerProfileRepository>
        >
    with
        $FutureModifier<ServerProfileRepository>,
        $FutureProvider<ServerProfileRepository> {
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
  ServerProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverProfileRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverProfileRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<ServerProfileRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ServerProfileRepository> create(Ref ref) {
    return serverProfileRepository(ref);
  }
}

String _$serverProfileRepositoryHash() =>
    r'afa7cb6bf158d742c99ba2a4a587993ba5b85a51';
