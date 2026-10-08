package dev.brickvpn.harness.vpn

import kotlinx.coroutines.delay

/**
 * The abstract "engine" seam between the Android service and whatever actually
 * moves packets.
 *
 * P3-T6 (this task) implements it with [FakeTunnelEngine] only. The real libbox
 * engine is P3-T7's job, per `ROADMAP.md` — this interface exists so the Android
 * lifecycle layer can be proven in isolation from libbox, which is exactly the
 * separation the P3-T6 Notes for Agent require.
 *
 * Contract for any future implementation:
 *  - [start] is suspending and is **never** called on the main thread.
 *  - [start] receives a *borrowed* raw file descriptor. It must NOT take
 *    ownership and must NOT call `detachFd()`; the `ParcelFileDescriptor` stays
 *    owned by [BrickVpnService] and is closed there, exactly once.
 */
interface TunnelEngine {

    /**
     * Bring the tunnel up on [tunFd], returning normally when it is usable.
     * Throwing signals failure, which the service maps to a state-machine
     * `onFailure` (never a silent swallow).
     */
    suspend fun start(tunFd: Int)

    /** Tear the tunnel down. Must be idempotent and safe after a failed [start]. */
    suspend fun stop()
}

/**
 * A deliberately fake engine: it simulates a connection by sleeping a fixed
 * delay, and touches no network, no native library, and no user data.
 *
 * It exists so the Android framework integration (foreground service, TUN
 * establishment, `ACTION_STOP`, `onRevoke`, descriptor lifecycle) can be proven
 * end-to-end on a real device without a libbox integration bug being able to
 * masquerade as a lifecycle bug.
 *
 * @param connectDelayMillis simulated time to reach "connected". Small enough to
 *   keep instrumented tests fast, large enough that a test can observe the
 *   intermediate `Preparing`/`Starting` states.
 * @param failWith if non-null, [start] throws this instead of connecting. Used by
 *   tests to exercise the failure path.
 */
class FakeTunnelEngine(
    private val connectDelayMillis: Long = DEFAULT_CONNECT_DELAY_MILLIS,
    private val failWith: Throwable? = null,
) : TunnelEngine {

    override suspend fun start(tunFd: Int) {
        delay(connectDelayMillis)
        failWith?.let { throw it }
    }

    override suspend fun stop() {
        // Nothing to do: there is nothing real to tear down.
    }

    companion object {
        const val DEFAULT_CONNECT_DELAY_MILLIS: Long = 250L
    }
}
