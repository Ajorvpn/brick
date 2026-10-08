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
/// Session tokens (ARCHITECTURE.md Section 3.5, "Session tokens are
/// mandatory on every start()/stop() command"): every accepted command
/// claims a fresh token, and the delayed callbacks it schedules capture
/// that token. A callback whose captured token is no longer current
/// belongs to a superseded lifecycle attempt and is discarded at the point
/// of receipt, so a late "connected" event can never resurrect a session
/// the user already stopped.
///
/// Stop watchdog (ARCHITECTURE.md Section 3.5, "Stop watchdog with a hard
/// timeout"): entering [Disconnecting] arms [defaultStopWatchdogTimeout]
/// (5000 ms) as a fallback. If teardown has not completed by then the
/// watchdog forces [Disconnected] and cancels the pending completion — a
/// stuck `Disconnecting` is a P0 bug, never acceptable behaviour.
///
/// Security note: this file intentionally overrides no `toString` on any
/// class and the engine performs no logging at all — profiles and configs
/// carry credentials (SECURITY.md). [start] deliberately neither retains
/// nor inspects its [profile] argument.
final class MockVpnEngine implements VpnEngine {
  /// The hard watchdog ceiling mandated by ARCHITECTURE.md Section 3.5.
  ///
  /// A real engine may not exceed this. [stopWatchdogTimeout] is
  /// overridable only so the watchdog *mechanism* can be exercised in fast
  /// unit tests; the default always applies in production-shaped usage.
  static const Duration defaultStopWatchdogTimeout = Duration(
    milliseconds: 5000,
  );

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
    this.stopWatchdogTimeout = defaultStopWatchdogTimeout,
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

  /// Hard ceiling on how long [Disconnecting] may last before the watchdog
  /// forces [Disconnected].
  ///
  /// Defaults to [defaultStopWatchdogTimeout] (5000 ms); overridable only
  /// so tests can drive the watchdog path without a five-second wait.
  final Duration stopWatchdogTimeout;

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

  /// Monotonic session token (ARCHITECTURE.md Section 3.5).
  ///
  /// Incremented only when a command is *accepted* and therefore opens a
  /// new lifecycle attempt. A rejected or idempotent-no-op command must
  /// NOT bump it: doing so would invalidate the token of a genuinely
  /// in-flight attempt and strand the engine in [Connecting] forever.
  int _sessionToken = 0;

