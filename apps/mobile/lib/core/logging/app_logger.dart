// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:logger/logger.dart';
import 'package:shared_utils/shared_utils.dart' show redact;

/// Application logging facade.
///
/// This is the ONE supported way to emit log output anywhere in the app
/// (SECURITY.md Section 4). Features must not construct `Logger` instances
/// directly: an ad-hoc instance would bypass both the redaction contract
/// and the release-mode gate, which are exactly the two things this class
/// exists to enforce.
///
/// Two responsibilities:
///
/// 1. **Redaction.** Every message is passed through [redact] before it
///    reaches the logging backend. `redact` lives in `shared_utils` (pure
///    Dart) so that pure-Dart packages can redact too; this class is only
///    the composition point that wires it into the `logger` backend.
///
/// 2. **Release-mode silence.** In [kReleaseMode] the underlying filter is
///    set to [Level.off], so `d/i/w/e` emit **nothing at all**. This is the
///    concrete implementation of SECURITY.md Section 4 ("never in any log
///    output outside a local debug build") and Section 10 (no telemetry).
///    The gate is applied via the `logger` package's own filter, so a
///    silenced logger does no formatting work and produces no output
///    stream, rather than relying on call sites to remember to check.
///
/// Security note: this class must never be handed a raw `ServerProfile` or
/// `OutboundConfig` to stringify. Domain value types intentionally have no
/// `toString` override precisely so that accidental interpolation is a
/// no-op rather than a credential leak. Pass a pre-summarised string and
/// let [redact] be the single choke point.
///
// TODO(Ajorvpn): `redact` is a pass-through stub; real masking arrives in
// Phase 8 per SECURITY.md Section 4,
// https://github.com/Ajorvpn/brick/issues/8
class AppLogger {
  /// Wraps a `logger` package instance configured for the current build.
  ///
  /// [log] is injectable for tests so behaviour can be asserted without
  /// depending on console output.
  AppLogger({Logger? log, bool? isReleaseMode})
    : _isReleaseMode = isReleaseMode ?? kReleaseMode,
      _log =
          log ??
          Logger(
            // `Level.off` short-circuits the filter, so a release build
            // produces zero output regardless of what is logged.
            level: (isReleaseMode ?? kReleaseMode) ? Level.off : Level.debug,
          );

  final Logger _log;
  final bool _isReleaseMode;

  /// Whether this logger is running in a release build.
  ///
  /// Exposed so the release-mode gate can be asserted by a test rather than
  /// inferred from captured console output.
  bool get isReleaseMode => _isReleaseMode;

  /// Whether this logger will emit anything.
  ///
  /// Always `false` in release mode, regardless of level arguments.
  bool get isEnabled => !_isReleaseMode;

  /// Debug-level message. Redacted before emission.
  void d(Object? message) => _emit(Level.debug, message);

  /// Info-level message. Redacted before emission.
  void i(Object? message) => _emit(Level.info, message);

  /// Warning-level message. Redacted before emission.
  void w(Object? message) => _emit(Level.warning, message);

  /// Error-level message. Redacted before emission.
  ///
  /// [error] and [stackTrace] are attached for diagnostics. They are NOT
  /// run through [redact] because they are `Object`s rather than log
  /// strings; if a caller ever needs to log a sensitive object here, it
  /// must summarise it to a String first and pass that as [message].
  void e(Object? message, [Object? error, StackTrace? stackTrace]) {
    _emit(Level.error, message, error: error, stackTrace: stackTrace);
  }

  /// Routes [message] through [redact] and then to the backend.
  ///
  /// Redaction happens on EVERY path, including release mode, so that the
  /// redaction contract cannot be bypassed by a future call site that adds
  /// its own level check.
  void _emit(
    Level level,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final safe = message == null ? null : redact(message.toString());
    _log.log(level, safe, error: error, stackTrace: stackTrace);
  }
}
