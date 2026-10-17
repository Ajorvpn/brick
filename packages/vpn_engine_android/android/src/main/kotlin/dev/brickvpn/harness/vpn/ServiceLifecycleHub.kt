package dev.brickvpn.harness.vpn

import android.util.Log

/**
 * P3-T13 Part A seam: informed whenever `BrickVpnService` is created or
 * destroyed, carrying the live [VpnStateMachine] so Part B's Pigeon bridge can
 * attach to the real machine (state flow, session) without polling or
 * re-creating one.
 *
 * Exactly one observer at a time. Events fired while [observer] is `null` are
 * dropped — a later observer does not replay missed events.
 */
interface ServiceLifecycleObserver {

    /** The service finished `onCreate`; [machine] is its live state machine. */
    fun onCreated(machine: VpnStateMachine)

    /** The service entered `onDestroy`. */
    fun onDestroyed()
}

/**
 * Registry for the single [ServiceLifecycleObserver].
 *
 * - [created] / [destroyed] are called by `BrickVpnService` as the LAST
 *   statement of `onCreate` / `onDestroy`, after the service's own state is
 *   consistent.
 * - Both calls NEVER throw: a throwing observer is caught and routed to
 *   [errorLogger] (default: `android.util.Log.w`), and a throwing
 *   [errorLogger] is itself caught — a seam must not be able to take the
 *   service down.
 * - [reset] clears both hooks (tests call it in `@After`).
 */
object ServiceLifecycleHub {

    private const val TAG = "ServiceLifecycleHub"

    /** Sink for lifecycle events. Exactly one; `null` (the default) drops all. */
    @Volatile
    @JvmStatic
    var observer: ServiceLifecycleObserver? = null

    /**
     * Failure sink for a throwing [observer]. `null` (the default) falls back
     * to `Log.w`. Overridden by JVM tests so no `android.*` class is touched
     * on the host.
     */
    @Volatile
    @JvmStatic
    var errorLogger: ((String, Throwable) -> Unit)? = null

    /** Publishes a creation event. Synchronous; never throws. */
    @JvmStatic
    fun created(machine: VpnStateMachine) {
        try {
            observer?.onCreated(machine)
        } catch (t: Throwable) {
            report("onCreated", t)
        }
    }

    /** Publishes a destruction event. Synchronous; never throws. */
    @JvmStatic
    fun destroyed() {
        try {
            observer?.onDestroyed()
        } catch (t: Throwable) {
            report("onDestroyed", t)
        }
    }

    /** Clears [observer] and [errorLogger]. */
    @JvmStatic
    fun reset() {
        observer = null
        errorLogger = null
    }

    private fun report(where: String, t: Throwable) {
        try {
            val logger = errorLogger
            if (logger != null) {
                logger("$where threw", t)
            } else {
                Log.w(TAG, "$where threw", t)
            }
        } catch (_: Throwable) {
            // Deliberately final: created()/destroyed() are documented never to
            // throw, so even a failing errorLogger must not escape. This is the
            // one place in the seam where swallowing is the contract.
        }
    }
}
