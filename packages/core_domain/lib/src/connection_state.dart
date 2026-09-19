// SPDX-License-Identifier: GPL-3.0-or-later

/// Why this state exists: the UI, the engine, and future storage code all
/// need one shared vocabulary for "what is the VPN doing right now" so a
/// new state cannot be invented ad hoc in one layer and misread in another.
///
/// The type is `sealed` with exactly five variants so every `switch` over a
/// [ConnectionState] is exhaustiveness-checked by the analyzer: forgetting a
/// variant is a compile-time error, not a runtime surprise. [Error] carries
/// a structured [ConnectionErrorReason] instead of a bare string so calling
/// code is statically forced to branch on the failure category (a direct
/// lesson from the legacy prototype, where vague string error states
/// produced undebuggable behavior).
sealed class ConnectionState {
  const ConnectionState();
}

/// No tunnel exists and no connection attempt is running.
///
/// This is both the initial state before the first connect and the resting
/// state after a clean disconnect or after an error has been dismissed.
final class Disconnected extends ConnectionState {
  const Disconnected();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A connection attempt is in flight but no traffic flows yet.
final class Connecting extends ConnectionState {
  const Connecting();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A working tunnel exists and traffic may flow.
final class Connected extends ConnectionState {
  const Connected();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A teardown was requested and is in flight; the tunnel is not yet gone.
final class Disconnecting extends ConnectionState {
  const Disconnecting();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The last connection attempt or the active tunnel failed.
///
/// The failure category travels as a structured [reason] so UI copy,
/// retry policy, and logging can branch on it exhaustively instead of
/// parsing a human-readable message.
final class Error extends ConnectionState {
  const Error(this.reason);

  /// Structured failure category for this error state.
  final ConnectionErrorReason reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is Error &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(runtimeType, reason);
}

/// Why a sealed class instead of an enum: one variant ([PlatformError])
/// must carry a `String detail` payload, which a plain enum cannot do, and
/// Phase 3 will need to extend the native-error taxonomy without breaking
/// existing exhaustive switches. A sealed hierarchy gives both payload
/// support and compile-time exhaustiveness today.
///
/// All reasons are immutable value objects with value equality so they can
/// be compared and stored without identity surprises.
sealed class ConnectionErrorReason {
  const ConnectionErrorReason();
}

/// The operating system denied a permission required to run the VPN
/// (for example the Android VpnService consent dialog was rejected).
final class PermissionDenied extends ConnectionErrorReason {
  const PermissionDenied();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The selected server profile or generated engine config was invalid,
/// so no connection attempt could be started.
final class InvalidConfig extends ConnectionErrorReason {
  const InvalidConfig();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The underlying platform or engine reported a failure that does not fit
/// the categories above. The opaque native message travels in [detail] for
/// diagnostics; calling code must not branch on its text.
final class PlatformError extends ConnectionErrorReason {
  const PlatformError(this.detail);

  /// Opaque native detail for diagnostics only, never for branching.
  final String detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is PlatformError &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(runtimeType, detail);
}

/// A failure whose category is genuinely not known yet.
///
/// This is a deliberate escape hatch for the skeleton phase, not a default
/// bucket: once the Phase 3 native error taxonomy is defined, new reasons
/// should be added instead of reusing [Unknown].
final class Unknown extends ConnectionErrorReason {
  const Unknown();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}
