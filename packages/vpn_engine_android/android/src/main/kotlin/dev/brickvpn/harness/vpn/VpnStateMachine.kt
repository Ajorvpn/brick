package dev.brickvpn.harness.vpn

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * A monotonically-increasing identifier for one lifecycle attempt.
 *
 * Every `start()` mints a fresh token. Engine callbacks carry the token they
 * were issued under, so a superseded attempt's late callback can be discarded
 * at the point of receipt instead of corrupting the current session. This is
 * `ARCHITECTURE.md` Section 3.5's "session tokens are mandatory on every
 * start()/stop() command" rule, and it is the mechanism that prevents a
 * "stopping" state being overwritten by a late callback from a previous
 * session.
 */
@JvmInline
value class SessionToken(val value: Long) {
    override fun toString() = "SessionToken($value)"
}

/**
 * The VPN lifecycle state machine for the native Android harness.
 *
 * ## Pure Kotlin by construction
 *
 * This class imports **no Android framework class** — no `Context`, no
 * `VpnService`, no `ParcelFileDescriptor`. It is therefore unit-testable on a
 * host JVM with no emulator and no Robolectric. `VpnService` (P3-T6) becomes a
 * thin adapter that owns the Android objects and delegates here.
 *
 * ## Thread safety
 *
 * All state mutation happens inside [lock]. The public surface is synchronous
 * (commands return an acceptance result immediately, per Section 3.5); only the
 * watchdog runs on [scope].
 *
 * ## Watchdogs — two, with deliberately different destinations
 *
 * Section 3.5 mandates a hard 5000 ms watchdog on any transition into a
 * stopping state. This class additionally guards the start path, because a start
 * that never settles is the same class of bug.
 *
 * The two watchdogs resolve differently, and this asymmetry is intentional:
 *
 *  - **Start watchdog** -> `Error("Watchdog timeout after 5000ms")`. Legal,
 *    because `Preparing`/`Starting` -> `Error` is in the normative graph.
 *  - **Stop watchdog** -> `Stopped`, **not** `Error`. `Stopping` -> `Error` is
 *    *forbidden* by Section 3.1.1 precisely "so the 5000 ms stop watchdog
 *    [can] force a stuck teardown to a legal resting state instead of needing
 *    an escape hatch". Forcing `Error` here would violate the normative graph
 *    to satisfy a timeout, which is exactly the "silently coercing an
 *    impossible transition" the architecture forbids.
 *
 * In both cases the decision is recorded in [lastWatchdogMessage] so a forced
 * transition is auditable rather than silent.
 *
 * @param scope coroutine scope for the watchdogs. Tests pass `backgroundScope`
 *   from `runTest` so the 5000 ms window is virtual time, not a real sleep.
 * @param watchdogTimeoutMillis hard ceiling for a pending transition.
 */
