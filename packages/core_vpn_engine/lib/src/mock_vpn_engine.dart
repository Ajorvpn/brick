// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart';

import 'vpn_command_result.dart';
import 'vpn_engine.dart';

/// In-memory reference implementation of [VpnEngine].
///
/// Why this exists: Phases 4–6 build the app skeleton, state management,
/// and UI against this type, before the real Android engine (Phase 3)
/// exists. It simulates the full lifecycle — accepted commands, delayed
/// transitions, streaming stats, and configurable failures — with no
/// native code, no TUN interface, and no network I/O.
///
/// The mock deliberately treats its internal state machine with the same
/// rigor the native engine will need: every transition is checked against
/// the legal transition graph, and an impossible sequence (for example
/// `Connected` → `Connecting` without passing through
/// [Disconnecting]/[Disconnected] first) throws a [StateError] instead of
/// silently producing a lie. That is the exact failure class of the legacy
/// prototype's "Connected over a dead tunnel" bug (ARCHITECTURE.md
/// Section 1.4, Problem 1). The check runs in all build modes because this
/// is a test double — there is no release build to protect, and a loud
/// failure inside a test is always the desired outcome.
///
/// Invariant 1 (acceptance ≠ final state): [start] and [stop] resolve as
/// soon as the command is accepted; the simulated delay and the resulting
/// transitions run on internal timers and are delivered exclusively via
/// [connectionState].
///
/// Invariant 2 (independent failure domains): [connectionState] and
/// [trafficStats] are backed by two independent broadcast controllers and
/// independent timers. Any error raised inside a stats tick is routed to
/// [trafficStats] only; the connection-state pipeline cannot be affected
/// by it.
///
/// Security note: this file intentionally overrides no `toString` on any
/// class and the engine performs no logging at all — profiles and configs
/// carry credentials (SECURITY.md).
final class MockVpnEngine implements VpnEngine {
  /// Creates a mock engine with configurable simulated timing and failure
  /// modes.
  ///
  /// The durations default to demo-friendly values; tests should pass
  /// millisecond-scale values to stay fast. The `simulate*` flags and
  /// [simulatedConnectionError] are mutable test hooks — flip them between
  /// calls to exercise rejection paths. They are NOT part of the
  /// [VpnEngine] contract.
  MockVpnEngine({
    this.connectDelay = const Duration(milliseconds: 300),
    this.disconnectDelay = const Duration(milliseconds: 200),
    this.statsInterval = const Duration(seconds: 1),
    this.txBytesPerTick = 65536,
    this.rxBytesPerTick = 262144,
    this.simulatePermissionDenied = false,
    this.simulateInvalidConfig = false,
    this.simulateStartupFailure = false,
    this.simulateStatsFailure = false,
    this.simulatedConnectionError,
  });

  /// Simulated latency between an accepted [start] and the engine settling
  /// on [Connected] (or on a simulated [Error]).
  final Duration connectDelay;

  /// Simulated latency between an accepted [stop] and [Disconnected].
  final Duration disconnectDelay;

  /// Period of the simulated traffic-stats ticks while [Connected].
  final Duration statsInterval;

  /// Bytes added to the transmitted counter on every stats tick.
  final int txBytesPerTick;

  /// Bytes added to the received counter on every stats tick.
  final int rxBytesPerTick;

  /// Test hook: when true, [start] is rejected with
  /// [VpnCommandRejectedPermissionDenied] and no state transition occurs.
  bool simulatePermissionDenied;

  /// Test hook: when true, [start] is rejected with
  /// [VpnCommandRejectedInvalidConfig] and no state transition occurs.
  bool simulateInvalidConfig;

  /// Test hook: when true, [start] fails immediately with
  /// [VpnCommandFailed] and no state transition occurs.
  bool simulateStartupFailure;

  /// Test hook: when non-null, the connect sequence settles on [Error]
  /// carrying this reason instead of [Connected] and no stats ticks start.
  ConnectionErrorReason? simulatedConnectionError;

  /// Test hook: when true, every stats tick routes a [StateError] to
  /// [trafficStats] instead of a snapshot, simulating a broken statistics
  /// pipeline. This hook goes beyond the required set in the P1-T5 scope:
  /// it exists so the independent-failure-domains invariant can be proven
  /// by a test rather than merely asserted in a doc comment.
  bool simulateStatsFailure;

  final _stateController = StreamController<ConnectionState>.broadcast();
  final _statsController = StreamController<TrafficStats>.broadcast();

