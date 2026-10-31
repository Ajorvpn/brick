// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_profile_repository_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Binds the application's [ServerProfileRepository] contract to its
/// concrete persistent [FileServerProfileRepository] implementation.
///
/// In Phase 5 (P5-T1), this replaces the Phase 4 in-memory/SharedPreferences
/// scaffold with a versioned, atomic JSON-file persistent store.
///
/// In case of storage initialization failure (e.g., missing directory or
/// permission issue), it logs the error and gracefully degrades to an
/// in-memory fallback store in the system temp directory rather than
/// crashing the application.

@ProviderFor(serverProfileRepository)
final serverProfileRepositoryProvider = ServerProfileRepositoryProvider._();

/// Binds the application's [ServerProfileRepository] contract to its
/// concrete persistent [FileServerProfileRepository] implementation.
///
/// In Phase 5 (P5-T1), this replaces the Phase 4 in-memory/SharedPreferences
/// scaffold with a versioned, atomic JSON-file persistent store.
///
/// In case of storage initialization failure (e.g., missing directory or
/// permission issue), it logs the error and gracefully degrades to an
/// in-memory fallback store in the system temp directory rather than
/// crashing the application.

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
  /// Binds the application's [ServerProfileRepository] contract to its
  /// concrete persistent [FileServerProfileRepository] implementation.
  ///
  /// In Phase 5 (P5-T1), this replaces the Phase 4 in-memory/SharedPreferences
  /// scaffold with a versioned, atomic JSON-file persistent store.
  ///
  /// In case of storage initialization failure (e.g., missing directory or
  /// permission issue), it logs the error and gracefully degrades to an
  /// in-memory fallback store in the system temp directory rather than
  /// crashing the application.
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
    r'713b1771b246f05ad7fd49bb4ab8c190f398f7be';