class VpnStateMachine(
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    val watchdogTimeoutMillis: Long = DEFAULT_WATCHDOG_TIMEOUT_MILLIS,
) {

    private val lock = Any()
    private val _state = MutableStateFlow<VpnState>(VpnState.Idle)

    /** Authoritative, observable state. */
    val state: StateFlow<VpnState> = _state.asStateFlow()

    /** Convenience accessor for the current state. */
    val currentState: VpnState get() = _state.value

    private var tokenSeq: Long = 0
    private var activeToken: SessionToken? = null
    private var watchdogJob: Job? = null

    /** Set when a watchdog fires, so a forced transition is never silent. */
    @Volatile
    var lastWatchdogMessage: String? = null
        private set

    /** Diagnostic record of the most recent refusal. `null` if none. */
    @Volatile
    var lastRejection: String? = null
        private set

    /**
     * The token of the current attempt, or `null` before the first `start()`.
     * Engine callbacks must present this exact token to be applied.
     */
    val activeSession: SessionToken? get() = synchronized(lock) { activeToken }

    // ---------------------------------------------------------------- commands

    /**
     * Requests a connection. Returns synchronously; the resulting state is
     * reported only via [state], never inferred from this return value.
     */
    fun start(): VpnCommandResult = synchronized(lock) {
        when (_state.value) {
            // A live or in-flight session: never layer a second attempt over it.
            is VpnState.Preparing, is VpnState.Starting,
            is VpnState.Running, is VpnState.Stopping,
            -> VpnCommandResult.RejectedBusy

            is VpnState.Revoked -> VpnCommandResult.RejectedPermissionDenied

            // Fresh attempt from any resting state. `Error -> Preparing` is the
            // "explicit retry" edge; `Stopped -> Preparing` is a restart.
            is VpnState.Idle, is VpnState.Stopped, is VpnState.Error -> {
                val token = SessionToken(++tokenSeq)
                activeToken = token
                applyLocked(VpnState.Preparing, token)
                armStartWatchdog(token)
                VpnCommandResult.Accepted
            }
        }
    }

    /**
     * Requests teardown. Idempotent: repeated calls while [VpnState.Stopping]
     * have no additional effect and, critically, do NOT re-arm the watchdog —
     * otherwise a caller polling `stop()` could keep a stuck teardown alive
     * forever.
     */
    fun stop(): VpnCommandResult = synchronized(lock) {
        when (_state.value) {
            // Never started, or already cleanly stopped: nothing to do.
            is VpnState.Idle, is VpnState.Stopped -> VpnCommandResult.Accepted
            // Idempotent no-op: no state change, no watchdog re-arm.
            is VpnState.Stopping -> VpnCommandResult.Accepted
            // Revoked implies the OS already tore the tunnel down for us.
            is VpnState.Revoked -> VpnCommandResult.Accepted

            // Running/Preparing/Starting: announce teardown. `Starting ->
            // Stopping` is the "stop cancels an in-flight start" path, and lands
            // on one clean state rather than a hybrid.
            is VpnState.Running, is VpnState.Preparing,
            is VpnState.Starting, is VpnState.Error,
            -> {
                val token = activeToken ?: SessionToken(++tokenSeq).also { activeToken = it }
                applyLocked(VpnState.Stopping, token)
                armStopWatchdog(token)
                VpnCommandResult.Accepted
            }
        }
    }

    // ------------------------------------------------------- engine callbacks

    /** Config validated; the engine is now starting. */
    fun onPreparingComplete(token: SessionToken): Boolean = synchronized(lock) {
        applyIfCurrent(token, VpnState.Starting)
    }

    /** Tunnel is up. Disarms the start watchdog. */
    fun onRunning(token: SessionToken): Boolean = synchronized(lock) {
        applyIfCurrent(token, VpnState.Running)
    }

    /** Teardown finished cleanly. Disarms the stop watchdog. */
    fun onStopped(token: SessionToken): Boolean = synchronized(lock) {
        applyIfCurrent(token, VpnState.Stopped)
    }

    /**
     * A failure occurred. Legal from [VpnState.Preparing], [VpnState.Starting]
     * and [VpnState.Running] — `Running` is essential: a live tunnel can die
     * spontaneously, and routing that through a clean teardown would lose the
     * failure reason (the P1-T5 hardening).
     */
    fun onFailure(token: SessionToken, reason: String): Boolean = synchronized(lock) {
        applyIfCurrent(token, VpnState.Error(reason))
    }

    /** VPN permission was revoked by the system or another app. */
    fun onRevoke(): Boolean = synchronized(lock) {
        val token = activeToken ?: return false
        applyIfCurrent(token, VpnState.Revoked)
    }

    /** Permission re-granted; returns to a resting state. */
    fun onPermissionRestored(): Boolean = synchronized(lock) {
        val token = activeToken ?: SessionToken(++tokenSeq).also { activeToken = it }
        applyIfCurrent(token, VpnState.Idle)
    }

    /** Releases the watchdog coroutine. Call when the owning service is destroyed. */
    fun close() {
        synchronized(lock) {
            watchdogJob?.cancel()
            watchdogJob = null
        }
    }

    // ---------------------------------------------------------------- internals

    /**
     * Applies [next] if [token] is the active session and the edge is legal.
     *
     * Returns `false` — and changes nothing — for a stale token or an illegal
     * edge. Illegal edges are *refused*, never thrown: `ARCHITECTURE.md`
     * Section 3.1.1 says an illegal transition is a programmer error that a
     * native engine must "log and refuse", whereas the Dart mock throws
     * `StateError`. The refusal is recorded in [lastRejection] for diagnosis.
     */
    private fun applyIfCurrent(token: SessionToken, next: VpnState): Boolean {
        val current = _state.value
        if (activeToken != token) {
            lastRejection = "stale token $token (active=$activeToken), state=$current, next=$next"
            return false
        }
        if (!current.canTransitionTo(next)) {
            lastRejection = "illegal transition $current -> $next"
            return false
        }
        applyLocked(next, token)
        return true
    }

    /**
     * Performs a legal, in-session transition. The watchdog is disarmed whenever
     * the transition resolves the pending window (a running tunnel, a clean stop,
     * a terminal error, or a revocation); re-arming for the *next* pending
     * window is the caller's job.
     */
    private fun applyLocked(next: VpnState, @Suppress("UNUSED_PARAMETER") token: SessionToken) {
        _state.value = next
        if (next is VpnState.Running || next is VpnState.Stopped ||
            next is VpnState.Error || next is VpnState.Revoked
        ) {
            watchdogJob?.cancel()
            watchdogJob = null
        }
    }

    private fun armStartWatchdog(token: SessionToken) {
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            delay(watchdogTimeoutMillis)
            synchronized(lock) {
                if (activeToken != token) return@launch
                val s = _state.value
                if (s !is VpnState.Preparing && s !is VpnState.Starting) return@launch
                lastWatchdogMessage =
                    "Watchdog timeout after ${watchdogTimeoutMillis}ms (start) from $s"
                applyLocked(VpnState.Error(startWatchdogReasonFor(watchdogTimeoutMillis)), token)
            }
        }
    }

    private fun armStopWatchdog(token: SessionToken) {
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            delay(watchdogTimeoutMillis)
            synchronized(lock) {
                if (activeToken != token) return@launch
                if (_state.value !is VpnState.Stopping) return@launch
                lastWatchdogMessage =
                    "Watchdog timeout after ${watchdogTimeoutMillis}ms (stop); forced to Stopped"
                // Forced to Stopped, NOT Error: see the class KDoc. `Stopping ->
                // Error` is illegal, and the watchdog exists precisely to reach
                // a legal resting state.
                applyLocked(VpnState.Stopped, token)
            }
        }
    }

    companion object {
        /** `ARCHITECTURE.md` Section 3.5: hard 5000 ms stop watchdog. */
        const val DEFAULT_WATCHDOG_TIMEOUT_MILLIS: Long = 5_000L

        /**
         * The start-watchdog reason, parameterised by the configured timeout so a
         * test that shortens the window still gets an accurate message.
         */
        fun startWatchdogReasonFor(watchdogTimeoutMillis: Long): String =
            "Watchdog timeout after ${watchdogTimeoutMillis}ms"
    }
}
