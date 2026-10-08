package dev.brickvpn.harness.vpn

import android.util.Log
import io.nekohasekai.libbox.libbox.BoxService
import io.nekohasekai.libbox.libbox.Libbox
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The real [TunnelEngine]: actually starts and stops a libbox instance.
 *
 * Replaces P3-T6's [FakeTunnelEngine], which only slept. `Running` now means
 * "libbox accepted the config and started", not "a timer elapsed".
 *
 * ## What "real" means here, precisely
 *
 * [start] calls `Libbox.newService(config, platformInterface)` to build a Go
 * `BoxService` and then `BoxService.start()`. [stop] calls `BoxService.close()`.
 * Between them, libbox is a live Go runtime holding the borrowed TUN descriptor
 * and reading packets from it. With the Gate A config those packets are
 * discarded by a `block` outbound: libbox genuinely runs, and nothing is
 * routed to a real server.
 *
 * ## AC1 is NOT satisfied by this class
 *
 * `ROADMAP.md` P3-T7 AC1 requires a verified change in the device's effective
 * outbound IP. A `block` outbound cannot produce that -- it discards traffic.
 * AC1 therefore remains **OUTSTANDING**, blocked on a human-provided test
 * server. This class is the non-traffic half of P3-T7 only.
 *
 * ## Threading
 *
 * Every libbox call is wrapped in `withContext(Dispatchers.IO)`, satisfying AC3
 * ("no libbox call blocks the main thread"). `BrickVpnService` already invokes
 * [start]/[stop] from its own IO scope; the explicit dispatcher here means the
 * guarantee holds even if a future caller does not.
 *
 * ## Error propagation
 *
 * Nothing is swallowed. A libbox failure propagates as a thrown exception,
 * which `BrickVpnService.runStartSequence` turns into
 * `VpnStateMachine.onFailure(...)` with a specific reason -- the ROADMAP's
 * "Notes for Agent" rule against silently swallowing libbox errors.
 *
 * @param configJsonProvider supplies the sing-box config. A provider rather
 *   than a constant so a test can inject a deliberately invalid config and
 *   prove the failure path reaches `Error`.
 */
