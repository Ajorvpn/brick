package dev.brickvpn.harness.vpn

import android.content.Intent
import android.net.VpnService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.nekohasekai.libbox.libbox.Libbox
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * P3-T7 instrumented tests — real libbox, on the REAL connected device.
 *
 * These exist because P3-T6's suite proved only that a *fake* engine could be
 * driven through the Android lifecycle. Passing P3-T6 with a real
 * [LibboxTunnelEngine] proves the lifecycle still holds; **these** tests prove
 * libbox itself actually ran and was actually torn down.
 *
 * The distinction matters: `VpnState.Running` on its own is weak evidence,
 * because a fake engine can produce it by sleeping. These assertions check
 * [LibboxTunnelEngine.isRunning] instead, which can only be true if
 * `Libbox.newService(...)` + `BoxService.start()` returned without throwing.
 *
 * **AC1 is deliberately NOT tested here.** No test in this file verifies
 * outbound traffic or a change in the device's effective IP — the Gate A
 * config's only outbound is `block`, which discards traffic. That is ROADMAP
 * P3-T7 AC1 and it remains OUTSTANDING pending a human-provided test server.
 */
@RunWith(AndroidJUnit4::class)
class LibboxEngineTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private var started = false

    @Before
    fun setUp() {
        VpnService.prepare(context)
        stopLeftoverService()
    }

    /**
     * Instrumented tests all run in **one process**, and a `VpnService` is a
     * process singleton: `startService()` on a still-running instance delivers
     * to that instance rather than creating a new one.
     *
     * Without this, a test that leaves the service alive lets the next test
     * inherit its state. That is not hypothetical -- it produced real failures:
     * `onRevokeTearsDownTheRealLibboxInstance` leaves the machine in `Revoked`,
     * and because `Revoked -> Preparing` is illegal, the *next* test's
     * `start()` correctly returns `RejectedPermissionDenied` and `Running`
     * becomes unreachable ("timed out waiting for Running; last state was
     * Revoked"). The service was behaving correctly; the suite was not
     * independent.
     *
     * Each test therefore begins from a clean slate. This is isolation, not
     * relaxation: no assertion in this file was weakened.
     */
    private fun stopLeftoverService() {
        val previous = BrickVpnService.current ?: return
        // 1. Ask the previous session to tear down cleanly, so libbox closes
        //    through its normal path instead of being killed mid-flight.
        runCatching {
            context.startService(
                Intent(context, BrickVpnService::class.java)
                    .setAction(BrickVpnService.ACTION_STOP),
            )
        }
        // 2. Then force the component down. A `VpnService` is a process
        //    singleton: if the old instance survives, the next test's
        //    startService() is delivered to it and it inherits the previous
        //    test's state. That is exactly what produced
        //    "timed out waiting for Running; last state was Revoked" -- the
        //    machine had been left in `Revoked`, and `Revoked -> Preparing` is
        //    illegal by design, so `start()` correctly refuses. Forcing the
        //    component down means the next test gets a fresh instance and a
        //    fresh `Idle` machine.
        runCatching {
            context.stopService(Intent(context, BrickVpnService::class.java))
        }
        // onDestroy() clears `current`; wait for that rather than guessing.
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            if (BrickVpnService.current == null) break
            Thread.sleep(25)
        }
        if (BrickVpnService.current === previous) {
            throw AssertionError(
                "previous BrickVpnService (state=" +
                    "${previous.stateMachine.currentState}) did not shut down; " +
                    "the next test cannot start from a clean slate",
            )
        }
        started = false
    }

    @After
    fun tearDown() {
        if (started) {
            runCatching { sendActionStop() }
            Thread.sleep(1_500)
        }
    }

    /**
     * Waits for the **real libbox instance** to report stopped.
     *
     * `onRevoke` performs its teardown on a background scope (`ioScope`), so the
     * engine flag flips asynchronously. Asserting immediately after
     * `awaitState(Revoked)` is a race: when the state was *already* `Revoked`
     * (inherited session) `awaitState` returns instantly and the assertion runs
     * before the teardown coroutine has been scheduled. Waiting for the
     * documented end state is the synchronisation equivalent of [awaitState],
     * not a weaker check -- the terminal assertion still requires `false`.
     */
    private fun awaitEngineStopped(engine: LibboxTunnelEngine, timeoutMs: Long = 5_000) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (!engine.isRunning()) return
            Thread.sleep(25)
        }
        throw AssertionError("libbox engine still reported running after ${timeoutMs}ms")
    }

    private fun startService() {
        context.startForegroundService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_START),
        )
        started = true
    }

    private fun sendActionStop() {
        // startService(), not startForegroundService(): a teardown must not
        // re-promote the service to the foreground.
        context.startService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_STOP),
        )
    }

    private fun awaitService(): BrickVpnService {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            BrickVpnService.current?.let { return it }
            Thread.sleep(50)
        }
        throw AssertionError("service was never created")
    }

    private fun awaitState(
        svc: BrickVpnService,
        predicate: (VpnState) -> Boolean,
        label: String,
        timeoutMs: Long = 20_000,
    ): VpnState {
        val deadline = System.currentTimeMillis() + timeoutMs
        var last: VpnState = svc.stateMachine.currentState
        while (System.currentTimeMillis() < deadline) {
            last = svc.stateMachine.currentState
            if (predicate(last)) return last
            Thread.sleep(50)
        }
        throw AssertionError(
            "timed out waiting for $label; last state was $last; " +
                "rejection=${svc.stateMachine.lastRejection}",
        )
    }

    /**
     * The JNI-linkage proof: [Libbox.version] is a `native` method, so calling
     * it loads `libgojni.so`. An [UnsatisfiedLinkError] here means the AAR is
     * missing, ABI-mismatched, or misaligned — and every other test here would
     * fail for that same reason with a far less obvious message.
     */
    @Test
    fun libboxNativeLibraryLoads() {
        val version = Libbox.version()
        assertNotNull("Libbox.version() returned null", version)
        assertTrue(
            "Libbox.version() returned a blank string; native lib did not load",
            version.isNotBlank(),
        )
    }

    /** The service must be bound to the REAL engine, not the P3-T6 fake. */
    @Test
    fun serviceIsBoundToTheRealLibboxEngine() {
        startService()
        val svc = awaitService()
        assertTrue(
            "expected a LibboxTunnelEngine, got ${svc.engine.javaClass.name}",
            svc.engine is LibboxTunnelEngine,
        )
    }

    /**
     * The core of P3-T7: libbox genuinely starts, and the state machine's
     * `Running` reflects that rather than a timer.
     */
    @Test
    fun realLibboxStartsAndRunningMeansLibboxIsUp() {
        startService()
        val svc = awaitService()
        val engine = svc.engine as LibboxTunnelEngine

        val reached = awaitState(svc, { it is VpnState.Running }, "Running")
        assertTrue("expected Running, got $reached", reached is VpnState.Running)

        // The state machine and the real engine must agree. If `Running` were
        // reachable without libbox actually being up, this is what catches it.
        assertTrue(
            "state machine says Running but no libbox service is live",
            engine.isRunning(),
        )
    }

    /**
     * `ACTION_STOP` must tear down the **real** libbox instance, not merely the
     * Kotlin state.
     */
    @Test
    fun actionStopTearsDownTheRealLibboxInstance() {
        startService()
        val svc = awaitService()
        val engine = svc.engine as LibboxTunnelEngine
        awaitState(svc, { it is VpnState.Running }, "Running")
        assertTrue(engine.isRunning())

        sendActionStop()

        val stopped = awaitState(svc, { it is VpnState.Stopped }, "Stopped")
        assertTrue("expected Stopped, got $stopped", stopped is VpnState.Stopped)
        // BoxService.close() must have run: isRunning() only flips false there.
        awaitEngineStopped(engine)
        assertFalse(
            "state machine says Stopped but the libbox service is still live",
            engine.isRunning(),
        )
    }

    /** `onRevoke` must likewise stop the real libbox instance. */
    @Test
    fun onRevokeTearsDownTheRealLibboxInstance() {
        startService()
        val svc = awaitService()
        val engine = svc.engine as LibboxTunnelEngine
        awaitState(svc, { it is VpnState.Running }, "Running")
        assertTrue(engine.isRunning())

        InstrumentationRegistry.getInstrumentation().runOnMainSync { svc.onRevoke() }

        val revoked = awaitState(svc, { it is VpnState.Revoked }, "Revoked")
        assertTrue("expected Revoked, got $revoked", revoked is VpnState.Revoked)
        // onRevoke() tears down on a background scope, so wait for the flag
        // rather than racing it (see awaitEngineStopped).
        awaitEngineStopped(engine)
        assertFalse(
            "state machine says Revoked but the libbox service is still live",
            engine.isRunning(),
        )
    }

    /**
     * A double stop must be harmless. `ACTION_STOP`, `onRevoke`, and
     * `onDestroy` can all fire for one session, so reaching
     * `BoxService.close()` twice must not crash the process.
     */
    @Test
    fun repeatedStopIsIdempotentAndDoesNotCrash() {
        startService()
        val svc = awaitService()
        val engine = svc.engine as LibboxTunnelEngine
        awaitState(svc, { it is VpnState.Running }, "Running")

        sendActionStop()
        awaitState(svc, { it is VpnState.Stopped }, "Stopped")

        runCatching { sendActionStop() }
        Thread.sleep(1_000)
        assertFalse("engine reported running after a second stop", engine.isRunning())
    }

    /**
     * A malformed config must be rejected loudly, never silently accepted and
     * never swallowed into a log warning (ROADMAP "Notes for Agent" and the
     * legacy swallowed-`CommandClient` lesson).
     *
     * Uses a `tunFd` of `-1` deliberately: [LibboxTunnelEngine.start] must
     * surface the *config* failure before the descriptor is ever consulted,
     * which is exactly the ordering that stops a bad config from being
     * misattributed to the TUN handoff.
     */
    @Test
    fun invalidConfigFailsLoudlyRatherThanSilently() {
        val failing = LibboxTunnelEngine { "{ not valid sing-box json" }
        // runBlocking: `start` is `suspend`, and the test is not in a coroutine.
        val threw = runCatching { runBlocking { failing.start(tunFd = -1) } }
        assertTrue(
            "libbox accepted a malformed config; a failure would be swallowed",
            threw.isFailure,
        )
        assertFalse(
            "engine claims to be running after a failed start",
            failing.isRunning(),
        )
    }

    /** A syntactically valid config pointing at a reserved, guaranteed-dead port. */
    private fun deadPeerConfig(): String = """
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
            {
              "type": "shadowsocks",
              "tag": "proxy",
              "server": "127.0.0.1",
              "server_port": 1,
              "method": "aes-128-gcm",
              "password": "0123456789abcdef"
            }
          ],
          "route": { "auto_detect_interface": true }
        }
    """.trimIndent()

    /**
     * D.1 -- clean handling of a **known-closed** peer, through the real service.
     *
     * `127.0.0.1:1` (tcpmux) is reserved and nothing listens on it, so the dial
     * is refused immediately and deterministically.
     *
     * The property under test is *not* reachability. It is that a syntactically
     * valid config pointing at a dead peer still produces an honest, complete,
     * and reversible lifecycle:
     *
     *  - the state machine reaches `Running` (libbox accepted the config; a
     *    dial failure must NOT be misreported as a start failure), and
     *  - an explicit stop then reaches `Stopped` with no leak or hang.
     *
     * This is the legacy failure mode this project must not inherit: "connected"
     * coexisting with a broken tunnel, and teardown that silently hangs.
     *
     * It must run via [BrickVpnService.engineFactoryForTests] rather than
     * `LibboxTunnelEngine.start(tunFd = -1)`: libbox configures the TUN during
     * `BoxService.start()`, so a *valid* config needs a genuine descriptor. With
     * `-1` it fails earlier with "query tun name: bad file descriptor", which
     * would assert TUN plumbing rather than what this test is for.
     */
    @Test
    fun deadPeerStillWalksTheFullLifecycleAndTearsDownCleanly() {
        val engineRef = java.util.concurrent.atomic.AtomicReference<LibboxTunnelEngine?>(null)

        BrickVpnService.engineFactoryForTests = {
            LibboxTunnelEngine({ deadPeerConfig() }) { fd ->
                // No real protect(): nothing is ever dialed successfully here.
            }.also { engineRef.set(it) }
        }
        try {
            startService()
            val svc = awaitService()

            awaitState(svc, { it is VpnState.Running }, "Running")
            val engine = engineRef.get()
            assertNotNull("test engine was never constructed", engine)
            assertTrue(
                "engine reports not-running while the service state is Running",
                engine!!.isRunning(),
            )

            sendActionStop()
            awaitState(svc, { it is VpnState.Stopped }, "Stopped")
            awaitEngineStopped(engine)
        } finally {
            BrickVpnService.engineFactoryForTests = null
        }
    }

    /**
     * B.4 -- proves `protect()` is genuinely invoked during a **real** connection
     * attempt, not merely that the method exists on the interface.
     *
     * The engine is substituted through [BrickVpnService.engineFactoryForTests] so
     * it runs inside a real service start sequence: a genuine TUN fd is lent and
     * libbox genuinely dials. `autoDetectInterfaceControl` is installed on the
     * outbound dialer only when BOTH `usePlatformAutoDetectInterfaceControl()` is
     * true AND the config sets `route.auto_detect_interface`. This test therefore
     * fails if either half of that two-part gate regresses -- exactly the bug
     * class that would silently reintroduce a routing loop on a `0.0.0.0/0`
     * route, where libbox's connection to the server is captured by its own TUN.
     *
     * The peer is the same reserved dead port, so nothing is actually relayed;
     * the assertion is purely that the socket-protection callback fired.
     */
    @Test
    fun outboundSocketProtectionIsInvokedDuringARealDial() {
        val protected = java.util.Collections.synchronizedList(mutableListOf<Int>())

        BrickVpnService.engineFactoryForTests = {
            LibboxTunnelEngine({ deadPeerConfig() }) { fd -> protected.add(fd) }
        }
        try {
            startService()
            val svc = awaitService()
            awaitState(svc, { it is VpnState.Running }, "Running")

            // libbox dials on service start; poll briefly for the control func.
            val deadline = System.currentTimeMillis() + 20_000
            while (System.currentTimeMillis() < deadline && protected.isEmpty()) {
                Thread.sleep(50)
            }

            assertTrue(
                "autoDetectInterfaceControl never fired during a real dial; either " +
                    "usePlatformAutoDetectInterfaceControl() is false or " +
                    "route.auto_detect_interface is unset, so outbound sockets are " +
                    "NOT excluded from the TUN (would loop on a 0.0.0.0/0 route)",
                protected.isNotEmpty(),
            )
            sendActionStop()
            awaitState(svc, { it is VpnState.Stopped }, "Stopped")
        } finally {
            BrickVpnService.engineFactoryForTests = null
        }
    }
}
