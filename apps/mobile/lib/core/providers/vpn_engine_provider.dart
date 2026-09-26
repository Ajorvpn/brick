// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vpn_engine_provider.g.dart';

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
@Riverpod(keepAlive: true)
VpnEngine vpnEngine(Ref ref) {
  final engine = MockVpnEngine();
  // `MockVpnEngine.dispose()` is asynchronous (it closes two broadcast
  // StreamControllers), but `onDispose` callbacks cannot be awaited. The
  // returned Future is intentionally not awaited: this is a best-effort
  // teardown at app shutdown, and an un-awaited close Future is safe here
  // because the mock cancels all of its timers synchronously in dispose().
  ref.onDispose(engine.dispose);
  return engine;
}
