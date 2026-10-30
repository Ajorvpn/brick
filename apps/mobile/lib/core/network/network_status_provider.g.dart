// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider exposing the [ConnectivitySource] abstraction.
///
/// Can be overridden in tests with a fake implementation to avoid invoking
/// native platform channels.

@ProviderFor(connectivitySource)
final connectivitySourceProvider = ConnectivitySourceProvider._();

/// Provider exposing the [ConnectivitySource] abstraction.
///
/// Can be overridden in tests with a fake implementation to avoid invoking
/// native platform channels.

final class ConnectivitySourceProvider
    extends
        $FunctionalProvider<
          ConnectivitySource,
          ConnectivitySource,
          ConnectivitySource
        >
    with $Provider<ConnectivitySource> {
  /// Provider exposing the [ConnectivitySource] abstraction.
  ///
  /// Can be overridden in tests with a fake implementation to avoid invoking
  /// native platform channels.
  ConnectivitySourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivitySourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivitySourceHash();

  @$internal
  @override
  $ProviderElement<ConnectivitySource> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectivitySource create(Ref ref) {
    return connectivitySource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectivitySource value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectivitySource>(value),
    );
  }
}

String _$connectivitySourceHash() =>
    r'1512dc0976ccd768a0670b046aeee04e3fa2613a';

/// Exposes the app-wide network reachability stream.
///
/// This provider is OBSERVABILITY ONLY (per P4-T4). It must not be wired into
/// any reactive reconnect logic, which is strictly deferred to Phase 7.

@ProviderFor(networkStatus)
final networkStatusProvider = NetworkStatusProvider._();

/// Exposes the app-wide network reachability stream.
///
/// This provider is OBSERVABILITY ONLY (per P4-T4). It must not be wired into
/// any reactive reconnect logic, which is strictly deferred to Phase 7.

final class NetworkStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<NetworkStatus>,
          NetworkStatus,
          Stream<NetworkStatus>
        >
    with $FutureModifier<NetworkStatus>, $StreamProvider<NetworkStatus> {
  /// Exposes the app-wide network reachability stream.
  ///
  /// This provider is OBSERVABILITY ONLY (per P4-T4). It must not be wired into
  /// any reactive reconnect logic, which is strictly deferred to Phase 7.
  NetworkStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'networkStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$networkStatusHash();

  @$internal
  @override
  $StreamProviderElement<NetworkStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<NetworkStatus> create(Ref ref) {
    return networkStatus(ref);
  }
}

String _$networkStatusHash() => r'708e400bf0700c5e39a6eb22b8b4d0f2d704923d';
