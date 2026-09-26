// SPDX-License-Identifier: GPL-3.0-or-later

/// Redacts sensitive information from log messages (IPs, keys, credentials).
///
/// Placement (SECURITY.md Section 4): this lives in `shared_utils` — NOT in
/// `apps/mobile` — because it must be callable from pure-Dart packages
/// (`core_domain`, `config_parser`) that must never depend on the Flutter
/// app. SECURITY.md Section 4 states that "the shared logging utility in
/// `packages/shared_utils` must provide a redaction helper that all logging
/// call sites for domain objects ... are required to use".
///
/// This package intentionally has ZERO external dependencies (pure Dart,
/// no Flutter, no `logger` package), so the redaction contract is expressed
/// as a plain function that the app's `AppLogger` composes with its own
/// logging backend.
///
/// Security note: this file deliberately implements NO `toString` overrides
/// and performs no logging of its own — it only transforms strings.
///
/// TODO(security): implement real redaction for IP addresses, credentials,
/// and keys — see SECURITY.md Section 4 logging policy. This is intentionally
/// a pass-through for Phase 1; the real rules depend on Phase 2 config
/// contents and Phase 3 native log formats, which do not exist yet.
String redact(String input) {
  // Stub implementation for Phase 1; returns input unchanged for now.
  return input;
}
