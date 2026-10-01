// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok, Result;

/// Turns a pasted server URI into a ready-to-persist [ServerProfile].
///
/// This is a domain use case, not a widget helper: "what does this text
/// mean?" is a decision, and `presentation/` may not make decisions. It
/// lives here so that no widget ever calls `parseUri()` itself and so the
/// parse/identity/timestamp sequence is defined in exactly one place.
///
/// Why it may import `config_parser`: that package is pure Dart by design
/// ("must never gain a Flutter dependency"), so depending on it from a
/// framework-agnostic layer keeps this class unit-testable with `dart test`
/// alone — no widget tree, no binding, no device. It is an external package,
/// not this feature's `data/` layer, so this is not a layering violation.
///
/// Identity and timestamp are supplied here rather than generated inside
/// `config_parser` because every parser there is a pure, deterministic
/// function (no clock, no randomness); `toServerProfile` requires the caller
/// to own both.
final class BuildServerProfile {
  /// Creates the use case.
  const BuildServerProfile();

  /// Parses [uri] and wraps the result in a [ServerProfile].
  ///
  /// Returns the [ConfigParseError] untouched on failure so the caller can
  /// display `error.message`, which `config_parser` guarantees never
  /// interpolates the offending input.
  Result<ServerProfile, ConfigParseError> call({
    required String uri,
    required String id,
    required DateTime addedAt,
  }) {
    return switch (parseUri(uri)) {
      Ok(:final value) => Ok(
        value.toServerProfile(
          id: id,
          addedAt: addedAt,
          // A URI fragment is the user's own label for the server; without
          // one, `toServerProfile` falls back to `host:port`.
          customRemark: parseUriRemark(uri),
        ),
      ),
      Err(:final error) => Err(error),
    };
  }
}
