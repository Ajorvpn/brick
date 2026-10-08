// SPDX-License-Identifier: GPL-3.0-or-later
//
// P3-T12 — Pigeon schema for the Brick VPN Android engine.
//
// ARCHITECTURE.md Section 3.5 (lines 361-366) is non-negotiable:
//   "All platform-channel commands must use Pigeon-generated type-safe
//    interfaces, never hand-written MethodChannel string-keyed method names
//    or raw argument maps. High-frequency streams (connection state, traffic
//    stats, logs) must use EventChannel (or a typed equivalent generated/
//    wrapped for type safety) rather than repeated method-channel polling."
//
// CODEGEN IS MANUAL, NOT A BUILD HOOK (T12 Scope asks us to decide + justify):
//   cd packages/vpn_engine_android && dart run pigeon
//
//   Why manual rather than a Gradle/build_runner hook:
//    1. Riverpod codegen in this repo is also manual and its generated files
//       are COMMITTED (.g.dart are not gitignored) — this follows that
//       project-wide convention, which T12's AC4 explicitly asks us to match.
//    2. Generated output must be reviewable in the diff; a hook that rewrites
//       sources during `gradlew build` makes `--set-exit-if-changed` and code
//       review meaningless.
//    3. Pigeon is a dev_dependency of THIS package only, so a hook would make
//       every Flutter build depend on the generator being resolvable.
//
// TYPE VOCABULARY — deliberately native-shaped, not Dart-shaped:
//   The bridge carries the NATIVE 8-state `VpnState` hierarchy and the NATIVE
//   5-variant `VpnCommandResult`, not core_domain's 5-variant
//   `ConnectionState`. Collapsing 8 -> 5 here in Kotlin would push a mapping
//   decision into P3-T13 (which must contain no judgment at all) and would
//   destroy the `Revoked` vs `Error(reason)` distinction that
//   ARCHITECTURE.md line 202 documents as a lossy 8 -> 5 mapping. The
//   collapse therefore belongs to P3-T14, whose `AndroidVpnEngine` is
//   explicitly required to "correct mapping of every Pigeon type to/from
//   ConnectionState".

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/vpn_engine_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/dev/brickvpn/harness/vpn/VpnEngineApi.g.kt',
    // Without this the generated file has NO `package` declaration at all —
    // Pigeon does not infer it from the output directory — leaving the Kotlin
    // types in the default/root package, which cannot see the Gate A types it
    // sits beside. Set explicitly to match the migrated Gate A namespace.
    kotlinOptions: KotlinOptions(package: 'dev.brickvpn.harness.vpn'),
    // The DART package name (not the Android `package:`). Channel names derive
    // from this: dev.flutter.pigeon.<dartPackageName>.<Api>.<method>.
    dartPackageName: 'vpn_engine_android',
  ),
)

/// Mirrors the native `dev.brickvpn.harness.vpn.VpnState` sealed hierarchy —
/// all EIGHT variants, including the two with no Dart equivalent.
///
/// Do NOT "simplify" this to core_domain's five `ConnectionState` variants:
/// `Revoked` is Android-specific (ARCHITECTURE.md line 209: "VPN permission
/// revocation is an Android-specific concept") and must survive the bridge so
/// P3-T14 can map it to `Error(PermissionDenied)` explicitly.
enum VpnNativeState {
  idle,
  preparing,
  starting,
  running,
  stopping,
  stopped,
  error,
  revoked,
}

/// Mirrors native `dev.brickvpn.harness.vpn.VpnCommandResult` — all FIVE
/// variants, matching `core_vpn_engine`'s discriminators 1:1 (`accepted`,
/// `rejected_busy`, `rejected_invalid_config`, `rejected_permission_denied`,
/// `failed`).
///
/// Reachability note (recorded so no later task mistakes it for a bug): the
/// native `VpnStateMachine.start()` can currently return only `accepted` /
/// `rejectedBusy` / `rejectedPermissionDenied`, and `stop()` returns only
/// `accepted`, because no config validation exists on that path yet. The enum
/// still carries all five because `VpnCommandResult` is a *sealed* type in
/// Dart — omitting a variant would make P3-T14's exhaustive switch impossible
/// to write faithfully.
enum VpnCommandOutcome {
  accepted,
  rejectedBusy,
  rejectedInvalidConfig,
  rejectedPermissionDenied,
  failed,
}

/// Result of the Android VPN consent flow (`VpnService.prepare()`).
///
/// This is the P3-T12 AC3 addition: the original P1-T4 interface was written
/// before Android's consent dialog was in view, so it models no way to ASK for
/// permission — only a way to be REJECTED for lacking it. The distinction
/// between [alreadyGranted] and [granted] is preserved deliberately: UI code
/// needs to know whether it may prompt immediately or whether a rationale
/// screen should come first.
enum VpnConsentStatus {
  /// Consent was already held; no system dialog was shown.
  alreadyGranted,

  /// The system consent dialog was shown and the user accepted it.
  granted,

  /// The dialog was shown and refused (or consent was revoked since).
  /// `start()` will be rejected until consent is obtained.
  denied,
}

