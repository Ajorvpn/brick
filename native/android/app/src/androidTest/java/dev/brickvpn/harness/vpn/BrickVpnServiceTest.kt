package dev.brickvpn.harness.vpn

import android.content.Intent
import android.net.VpnService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * P3-T6 instrumented tests — these run on the REAL connected device
 * (`connectedAndroidTest`), as required by ROADMAP AC-6/AC-7.
 *
 * They prove the Android lifecycle layer only. **No libbox is involved**; the
 * engine is [FakeTunnelEngine], per the P3-T6/P3-T7 separation.
 *
 * VpnService requires user consent before `Builder.establish()` returns a
 * descriptor. Consent is granted out-of-band for automation with:
 *   adb shell appops set dev.brickvpn.native.harness ACTIVATE_VPN allow
 */
@RunWith(AndroidJUnit4::class)
class BrickVpnServiceTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private var started = false

    private fun startService() {
        context.startForegroundService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_START)
        )
        started = true
    }

    private fun sendActionStop() {
        // Deliberately startService(), NOT startForegroundService(): a stop
        // command must not re-promote the service to the foreground, and the
        // FGS contract would then require a startForeground() call for a
        // teardown. The service is already foreground if it was running.
        context.startService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_STOP)
        )
    }

    /** Polls until [predicate] holds or the timeout expires. */
    private fun awaitState(
        svc: BrickVpnService,
        predicate: (VpnState) -> Boolean,
        label: String,
        timeoutMs: Long = 15_000,
    ): VpnState {
        val deadline = System.currentTimeMillis() + timeoutMs
        var last: VpnState = svc.stateMachine.currentState
        while (System.currentTimeMillis() < deadline) {
            last = svc.stateMachine.currentState
            if (predicate(last)) return last
            Thread.sleep(50)
        }
        throw AssertionError("timed out waiting for $label; last state was $last")
    }

    private fun awaitService(): BrickVpnService {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            BrickVpnService.current?.let { return it }
            Thread.sleep(50)
        }
        throw AssertionError("service was never created")
    }

    @Before
    fun setUp() {
        VpnService.prepare(context)
    }

    @After
    fun tearDown() {
        if (started) {
            runCatching { sendActionStop() }
            Thread.sleep(1_500)
        }
    }

    /** AC-6a: the service starts and reaches `Running` (fake engine). */
    @Test
    fun serviceStartsAndReachesRunning() {
        startService()
        val svc = awaitService()
        val reached = awaitState(svc, { it is VpnState.Running }, "Running")
        assertTrue("expected Running, got $reached", reached is VpnState.Running)
    }

    /** AC-6b: explicit ACTION_STOP cleanly stops it. */
    @Test
    fun actionStopStopsCleanly() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        sendActionStop()

        val stopped = awaitState(svc, { it is VpnState.Stopped }, "Stopped")
        assertTrue("expected Stopped, got $stopped", stopped is VpnState.Stopped)
    }

    /**
     * AC-2 / AC-6c: `onRevoke()` drives the dedicated `Revoked` transition, not a
     * parallel teardown path.
     */
    @Test
    fun onRevokeDrivesRevokedTransition() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        // Invoking the callback the way the platform does; the service must route
        // it through the state machine rather than tearing down in parallel.
        InstrumentationRegistry.getInstrumentation().runOnMainSync { svc.onRevoke() }

        val revoked = awaitState(svc, { it is VpnState.Revoked }, "Revoked")
        assertTrue("expected Revoked, got $revoked", revoked is VpnState.Revoked)
    }

    /**
     * AC-4 / AC-6d: no `ParcelFileDescriptor` leak.
     *
     * Counts this process's open descriptors before and after repeated full
     * start/stop cycles. A leaked TUN descriptor would add one per cycle.
     */
    @Test
    fun noDescriptorLeakAcrossStartStop() {
        // Warm up once so one-time allocations do not pollute the baseline.
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")
        stopAndAwait(svc)
        Thread.sleep(1_000)

        val baseline = countOpenFds()
        assertTrue("baseline fd count should be > 0", baseline > 0)

        repeat(3) {
            startService()
            val s = awaitService()
            awaitState(s, { it is VpnState.Running }, "Running")
            stopAndAwait(s)
            Thread.sleep(500)
        }

        val after = countOpenFds()
        // Small slack for unrelated runtime bookkeeping; a real leak is 1 per cycle.
        assertTrue(
            "fd leak: baseline=$baseline after=$after (delta=${after - baseline})",
            after - baseline <= 2,
        )
    }

    private fun stopAndAwait(svc: BrickVpnService) {
        sendActionStop()
        awaitState(svc, { it is VpnState.Stopped }, "Stopped")
    }

    /** Counts entries in this process's `/proc/self/fd`. */
    private fun countOpenFds(): Int = File("/proc/self/fd").list()?.size ?: -1
}

