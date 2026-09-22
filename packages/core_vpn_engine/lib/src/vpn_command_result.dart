// SPDX-License-Identifier: GPL-3.0-or-later

/// The immediate, synchronous outcome of a `VpnEngine.start()` or
/// `VpnEngine.stop()` command.
///
/// Why this type exists: command ACCEPTANCE and connection STATE are two
/// different things. A `VpnCommandAccepted` result means "the engine took
/// the command and began executing it" — nothing more. It NEVER means the
/// VPN is connected, connecting, or even that the command will ultimately
/// succeed; the authoritative state lives exclusively on the
/// `VpnEngine.connectionState` stream (see ARCHITECTURE.md Section 3).
///
/// File-level security note: no class in this file overrides `toString`.
/// Result payloads in later phases may reference failure details that must
/// never leak into system logs via an incidental print, per SECURITY.md.
///
/// Sealing note: `VpnCommandResult` is `sealed`, so the set of outcomes is
/// closed at compile time and callers can switch over it exhaustively.
sealed class VpnCommandResult {
  const VpnCommandResult();

  /// Stable discriminator string for serialization and logging switches.
  String get type;

  /// Deterministic JSON mapping with the `'type'` discriminator entry.
  Map<String, dynamic> toJson();
}

/// The command was accepted and execution began. Carries no implication
/// about the eventual connection state.
final class VpnCommandAccepted extends VpnCommandResult {
  const VpnCommandAccepted();

  @override
  String get type => 'accepted';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VpnCommandAccepted;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// The command was rejected because the engine is already starting,
/// stopping, or running. Callers should wait for the state stream instead
/// of retrying in a tight loop.
final class VpnCommandRejectedBusy extends VpnCommandResult {
  const VpnCommandRejectedBusy();

  @override
  String get type => 'rejected_busy';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VpnCommandRejectedBusy;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// The command was rejected because the supplied [ServerProfile] config is
/// malformed or invalid (missing required fields, unreachable shape, etc.).
final class VpnCommandRejectedInvalidConfig extends VpnCommandResult {
  const VpnCommandRejectedInvalidConfig();

  @override
  String get type => 'rejected_invalid_config';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VpnCommandRejectedInvalidConfig;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// The command was rejected because the OS VPN permission was denied by
/// the user (e.g. the Android VpnService consent dialog was dismissed).
final class VpnCommandRejectedPermissionDenied extends VpnCommandResult {
  const VpnCommandRejectedPermissionDenied();

  @override
  String get type => 'rejected_permission_denied';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VpnCommandRejectedPermissionDenied;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// The native engine threw an immediate error during startup preparation.
/// The command never became "in flight"; no state transition was queued.
final class VpnCommandFailed extends VpnCommandResult {
  const VpnCommandFailed();

  @override
  String get type => 'failed';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VpnCommandFailed;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  Map<String, dynamic> toJson() => {'type': type};
}