  ConnectionState _state = const Disconnected();
  Timer? _transitionTimer;
  Timer? _statsTimer;
  int _txBytes = 0;
  int _rxBytes = 0;
  bool _disposed = false;

  // ── VpnEngine contract ─────────────────────────────────────────────

  @override
  Stream<ConnectionState> get connectionState => _stateController.stream;

  @override
  Stream<TrafficStats> get trafficStats => _statsController.stream;

  /// Requests a simulated connection to [profile].
  ///
  /// Acceptance matrix (the engine's current state decides the outcome):
  ///
  /// | Current state   | Result                                   |
  /// |-----------------|------------------------------------------|
  /// | `Disconnected`  | evaluate the `simulate*` hooks below      |
  /// | `Error`         | same as `Disconnected` (explicit retry)   |
  /// | `Connecting`    | [VpnCommandRejectedBusy]                  |
  /// | `Connected`     | [VpnCommandRejectedBusy]                  |
  /// | `Disconnecting` | [VpnCommandRejectedBusy]                  |
  ///
  /// Busy checks run before the simulated-fault hooks: an engine that is
  /// already running or tearing down could not have processed the command
  /// at all, so reporting a simulated permission denial for it would be a
  /// lie about what happened. `Disconnecting` counts as busy because the
  /// shipped [VpnCommandRejectedBusy] contract reads "already starting,
  /// stopping, or running", and accepting a start mid-teardown would need
  /// a `Disconnecting` -> `Connecting` hybrid transition that the state
  /// machine deliberately forbids.
  ///
  /// When several fault hooks are enabled at once, the first match in the
  /// order permission denied -> invalid config -> startup failure wins;
  /// tests are expected to enable one at a time.
  ///
  /// [profile] is deliberately neither retained nor inspected: only the
  /// container type matters to the mock. That keeps credentials out of
  /// engine memory (SECURITY.md) and makes explicit that the mock never
  /// pretends to validate configuration (real validation is Phase 2's
  /// parser).
  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    _assertNotDisposed();
    if (_state is Connecting ||
        _state is Connected ||
        _state is Disconnecting) {
      return const VpnCommandRejectedBusy();
    }
    if (simulatePermissionDenied) {
      return const VpnCommandRejectedPermissionDenied();
    }
    if (simulateInvalidConfig) {
      return const VpnCommandRejectedInvalidConfig();
    }
    if (simulateStartupFailure) {
      return const VpnCommandFailed();
    }
    _transitionTo(const Connecting());
    _scheduleConnectCompletion();
    return const VpnCommandAccepted();
  }

  /// Requests a simulated teardown.
  ///
  /// Acceptance matrix:
  ///
  /// | Current state   | Result                                    |
  /// |-----------------|-------------------------------------------|
  /// | `Connecting`    | accepted (cancels the pending attempt)     |
  /// | `Connected`     | accepted (stops the stats pipeline)        |
  /// | `Error`         | accepted (clears the recorded failure)     |
  /// | `Disconnecting` | [VpnCommandRejectedBusy] (no extra effect) |
  /// | `Disconnected`  | [VpnCommandRejectedBusy] (no extra effect) |
  ///
  /// Any pending delayed transition and the stats timer are cancelled
  /// before the teardown is announced, so a stop during the connecting
  /// phase genuinely cancels the in-progress attempt: no phantom
  /// `Connected` (or stats tick) from the previous session can surface
  /// afterwards.
  ///
  /// Idempotency (P1-T5 acceptance criteria) is guaranteed at the state
  /// level: repeated calls never alter a teardown already in flight. The
  /// second and later calls report [VpnCommandRejectedBusy] and the
  /// engine still settles on `Disconnected` exactly once — mirroring the
  /// Phase 3 native rule that "calling it multiple times has no
  /// additional effect beyond the first".
  @override
  Future<VpnCommandResult> stop() async {
    _assertNotDisposed();
    if (_state is Disconnected || _state is Disconnecting) {
      return const VpnCommandRejectedBusy();
    }
    _transitionTimer?.cancel();
    _transitionTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _transitionTo(const Disconnecting());
    _scheduleDisconnectCompletion();
    return const VpnCommandAccepted();
  }

  /// Current state snapshot without subscribing to [connectionState].
  ///
  /// Never derives the answer from a pending timer: during
  /// `connectDelay` the engine truthfully reports `Connecting`, not the
  /// state it is scheduled to reach (invariant: acceptance is not state).
  @override
  Future<ConnectionState> getStatus() async {
    _assertNotDisposed();
    return _state;
  }

  /// Releases the engine: cancels pending timers and closes both streams.
  ///
  /// Safe to call more than once — later calls are no-ops — so callers can
  /// hold it in `addTearDown`/`dispose` methods without bookkeeping. After
  /// disposal every command and query throws [StateError]: a disposed
  /// engine has no state to report, and silently succeeding would hide a
  /// use-after-dispose bug in the calling UI layer.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _transitionTimer?.cancel();
    _transitionTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    await _stateController.close();
    await _statsController.close();
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError(
        'MockVpnEngine used after dispose(): commands and queries are '
        'invalid once the engine has been released.',
      );
    }
  }

  // ── Simulated lifecycle internals ──────────────────────────────────

  void _scheduleConnectCompletion() {
    _transitionTimer = Timer(connectDelay, _completeConnect);
  }

  void _scheduleDisconnectCompletion() {
    _transitionTimer = Timer(disconnectDelay, _completeDisconnect);
  }

  /// Settles an accepted connect: either the simulated error or
  /// `Connected` plus the stats pipeline coming alive.
  void _completeConnect() {
    _transitionTimer = null;
    if (_disposed || _state is! Connecting) {
      return;
    }
    final failure = simulatedConnectionError;
    if (failure != null) {
      _transitionTo(Error(failure));
      return;
    }
    _transitionTo(const Connected());
    _startStatsTicks();
  }

  /// Settles an accepted stop, returning the engine to rest and clearing
  /// the per-session counters so the next session starts from zero.
  void _completeDisconnect() {
    _transitionTimer = null;
    if (_disposed || _state is! Disconnecting) {
      return;
    }
    _transitionTo(const Disconnected());
    _txBytes = 0;
    _rxBytes = 0;
  }

  void _startStatsTicks() {
    _statsTimer = Timer.periodic(statsInterval, (_) => _emitStatsTick());
  }

  /// Emits one synthetic traffic snapshot, or routes a simulated failure
  /// to the stats stream alone.
  ///
  /// Independent-failure-domains invariant: any error raised on this
  /// path is caught here and added to [_statsController] only. The
  /// connection-state controller is never touched from this method, so a
  /// broken statistics pipeline degrades statistics without ever
  /// affecting (or being able to affect) tunnel state — the coupling the
  /// legacy prototype suffered from is structurally impossible here.
  void _emitStatsTick() {
    if (_disposed || _state is! Connected || _statsController.isClosed) {
      return;
    }
    try {
      if (simulateStatsFailure) {
        throw StateError(
          'Simulated stats-pipeline failure '
          '(MockVpnEngine.simulateStatsFailure).',
        );
      }
      _txBytes += txBytesPerTick;
      _rxBytes += rxBytesPerTick;
      _statsController.add(
        TrafficStats(
          txBytes: _txBytes,
          rxBytes: _rxBytes,
          timestamp: DateTime.now(),
        ),
      );
    } catch (error, stackTrace) {
      _statsController.addError(error, stackTrace);
    }
  }

  /// Applies [next] after checking it against the legal transition graph.
  ///
  /// The check is unconditional (not debug-only) because this engine is a
  /// test double: there is no release build to protect, and a loud
  /// [StateError] inside a test is always better than a silently emitted
  /// impossible state that a UI test would then "verify".
  void _transitionTo(ConnectionState next) {
    if (!_isLegalTransition(_state, next)) {
      throw StateError(
        'Illegal MockVpnEngine transition: ${_state.runtimeType} -> '
        '${next.runtimeType}. Legal graph: Disconnected -> Connecting; '
        'Connecting -> Connected | Error | Disconnecting; Connected -> '
        'Disconnecting; Disconnecting -> Disconnected; Error -> '
        'Connecting | Disconnecting.',
      );
    }
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  /// The legal transition graph, expressed exhaustively over the sealed
  /// [ConnectionState] hierarchy so that a future new variant cannot
  /// silently escape this check (the analyzer rejects a non-exhaustive
  /// switch over a sealed type).
  static bool _isLegalTransition(ConnectionState from, ConnectionState to) =>
      switch (from) {
        Disconnected() => to is Connecting,
        Connecting() => to is Connected || to is Error || to is Disconnecting,
        Connected() => to is Disconnecting,
        Disconnecting() => to is Disconnected,
        Error() => to is Connecting || to is Disconnecting,
      };
}
