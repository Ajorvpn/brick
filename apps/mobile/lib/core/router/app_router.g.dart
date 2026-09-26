// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The app's [GoRouter] instance.
///
/// This is the single place where the route table is declared. Screens are
/// mapped to paths here and nowhere else, so adding a feature means adding
/// one entry to this list rather than threading navigation state through the
/// widget tree.
///
/// `keepAlive: true` is deliberate and load-bearing (same reasoning as
/// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
/// provider, and a [GoRouter] that were disposed whenever the last watcher
/// unmounted would lose its navigation state. The router must live exactly
/// as long as the app.
///
/// API note: `go_router` 18.x offers both the `GoRouter(routes: ...)`
/// constructor and the newer `GoRouter.routingConfig(routingConfig: ...)`
/// factory. Both are current and neither is deprecated; the constructor is
/// used here because it is the simplest form for a static route table, and
/// `routingConfig` is the right upgrade path if dynamic route lists are
/// needed later (verified against go_router 18.0.1 in the pub cache, not
/// assumed from training data).

@ProviderFor(appRouter)
final appRouterProvider = AppRouterProvider._();

/// The app's [GoRouter] instance.
///
/// This is the single place where the route table is declared. Screens are
/// mapped to paths here and nowhere else, so adding a feature means adding
/// one entry to this list rather than threading navigation state through the
/// widget tree.
///
/// `keepAlive: true` is deliberate and load-bearing (same reasoning as
/// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
/// provider, and a [GoRouter] that were disposed whenever the last watcher
/// unmounted would lose its navigation state. The router must live exactly
/// as long as the app.
///
/// API note: `go_router` 18.x offers both the `GoRouter(routes: ...)`
/// constructor and the newer `GoRouter.routingConfig(routingConfig: ...)`
/// factory. Both are current and neither is deprecated; the constructor is
/// used here because it is the simplest form for a static route table, and
/// `routingConfig` is the right upgrade path if dynamic route lists are
/// needed later (verified against go_router 18.0.1 in the pub cache, not
/// assumed from training data).

final class AppRouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// The app's [GoRouter] instance.
  ///
  /// This is the single place where the route table is declared. Screens are
  /// mapped to paths here and nowhere else, so adding a feature means adding
  /// one entry to this list rather than threading navigation state through the
  /// widget tree.
  ///
  /// `keepAlive: true` is deliberate and load-bearing (same reasoning as
  /// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
  /// provider, and a [GoRouter] that were disposed whenever the last watcher
  /// unmounted would lose its navigation state. The router must live exactly
  /// as long as the app.
  ///
  /// API note: `go_router` 18.x offers both the `GoRouter(routes: ...)`
  /// constructor and the newer `GoRouter.routingConfig(routingConfig: ...)`
  /// factory. Both are current and neither is deprecated; the constructor is
  /// used here because it is the simplest form for a static route table, and
  /// `routingConfig` is the right upgrade path if dynamic route lists are
  /// needed later (verified against go_router 18.0.1 in the pub cache, not
  /// assumed from training data).
  AppRouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appRouterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appRouterHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return appRouter(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$appRouterHash() => r'05fa2bf6c028a3e8c543ec2ba4d1abac4f0f18de';