  Timer? _connectTimer;
  Timer? _disconnectTimer;
  Timer? _statsTimer;
  Timer? _stopWatchdogTimer;
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
    // Claim a fresh session token for the attempt we are about to open.
    // The delayed completion captures it and refuses to act if any later
    // accepted command has superseded it.
    final currentSession = ++_sessionToken;
    // Per-session counters are reset *before* the transition, so the
    // first tick of this session is that session's own first sample and
    // the previous session's totals can never leak into it.
    _txBytes = 0;
    _rxBytes = 0;
    _transitionTo(const Connecting());
    _scheduleConnectCompletion(currentSession);
    return const VpnCommandAccepted();
  }

  /// Requests a simulated teardown.
  ///
  /// Acceptance matrix (every outcome is [VpnCommandAccepted]; the rows
  /// differ only in whether a teardown routine is actually spawned):
  ///
  /// | Current state   | Result                                          |
  /// |-----------------|-------------------------------------------------|
  /// | `Disconnecting` | accepted, idempotent no-op (no second routine)   |
  /// | `Disconnected`  | accepted, idempotent no-op (nothing to tear down) |
  /// | `Connected`     | accepted (stops the stats pipeline)              |
  /// | `Connecting`    | accepted (cancels the pending attempt)           |
  /// | `Error`         | accepted (clears the recorded failure)           |
  ///
  /// `stop` is deliberately **always** idempotent and always accepted. A
  /// teardown is idempotent by nature, so reporting "busy" would be a lie
  /// that forces every caller to special-case a state that is already on
  /// its way to the requested resting state. This matches the P1-T5
  /// acceptance criterion "stop is idempotent" and the native rule that
  /// "calling it multiple times has no additional effect beyond the
  /// first": only the first call in a given state spawns a teardown.
  ///
  /// Any pending delayed transition, the stats timer, and the stop
  /// watchdog are cancelled or re-armed before the teardown is announced,
  /// so a stop during the connecting phase genuinely cancels the
  /// in-progress attempt: no phantom `Connected` (or stats tick) from the
  /// previous session can surface afterwards.
  @override
  Future<VpnCommandResult> stop() async {
    _assertNotDisposed();
    // Idempotent no-ops. Neither branch touches the session token, so an
    // in-flight teardown armed by the first call is never invalidated.
    if (_state is Disconnecting || _state is Disconnected) {
      return const VpnCommandAccepted();
    }
    final currentSession = ++_sessionToken;
    _connectTimer?.cancel();
    _connectTimer = null;
    _stopStatsTimer();
    _transitionTo(const Disconnecting());
    _scheduleDisconnectCompletion(currentSession);
    _armStopWatchdog(currentSession);
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

  /// Consent on a platform that has no consent dialog.
  ///
  /// The mock models connection lifecycle, not Android's `VpnService.prepare()`
  /// prompt — there is nothing to ask a user, so consent is already held and
  /// the answer is immediate. Returning [VpnCommandAccepted] here is not a
  /// faked *dialog outcome*; it is the truthful answer for a platform with no
  /// dialog, exactly as documented on `VpnEngine.prepare()`.
  ///
  /// Unlike a no-op stub it still enforces the disposed invariant, so a
  /// `prepare()` issued after `dispose()` fails loudly instead of implying a
  /// consent grant that could then be used to justify a later `start()`.
  @override
  Future<VpnCommandResult> prepare() async {
    _assertNotDisposed();
    return const VpnCommandAccepted();
  }

  /// Releases the engine: cancels pending timers and closes both streams.
  ///
  /// Safe to call more than once — later calls are no-ops — so callers can
  /// hold it in `addTearDown`/`dispose` methods without bookkeeping. After
  /// disposal every command and query throws [StateError]: a disposed
  /// engine has no state to report, and silently succeeding would hide a
  /// use-after-dispose bug in the calling UI layer.
  ///
  /// [dispose] also bumps the session token so any callback that is
  /// already queued but not yet delivered is discarded by the same
  /// stale-callback guard that protects ordinary command races.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _sessionToken++;
    _connectTimer?.cancel();
    _connectTimer = null;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    _stopWatchdogTimer?.cancel();
    _stopWatchdogTimer = null;
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

  // ── Failure-simulation hooks ────────────────────────────────────────

  /// Simulates the connect attempt failing while it is in flight.
  ///
  /// Only valid from [Connecting] — a real engine cannot fail a connection
  /// that was never attempted, and allowing it from [Connected] would let
  /// a test fabricate a failure for a tunnel that is demonstrably up.
  /// Throws [StateError] from any other state and after [dispose].
  ///
  /// Cancels the pending connect completion first, so a late completion
  /// cannot overwrite the injected failure with a spurious `Connected`.
  void simulateConnectionFailure([
    ConnectionErrorReason reason = const PlatformError(
      'Simulated connection failure',
    ),
  ]) {
    _assertNotDisposed();
    if (_state is! Connecting) {
      throw StateError(
        'Cannot simulate connection failure when state is '
        '${_state.runtimeType}. simulateConnectionFailure is only valid '
        'when state is Connecting.',
      );
    }
    _connectTimer?.cancel();
    _connectTimer = null;
    _stopStatsTimer();
    _sessionToken++;
    _transitionTo(Error(reason));
  }

  /// Simulates a tunnel that died without being asked to.
  ///
  /// Only valid from [Connected] — an unexpected drop is by definition a
  /// failure of an already-established tunnel. Throws [StateError] from
  /// any other state and after [dispose].
  void simulateUnexpectedDisconnect([
    ConnectionErrorReason reason = const PlatformError(
      'Simulated unexpected disconnect',
    ),
  ]) {
    _assertNotDisposed();
    if (_state is! Connected) {
      throw StateError(
        'Cannot simulate unexpected disconnect when state is '
        '${_state.runtimeType}. simulateUnexpectedDisconnect is only valid '
        'when state is Connected.',
      );
    }
    _stopStatsTimer();
    _sessionToken++;
    _transitionTo(Error(reason));
  }

  // ── Simulated lifecycle internals ──────────────────────────────────

  void _scheduleConnectCompletion(int session) {
    _connectTimer = Timer(connectDelay, () => _completeConnect(session));
  }

  void _scheduleDisconnectCompletion(int session) {
    _disconnectTimer = Timer(
      disconnectDelay,
      () => _completeDisconnect(session),
    );
  }

  /// Arms the hard stop watchdog for the in-flight teardown.
  ///
  /// If the engine is somehow still [Disconnecting] when this fires, the
  /// teardown is force-completed: a stuck `Disconnecting` state is a P0
  /// bug, never acceptable behaviour (ARCHITECTURE.md Section 3.5).
  ///
  /// The watchdog can only ever reach [Disconnected] because
  /// `Disconnecting -> Disconnected` is the only legal exit from
  /// [Disconnecting]; forcing an [Error] there would itself be an illegal
  /// transition.
  void _armStopWatchdog(int session) {
    _stopWatchdogTimer = Timer(
      stopWatchdogTimeout,
      () => _fireStopWatchdog(session),
    );
  }

  /// Watchdog callback: force the in-flight teardown to completion.
  void _fireStopWatchdog(int session) {
    _stopWatchdogTimer = null;
    // A stale watchdog must never touch a newer session.
    if (_disposed || session != _sessionToken || _state is! Disconnecting) {
      return;
    }
    // The normal completion is still pending; drop it so it cannot fire a
    // second, redundant transition afterwards.
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _stopStatsTimer();
    _transitionTo(const Disconnected());
  }

  /// Settles an accepted connect: either the simulated error or
  /// `Connected` plus the stats pipeline coming alive.
  ///
  /// The [session] guard is what makes a superseded attempt inert: if a
  /// `stop` (or a newer `start`) was accepted while this timer was
  /// pending, [_sessionToken] has moved on and this callback discards
  /// itself without transitioning anything.
  void _completeConnect(int session) {
    _connectTimer = null;
    if (_disposed || session != _sessionToken || _state is! Connecting) {
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

  /// Settles an accepted stop, returning the engine to rest.
  ///
  /// Cancels the stop watchdog on the graceful path, so a clean teardown
  /// never leaves a timer armed that could later force a redundant
  /// transition.
  void _completeDisconnect(int session) {
    _disconnectTimer = null;
    if (_disposed || session != _sessionToken || _state is! Disconnecting) {
      return;
    }
    _stopWatchdogTimer?.cancel();
    _stopWatchdogTimer = null;
    _transitionTo(const Disconnected());
  }

  void _startStatsTicks() {
    _statsTimer = Timer.periodic(statsInterval, (_) => _emitStatsTick());
  }

  void _stopStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = null;
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
    // Disposal is checked FIRST, before any other condition: a tick that
    // arrives after release must not touch a closed controller.
    if (_disposed) {
      return;
    }
    if (_state is! Connected || _statsController.isClosed) {
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
        'Disconnecting | Error; Disconnecting -> Disconnected; Error -> '
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
  ///
  /// Note the deliberate shape of the graph: an established tunnel can
  /// only be torn down ([Connected] -> [Disconnecting]) or fail
  /// unexpectedly ([Connected] -> [Error]); it can never go straight back
  /// to [Connecting], and [Disconnecting] has exactly one legal exit.
  static bool _isLegalTransition(ConnectionState from, ConnectionState to) =>
      switch (from) {
        Disconnected() => to is Connecting,
        Connecting() => to is Connected || to is Error || to is Disconnecting,
        Connected() => to is Disconnecting || to is Error,
        Disconnecting() => to is Disconnected,
        Error() => to is Connecting || to is Disconnecting,
      };
}
