// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vpn_engine_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Exposes the global [VpnEngine] instance.
///
/// This is the app's single composition point for the VPN engine: every
/// feature depends on the [VpnEngine] *abstraction* (`ARCHITECTURE.md`
/// Section 3), and this provider decides which concrete implementation is
/// handed to them. Code generation is mandatory here
/// (`CODING_STANDARDS.md` Section 4), so this is a `@riverpod` function,
/// not a hand-written `Provider((ref) => ...)`.
///
/// Currently bound to [MockVpnEngine] for Phase 1–2 architecture and UI
/// development. In Phase 3 (native integration) this provider will be
/// overridden at the root composition level with the platform-native
/// `AndroidVpnEngine` implementation; because every consumer depends on
/// [VpnEngine] rather than on [MockVpnEngine], that swap requires **no
/// change** in `features/`.
///
/// Lifetime: the engine is a long-lived, app-scoped singleton. It is
/// disposed when this provider is destroyed (which, for the root
/// `ProviderScope`, means at app shutdown or on disposal in a test
/// container).
///
/// Security: the engine is created here without any `ServerProfile`
/// reference, and no config is ever passed to or retained by this file
/// (`SECURITY.md` Section 2 — server configuration is High-sensitivity
/// data). The mock deliberately performs no logging and overrides no
/// `toString` (`SECURITY.md` Section 4).
/// `keepAlive: true` is deliberate and load-bearing: a bare `@riverpod`
/// generates an AUTO-DISPOSE provider, which would tear the engine down the
/// moment the last widget watching it unmounts — killing a live tunnel
/// mid-connection. A VPN engine is an app-lifetime singleton, so it must
/// survive navigation and be disposed only with the root container.

@ProviderFor(vpnEngine)
final vpnEngineProvider = VpnEngineProvider._();

/// Exposes the global [VpnEngine] instance.
///
/// This is the app's single composition point for the VPN engine: every
/// feature depends on the [VpnEngine] *abstraction* (`ARCHITECTURE.md`
/// Section 3), and this provider decides which concrete implementation is
/// handed to them. Code generation is mandatory here
/// (`CODING_STANDARDS.md` Section 4), so this is a `@riverpod` function,
/// not a hand-written `Provider((ref) => ...)`.
///
/// Currently bound to [MockVpnEngine] for Phase 1–2 architecture and UI
/// development. In Phase 3 (native integration) this provider will be
/// overridden at the root composition level with the platform-native
/// `AndroidVpnEngine` implementation; because every consumer depends on
/// [VpnEngine] rather than on [MockVpnEngine], that swap requires **no
/// change** in `features/`.
///
/// Lifetime: the engine is a long-lived, app-scoped singleton. It is
/// disposed when this provider is destroyed (which, for the root
/// `ProviderScope`, means at app shutdown or on disposal in a test
/// container).
///
/// Security: the engine is created here without any `ServerProfile`
/// reference, and no config is ever passed to or retained by this file
/// (`SECURITY.md` Section 2 — server configuration is High-sensitivity
/// data). The mock deliberately performs no logging and overrides no
/// `toString` (`SECURITY.md` Section 4).
/// `keepAlive: true` is deliberate and load-bearing: a bare `@riverpod`
/// generates an AUTO-DISPOSE provider, which would tear the engine down the
/// moment the last widget watching it unmounts — killing a live tunnel
/// mid-connection. A VPN engine is an app-lifetime singleton, so it must
/// survive navigation and be disposed only with the root container.

final class VpnEngineProvider
    extends $FunctionalProvider<VpnEngine, VpnEngine, VpnEngine>
    with $Provider<VpnEngine> {
  /// Exposes the global [VpnEngine] instance.
  ///
  /// This is the app's single composition point for the VPN engine: every
  /// feature depends on the [VpnEngine] *abstraction* (`ARCHITECTURE.md`
  /// Section 3), and this provider decides which concrete implementation is
  /// handed to them. Code generation is mandatory here
  /// (`CODING_STANDARDS.md` Section 4), so this is a `@riverpod` function,
  /// not a hand-written `Provider((ref) => ...)`.
  ///
  /// Currently bound to [MockVpnEngine] for Phase 1–2 architecture and UI
  /// development. In Phase 3 (native integration) this provider will be
  /// overridden at the root composition level with the platform-native
  /// `AndroidVpnEngine` implementation; because every consumer depends on
  /// [VpnEngine] rather than on [MockVpnEngine], that swap requires **no
  /// change** in `features/`.
  ///
  /// Lifetime: the engine is a long-lived, app-scoped singleton. It is
  /// disposed when this provider is destroyed (which, for the root
  /// `ProviderScope`, means at app shutdown or on disposal in a test
  /// container).
  ///
  /// Security: the engine is created here without any `ServerProfile`
  /// reference, and no config is ever passed to or retained by this file
  /// (`SECURITY.md` Section 2 — server configuration is High-sensitivity
  /// data). The mock deliberately performs no logging and overrides no
  /// `toString` (`SECURITY.md` Section 4).
  /// `keepAlive: true` is deliberate and load-bearing: a bare `@riverpod`
  /// generates an AUTO-DISPOSE provider, which would tear the engine down the
  /// moment the last widget watching it unmounts — killing a live tunnel
  /// mid-connection. A VPN engine is an app-lifetime singleton, so it must
  /// survive navigation and be disposed only with the root container.
  VpnEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'vpnEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$vpnEngineHash();

  @$internal
  @override
  $ProviderElement<VpnEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VpnEngine create(Ref ref) {
    return vpnEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VpnEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VpnEngine>(value),
    );
  }
}

String _$vpnEngineHash() => r'a7a0ae6c6a34fe25a3695935bd43abc9c8f603bd';
