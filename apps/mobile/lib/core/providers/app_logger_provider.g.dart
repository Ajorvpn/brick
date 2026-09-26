// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_logger_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Exposes the app-wide [AppLogger].
///
/// This is the documented, single access pattern for logging
/// (SECURITY.md Section 4): every call site resolves the logger from here
/// instead of constructing a `Logger` directly, which guarantees that both
/// the redaction contract and the release-mode gate are applied.
///
/// `keepAlive: true` is deliberate and load-bearing, consistent with
/// `vpnEngineProvider` (P1-T7) and `appRouterProvider` (P1-T8): the logger
/// is app-lifetime infrastructure. A bare `@riverpod` would auto-dispose it,
/// producing a new `Logger` (and losing any registered `onLog` listeners)
/// whenever the last watching widget unmounted.
///
/// The provider is intentionally cheap to override in tests, e.g.
/// `appLoggerProvider.overrideWith(AppLogger(log: fakeLogger))`, so a test
/// can assert emitted output without touching the console.

@ProviderFor(appLogger)
final appLoggerProvider = AppLoggerProvider._();

/// Exposes the app-wide [AppLogger].
///
/// This is the documented, single access pattern for logging
/// (SECURITY.md Section 4): every call site resolves the logger from here
/// instead of constructing a `Logger` directly, which guarantees that both
/// the redaction contract and the release-mode gate are applied.
///
/// `keepAlive: true` is deliberate and load-bearing, consistent with
/// `vpnEngineProvider` (P1-T7) and `appRouterProvider` (P1-T8): the logger
/// is app-lifetime infrastructure. A bare `@riverpod` would auto-dispose it,
/// producing a new `Logger` (and losing any registered `onLog` listeners)
/// whenever the last watching widget unmounted.
///
/// The provider is intentionally cheap to override in tests, e.g.
/// `appLoggerProvider.overrideWith(AppLogger(log: fakeLogger))`, so a test
/// can assert emitted output without touching the console.

final class AppLoggerProvider
    extends $FunctionalProvider<AppLogger, AppLogger, AppLogger>
    with $Provider<AppLogger> {
  /// Exposes the app-wide [AppLogger].
  ///
  /// This is the documented, single access pattern for logging
  /// (SECURITY.md Section 4): every call site resolves the logger from here
  /// instead of constructing a `Logger` directly, which guarantees that both
  /// the redaction contract and the release-mode gate are applied.
  ///
  /// `keepAlive: true` is deliberate and load-bearing, consistent with
  /// `vpnEngineProvider` (P1-T7) and `appRouterProvider` (P1-T8): the logger
  /// is app-lifetime infrastructure. A bare `@riverpod` would auto-dispose it,
  /// producing a new `Logger` (and losing any registered `onLog` listeners)
  /// whenever the last watching widget unmounted.
  ///
  /// The provider is intentionally cheap to override in tests, e.g.
  /// `appLoggerProvider.overrideWith(AppLogger(log: fakeLogger))`, so a test
  /// can assert emitted output without touching the console.
  AppLoggerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLoggerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLoggerHash();

  @$internal
  @override
  $ProviderElement<AppLogger> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppLogger create(Ref ref) {
    return appLogger(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppLogger value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppLogger>(value),
    );
  }
}

String _$appLoggerHash() => r'3699c15aceb1e23139f386ef70915703ccabf195';
