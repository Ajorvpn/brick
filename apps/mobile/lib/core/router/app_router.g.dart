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
/// In Phase 4 (P4-T16), top-level tabs (Home and Settings) are hosted within
/// a [StatefulShellRoute.indexedStack] so that each tab preserves its own
/// navigation stack and scroll state.
///
/// `keepAlive: true` is deliberate and load-bearing (same reasoning as
/// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
/// provider, and a [GoRouter] that were disposed whenever the last watcher
/// unmounted would lose its navigation state. The router must live exactly
/// as long as the app.

@ProviderFor(appRouter)
final appRouterProvider = AppRouterProvider._();

/// The app's [GoRouter] instance.
///
/// This is the single place where the route table is declared. Screens are
/// mapped to paths here and nowhere else, so adding a feature means adding
/// one entry to this list rather than threading navigation state through the
/// widget tree.
///
/// In Phase 4 (P4-T16), top-level tabs (Home and Settings) are hosted within
/// a [StatefulShellRoute.indexedStack] so that each tab preserves its own
/// navigation stack and scroll state.
///
/// `keepAlive: true` is deliberate and load-bearing (same reasoning as
/// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
/// provider, and a [GoRouter] that were disposed whenever the last watcher
/// unmounted would lose its navigation state. The router must live exactly
/// as long as the app.

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
  /// In Phase 4 (P4-T16), top-level tabs (Home and Settings) are hosted within
  /// a [StatefulShellRoute.indexedStack] so that each tab preserves its own
  /// navigation stack and scroll state.
  ///
  /// `keepAlive: true` is deliberate and load-bearing (same reasoning as
  /// `vpnEngineProvider`): a bare `@riverpod` generates an auto-dispose
  /// provider, and a [GoRouter] that were disposed whenever the last watcher
  /// unmounted would lose its navigation state. The router must live exactly
  /// as long as the app.
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

String _$appRouterHash() => r'2340a0c46fbbdafc65adcb1ed9a49427832c31c9';
