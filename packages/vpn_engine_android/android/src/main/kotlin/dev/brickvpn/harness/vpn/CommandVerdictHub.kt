package dev.brickvpn.harness.vpn

import android.util.Log

/**
 * Which command produced a [VpnCommandResult] verdict.
 *
 * P3-T13 Part A: the two service entry points that call into
 * [VpnStateMachine.start] / [VpnStateMachine.stop].
 */
enum class CommandKind {
    START,
    STOP,
}

/**
 * P3-T13 Part A seam: publishes every start/stop command verdict exactly as the
 * state machine returned it, so an observer (Part B's Pigeon bridge) can see
 * REAL [VpnCommandResult]s instead of inferring them.
 *
 * - [publish] is called by `BrickVpnService` immediately after obtaining a
 *   verdict, before the verdict is acted on. Every verdict is published,
 *   including ones produced without a Pigeon caller (e.g. `ACTION_STOP`
 *   arriving as a plain intent).
 * - [publish] NEVER throws: a throwing [listener] is caught and routed to
 *   [errorLogger] (default: `android.util.Log.w`), and a throwing [errorLogger]
 *   is itself caught — a seam must not be able to take the service down.
 * - Exactly one [listener] at a time; adding a listener later does not replay
 *   missed events. [reset] clears both hooks (tests call it in `@After`).
 *
 * Pure-Kotlin surface: no `Context`, no Android type in any signature; the
 * only framework touch is the default [errorLogger] fallback, which JVM tests
 * bypass by overriding [errorLogger].
 */
object CommandVerdictHub {

    private const val TAG = "CommandVerdictHub"

    /** Sink for verdicts. Exactly one; `null` (the default) records nothing. */
    @Volatile
    @JvmStatic
    var listener: ((CommandKind, VpnCommandResult) -> Unit)? = null

    /**
     * Failure sink for a throwing [listener]. `null` (the default) falls back
     * to `Log.w`. Overridden by JVM tests so no `android.*` class is touched
     * on the host.
     */
    @Volatile
    @JvmStatic
    var errorLogger: ((String, Throwable) -> Unit)? = null

    /**
     * Publishes one verdict. Synchronous, in call order; never throws and
     * never affects the caller's control flow.
     */
    @JvmStatic
    fun publish(kind: CommandKind, result: VpnCommandResult) {
        try {
            listener?.invoke(kind, result)
        } catch (t: Throwable) {
            try {
                val logger = errorLogger
                if (logger != null) {
                    logger("listener threw for $kind=$result", t)
                } else {
                    Log.w(TAG, "listener threw for $kind=$result", t)
                }
            } catch (_: Throwable) {
                // Deliberately final: publish() is documented never to throw,
                // so even a failing errorLogger must not escape. This is the
                // one place in the seam where swallowing is the contract.
            }
        }
    }

    /** Clears [listener] and [errorLogger]. */
    @JvmStatic
    fun reset() {
        listener = null
        errorLogger = null
    }
}