/// One emission of the connection-state event channel.
///
/// `errorReason` is non-null exactly when [state] is [VpnNativeState.error],
/// mirroring native `VpnState.Error(val reason: String)`. Keeping the reason
/// attached to the event (rather than on a side channel) makes each emission
/// self-contained and order-preserving.
class VpnStateEvent {
  VpnStateEvent({required this.state, this.errorReason});

  VpnNativeState state;

  /// Native failure reason. Null unless [state] is `error`.
  String? errorReason;
}

/// One emission of the traffic-stats event channel.
///
/// KNOWN GAP, DELIBERATE (P3-T8 is `Not Started`): the native engine has no
/// stats source yet — `TunnelEngine` exposes only `start(tunFd)`/`stop()`.
/// The channel exists so the transport shape is fixed now, but the Kotlin side
/// emits NOTHING on it until P3-T8 supplies a real reader. Emitting invented
/// zeros would look like "connected but idle", which is precisely the legacy
/// "traffic always 0 bytes" failure this project must not repeat. P3-T14
/// inherits this gap and must not present an empty stream as a measured zero.
class TrafficStatsEvent {
  TrafficStatsEvent({
    required this.txBytes,
    required this.rxBytes,
    required this.epochMillis,
  });

  /// Cumulative bytes sent through the tunnel.
  int txBytes;

  /// Cumulative bytes received through the tunnel.
  int rxBytes;

  /// When the counters were read, epoch milliseconds (UTC). Milliseconds
  /// rather than `DateTime` so the value survives the `StandardMessageCodec`
  /// round-trip identically without local-time-zone handling.
  int epochMillis;
}

/// Commands Flutter invokes on the Android host.
///
/// Acceptance is separate from final state (ARCHITECTURE.md Section 3.5,
/// lines 367-374): [start]/[stop] report only whether the command was accepted
/// for processing. The resulting transition arrives EXCLUSIVELY on the
/// `stateEvents` stream below and must never be inferred from these return
/// values.
@HostApi()
abstract class VpnEngineHostApi {
  /// Obtains Android's `VpnService` consent, prompting the user if needed.
  ///
  /// `@async` because showing the system dialog and waiting for the user is
  /// inherently asynchronous on the Kotlin side; a plain method would force
  /// the host implementation to block a thread on a UI dialog.
  ///
  /// Maps in P3-T14 to `core_vpn_engine`'s `VpnEngine.prepare()`:
  /// `alreadyGranted`/`granted` -> `VpnCommandAccepted`,
  /// `denied` -> `VpnCommandRejectedPermissionDenied`.
  @async
  VpnConsentStatus prepare();

  /// Requests a tunnel start.
  ///
  /// [profileJson] is `ServerProfile.toJson()` from `core_domain` — NOT a
  /// Pigeon mirror of `ServerProfile`'s polymorphic `OutboundConfig`
  /// hierarchy. Serializing rather than re-modeling avoids inventing a second
  /// vocabulary for the same value (P1-T3 already proved `ServerProfile`
  /// round-trips losslessly through `toJson()`), and `core_domain` stays
  /// frozen.
  ///
  /// The type is `Map<String, Object?>` and deliberately NOT
  /// `Map<String, dynamic>`: Pigeon transcribes Dart `dynamic` verbatim into
  /// Kotlin `dynamic`, and Kotlin/JVM rejects that with
  /// "Dynamic type is only supported in Kotlin JS" — a JVM compile error that
  /// only appears once the generated file is compiled, not when Pigeon runs.
  ///
  /// KNOWN GAP for P3-T14/P3-T15: the native engine cannot consume this yet.
  /// `TunnelEngine.start(tunFd: Int)` takes no config and
  /// `LibboxTunnelEngine.configJsonProvider` defaults to the hardcoded
  /// `GATE_A_CONFIG_JSON`. P3-T15's own scope says to keep the hardcoded
  /// config for now, so the profile is carried faithfully across the bridge
  /// and deliberately not yet consumed. It must NOT be dropped here: doing so
  /// would lose information the contract requires.
  VpnCommandOutcome start(Map<String, Object?> profileJson);

  /// Requests a tunnel stop. Same acceptance semantics as [start].
  VpnCommandOutcome stop();

  /// Point-in-time state read for callers that are not subscribed (e.g. after
  /// a process restart, before the UI settles on an initial display).
  VpnStateEvent getStatus();
}

/// Host -> Flutter push streams.
///
/// Two structurally SEPARATE channels, not one multiplexed channel:
/// `core_vpn_engine`'s `VpnEngine` Invariant 2 requires that a failure in the
/// statistics pipeline can never block or corrupt the connection-state
/// pipeline. Sharing a channel would re-couple them at the transport layer and
/// silently violate that invariant.
///
/// Pigeon 29.0.6 generates a real `io.flutter.plugin.common.EventChannel` for
/// these (verified against the installed package, not assumed) — no hand-rolled
/// EventChannel and no method-channel polling.
@EventChannelApi()
abstract class VpnEngineEventChannels {
  /// Every state transition, in order.
  VpnStateEvent stateEvents();

  /// Traffic snapshots. Emits nothing until P3-T8 lands — see `TrafficStatsEvent`.
  TrafficStatsEvent trafficStatsEvents();
}