class LibboxTunnelEngine(
    private val configJsonProvider: () -> String = { GATE_A_CONFIG_JSON },
    /**
     * Excludes libbox's outbound sockets from the app's own TUN.
     *
     * Threaded straight through to [LibboxPlatformInterface]. Must be wired
     * whenever the TUN captures a broad route (e.g. `0.0.0.0/0`), otherwise
     * libbox's connection to the proxy server is routed back into its own TUN.
     * Defaults to a no-op so unit tests that never dial are unaffected.
     */
    private val socketProtector: (Int) -> Unit = {},
) : TunnelEngine {

    private val tag = "LibboxTunnelEngine"

    /**
     * The live libbox service, or `null` when not running.
     *
     * Cleared **before** `close()` is called, so a concurrent or re-entrant
     * [stop] is a no-op rather than a double close.
     */
    @Volatile
    private var service: BoxService? = null

    /**
     * The descriptor currently lent to libbox, or `null` when none.
     *
     * Invalidated before teardown so a late `openTun` callback throws instead
     * of returning a descriptor whose `ParcelFileDescriptor` is about to be
     * closed. That is the fd-lifetime half of the Domain 2 ownership rule.
     */
    @Volatile
    private var lentFd: Int? = null

    /**
     * Strong reference to the platform interface while libbox is running.
     *
     * gomobile proxies hold a Go-side reference back into this object; if the
     * JVM side let it be collected mid-session the next callback would fail
     * against a dangling proxy. Held in a field, and cleared together with
     * [service], for that reason alone.
     */
    @Volatile
    private var platformInterface: LibboxPlatformInterface? = null

    /** True between a successful [start] and the matching [stop]. */
    private val running = AtomicBoolean(false)

    /**
     * Creates a libbox `BoxService` and starts it.
     *
     * @param tunFd a **borrowed** descriptor owned by `BrickVpnService`. This
     *   class never closes it; the service closes it exactly once.
     * @throws Exception propagated from libbox, so the caller can map it to a
     *   specific `VpnState.Error` reason.
     */
    override suspend fun start(tunFd: Int) {
        check(service == null) { "start() called while a libbox service is already running" }
        lentFd = tunFd
        val pi = LibboxPlatformInterface({ currentLentFd() }, socketProtector)
        platformInterface = pi
        val config = configJsonProvider()
        try {
            val created = withContext(Dispatchers.IO) { Libbox.newService(config, pi) }
            service = created
            withContext(Dispatchers.IO) { created.start() }
            running.set(true)
            Log.i(tag, "libbox service started; needWIFIState=${created.needWIFIState()}")
        } catch (t: Throwable) {
            // Never leave a half-built service behind: unwind exactly what was
            // created, then rethrow so the failure reaches the state machine.
            runCatching { service?.close() }
                .onFailure { Log.w(tag, "cleanup after failed start failed: ${it.message}") }
            service = null
            platformInterface = null
            lentFd = null
            Log.e(tag, "libbox start failed: ${t.javaClass.simpleName}: ${t.message}")
            throw t
        }
    }

    /**
     * Tears the real libbox instance down.
     *
     * Idempotent and safe after a failed [start]: both are required by the
     * [TunnelEngine] contract, and both are exercised because the
     * `ACTION_STOP`, `onRevoke`, and `onDestroy` paths can race each other in
     * practice -- a double close must be harmless, not a crash.
     */
    override suspend fun stop() {
        val toClose = service
        // Clear Kotlin-side state FIRST, so a racing second stop() sees null
        // and does not double-close, and so openTun() stops handing out the
        // descriptor before its ParcelFileDescriptor is closed.
        service = null
        platformInterface = null
        lentFd = null
        if (toClose == null) {
            Log.i(tag, "stop(): no libbox service to close (already stopped)")
            return
        }
        withContext(Dispatchers.IO) { toClose.close() }
        running.set(false)
        Log.i(tag, "libbox service closed")
    }

    /**
     * The descriptor libbox may borrow, or a thrown error if none is lent.
     *
     * Throwing rather than returning `-1` matters: libbox would treat `-1` as
     * a real (invalid) descriptor and fail far away from the actual cause.
     */
    private fun currentLentFd(): Int = lentFd
        ?: error("libbox asked for a TUN descriptor but none is currently lent")

    /** Whether a libbox service is currently started. Exposed for tests. */
    fun isRunning(): Boolean = running.get()

    companion object {
        /**
         * The Gate A lifecycle-test config: a TUN inbound and a **`block`**
         * outbound, nothing else.
         *
         * `block` is a first-class sing-box outbound that discards everything
         * routed to it. It exists so libbox can be started and exercised with
         * **no remote server and no real traffic**, which is what makes this
         * task independent of external infrastructure.
         *
         * Deliberate omissions, each tied to a legacy failure this project must
         * not inherit:
         *  - **no `dns` block** -- the legacy project wedged startup on DNS
         *    bootstrap. With no DNS rules there is nothing to resolve. (AC5:
         *    v1.10.7's `PlatformInterface` exposes no DNS callback at all, so
         *    the legacy `Semaphore`/thread-pool bug class is structurally
         *    absent from this version rather than merely avoided.)
         *  - **no `route`, `rule_set`, `geoip`, or `geosite`** -- these are
         *    what the legacy project blocked forever on
         *    `raw.githubusercontent.com`. Absent here, so startup cannot block
         *    on a download. (AC6)
         *  - **no remote outbound** -- so no server, port, UUID, or password
         *    exists anywhere in this config, and there is no credential for
         *    `SECURITY.md` to protect at this stage.
         *
         * The TUN address matches `BrickVpnService`'s restricted test subnet
         * (`10.111.222.0/24`) so both sides agree which interface exists.
         */
        const val GATE_A_CONFIG_JSON: String = """
        {
          "log": { "level": "info", "timestamp": false },
          "inbounds": [
            {
              "type": "tun",
              "tag": "tun-in",
              "address": [ "10.111.222.1/24" ],
              "mtu": 9000
            }
          ],
          "outbounds": [
            { "type": "block", "tag": "block-out" }
          ],
          "route": {
            "auto_detect_interface": true
          }
        }
        """
    }
}
