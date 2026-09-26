// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:mobile/core/logging/app_logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_logger_provider.g.dart';

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
@Riverpod(keepAlive: true)
AppLogger appLogger(Ref ref) {
  return AppLogger();
}
