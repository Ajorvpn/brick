// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart';

import 'vpn_command_result.dart';

/// The abstract contract every Brick VPN engine implementation must
/// satisfy (Android `VpnService` + libbox in Phase 3, the desktop daemon
/// in Phase 12, and the P1-T5 mock for tests).
///
/// Invariant 1 — Command acceptance is separate from final state:
/// `start()` and `stop()` return a `Future<VpnCommandResult>` describing
/// only whether the command was ACCEPTED (or why it was rejected). The
/// actual lifecycle transition — Disconnected → Connecting → Connected,
/// or anything else — is delivered asynchronously and EXCLUSIVELY via the
/// [connectionState] stream. UI code must NEVER infer "connected" from a
/// command's return value; a returned `VpnCommandAccepted` only means the
/// engine began executing the command. This separation exists because the
/// legacy prototype coupled the two, producing "Connected" UI states while
/// the tunnel was dead (ARCHITECTURE.md Section 1.4, Problem 1).
///
/// Invariant 2 — Independent failure domains (two separate streams):
/// [connectionState] and [trafficStats] are two structurally separate
/// streams backed by independent pipelines. A failure in the statistics
/// pipeline must NEVER be able to affect, block, or stall the connection
/// state pipeline, and vice versa. Implementations must back each stream
/// with its own error propagation (and must never funnel one into the
/// other); this directly addresses the legacy prototype's silently-failing
/// stats pipeline and its coupling with connection issues.
///
/// Implementation note: `abstract interface class` forbids inheriting any
/// implementation from this type — every implementor must provide the full
/// contract, keeping the seam between the app and the native/daemon layers
/// honest.
///
/// Security note: this interface intentionally has no `toString` at any
/// level of its hierarchy; implementations receive [ServerProfile] objects
/// carrying credentials that must never reach logs, per SECURITY.md.
abstract interface class VpnEngine {
  /// Authoritative connection-state stream.
  ///
  /// Emits every lifecycle transition (see [ConnectionState]). Errors on
  /// this stream concern the connection pipeline only (Invariant 2).
  Stream<ConnectionState> get connectionState;

  /// Throughput statistics stream.
  ///
  /// Emits [TrafficStats] snapshots while the tunnel is up. Errors on this
  /// stream concern the stats pipeline only and must never influence
  /// [connectionState] (Invariant 2).
  Stream<TrafficStats> get trafficStats;

  /// Requests a tunnel start for [profile].
  ///
  /// Returns quickly with an acceptance/rejection result (Invariant 1) —
  /// the returned future does NOT wait for the tunnel to be connected,
  /// and resolving with [VpnCommandAccepted] does NOT imply connectivity.
  /// Watch [connectionState] for the actual transition.
  Future<VpnCommandResult> start(ServerProfile profile);

  /// Requests a tunnel stop.
  ///
  /// Same acceptance semantics as [start] (Invariant 1): the result says
  /// the stop command was accepted, not that the tunnel is already down.
  /// The transition to [Disconnected] arrives on [connectionState].
  Future<VpnCommandResult> stop();

  /// Queries the engine's current state snapshot without subscribing.
  ///
  /// A point-in-time read for callers that need the state once (e.g. after
  /// process restart); lifecycle changes still arrive on [connectionState].
  Future<ConnectionState> getStatus();

  /// Obtains the platform's tunnel-consent grant before [start] can succeed.
  ///
  /// ## Why this method exists (P3-T12 discovery)
  ///
  /// This interface was written in P1-T4, before Android-specific realities
  /// were fully in view. It could *report* a missing permission — that is
  /// what [VpnCommandRejectedPermissionDenied] is for — but it offered no way
  /// to *request* one. Android makes that a hard requirement: `VpnService`
  /// cannot establish a TUN interface until the user has accepted the
  /// system's consent dialog (`VpnService.prepare()` returns an `Intent` that
  /// must be launched, and its result observed). A caller left with no way to
  /// ask could never clear the rejection it was being given.
  ///
  /// `ARCHITECTURE.md` Section 3.3 already anticipated exactly this
  /// amendment, so adding it here corrects the original design rather than
  /// expanding scope: "This interface is expected to be amended during
  /// Phase 3 (see P3-T12 in ROADMAP.md) to add an explicit prepare()-style
  /// permission-consent command, mirroring Android's `VpnService.prepare()`
  /// flow, which was not present in the original interface design above."
  ///
  /// ## Contract
  ///
  /// Returns *only* whether consent now holds — it must not be read as any
  /// statement about tunnel state (Invariant 1 still applies: consent is
  /// neither a command acceptance nor a connection). Resolving with
  /// [VpnCommandAccepted] means the caller may now call [start] without
  /// expecting a permission rejection; [VpnCommandRejectedPermissionDenied]
  /// means consent was refused and [start] will keep being refused until the
  /// user grants it.
  ///
  /// Platforms with no consent concept (the P1-T5 mock, and later desktop)
  /// answer [VpnCommandAccepted] immediately rather than pretending a
  /// dialog happened.
  Future<VpnCommandResult> prepare();
}
