package dev.brickvpn.harness.vpn

import android.content.Intent
import android.net.VpnService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlinx.coroutines.runBlocking
import java.util.concurrent.CopyOnWriteArrayList

/**
 * P3-T13 Part A instrumented tests — these run on the REAL connected device
 * and prove that `BrickVpnService` publishes REAL [VpnCommandResult] verdicts
 * through [CommandVerdictHub] and real lifecycle events through
 * [ServiceLifecycleHub].
 *
 * Intent delivery is asynchronous: every assertion here waits (polls with a
 * timeout) for the hub to record the expected event BEFORE asserting — never
 * asserting right after `startService()`.
 *
 * VpnService requires user consent before `Builder.establish()` returns a
 * descriptor. Consent is granted out-of-band for automation with:
 *   adb shell appops set dev.brickvpn.native.harness ACTIVATE_VPN allow
 */
@RunWith(AndroidJUnit4::class)
class BrickVpnServiceVerdictTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private val verdicts = CopyOnWriteArrayList<Pair<CommandKind, VpnCommandResult>>()
    private val lifecycle = CopyOnWriteArrayList<String>()

    @Volatile
    private var started = false

    private fun startService() {
        context.startForegroundService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_START),
        )
        started = true
    }

    private fun sendActionStop() {
        // Deliberately startService(), NOT startForegroundService() — same
        // rationale as [BrickVpnServiceTest]: a stop must not re-promote the
        // service to the foreground.
        context.startService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_STOP),
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

    /** Polls until the hub recorded [kind]/[result] — async intents, never assert immediately. */
    private fun awaitVerdict(kind: CommandKind, result: VpnCommandResult, label: String) {
        val deadline = System.currentTimeMillis() + 15_000
        while (System.currentTimeMillis() < deadline) {
            if (verdicts.contains(kind to result)) return
            Thread.sleep(50)
        }
        throw AssertionError(
            "timed out waiting for verdict $label; recorded=${verdicts.joinToString()}",
        )
    }

    /** Polls until the lifecycle record is EXACTLY [expected] (order and counts). */
    private fun awaitLifecycle(expected: List<String>, label: String) {
        val deadline = System.currentTimeMillis() + 15_000
        while (System.currentTimeMillis() < deadline) {
            if (lifecycle.toList() == expected) return
            Thread.sleep(50)
        }
        throw AssertionError(
            "timed out waiting for $label; recorded=${lifecycle.joinToString()}",
        )
    }

    private fun stopLeftoverService() {
        val previous = BrickVpnService.current ?: return
        runCatching {
            context.startService(
                Intent(context, BrickVpnService::class.java)
                    .setAction(BrickVpnService.ACTION_STOP),
            )
        }
        runCatching {
            context.stopService(Intent(context, BrickVpnService::class.java))
        }
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            if (BrickVpnService.current == null) break
            Thread.sleep(25)
        }
        if (BrickVpnService.current === previous) {
            throw AssertionError(
                "previous BrickVpnService (state=" +
                    "${previous.stateMachine.currentState}) did not shut down",
            )
        }
        started = false
    }

    @Before
    fun setUp() {
        VpnService.prepare(context)
        // Stop any leftover BEFORE installing the hooks, so stale events can
        // never land in the fresh lists.
        stopLeftoverService()
        // onDestroy() fires ServiceLifecycleHub.destroyed() as its last
        // statement; give a just-observed shutdown time to finish before the
        // reset below, so a stray late event cannot poison the test.
        Thread.sleep(500)

        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        verdicts.clear()
        lifecycle.clear()

        // Hooks are installed BEFORE the intent, as the seam contract requires.
        CommandVerdictHub.listener = { kind, result -> verdicts += kind to result }
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                lifecycle += "created"
            }

            override fun onDestroyed() {
                lifecycle += "destroyed"
            }
        }
    }

    @After
    fun tearDown() {
        BrickVpnService.engineFactoryForTests = null
        if (started) {
            runCatching { sendActionStop() }
            Thread.sleep(1_500)
        }
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        verdicts.clear()
        lifecycle.clear()
        started = false
    }

    /** First start: the service publishes START / Accepted (real verdict, not inferred). */
    @Test
    fun firstStartPublishesStartAccepted() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        awaitVerdict(CommandKind.START, VpnCommandResult.Accepted, "first start -> Accepted")

        assertEquals(listOf(CommandKind.START to VpnCommandResult.Accepted), verdicts.toList())
    }

    /** A second start while Running: the machine rejects busy and the verdict is published. */
    @Test
    fun secondStartWhileRunningPublishesStartRejectedBusy() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        // Second intent while still Running.
        startService()
        awaitVerdict(CommandKind.START, VpnCommandResult.RejectedBusy, "second start -> RejectedBusy")

        assertEquals(
            listOf(
                CommandKind.START to VpnCommandResult.Accepted,
                CommandKind.START to VpnCommandResult.RejectedBusy,
            ),
            verdicts.toList(),
        )
    }

    /** Stop: the machine accepts teardown and the STOP verdict is published. */
    @Test
    fun stopPublishesStopAccepted() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        sendActionStop()
        awaitVerdict(CommandKind.STOP, VpnCommandResult.Accepted, "stop -> Accepted")

        assertEquals(
            listOf(
                CommandKind.START to VpnCommandResult.Accepted,
                CommandKind.STOP to VpnCommandResult.Accepted,
            ),
            verdicts.toList(),
        )
    }

    /** One full cycle: the lifecycle hub sees exactly one created + one destroyed. */
    @Test
    fun lifecycleDeliversOneCreatedAndOneDestroyedPerCycle() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")
        awaitLifecycle(listOf("created"), "one created after start")

        sendActionStop()
        awaitState(svc, { it is VpnState.Stopped }, "Stopped")
        awaitLifecycle(listOf("created", "destroyed"), "one created + one destroyed after stop")

        assertEquals(listOf("created", "destroyed"), lifecycle.toList())
        assertTrue("verdicts must also be present", verdicts.isNotEmpty())
    }

    /**
     * D2: ACTION_STOP sent while the service is in Error state publishes STOP / Accepted
     * and transitions to Stopped.
     */
    @Test
    fun stopWhileInErrorStatePublishesStopAcceptedAndReachesStopped() {
        BrickVpnService.engineFactoryForTests = {
            FakeTunnelEngine(failWith = IllegalStateException("forced engine failure for test"))
        }
        try {
            startService()
            val svc = awaitService()
            awaitState(svc, { it is VpnState.Error }, "Error")

            sendActionStop()
            awaitVerdict(CommandKind.STOP, VpnCommandResult.Accepted, "stop while Error -> Accepted")
            awaitState(svc, { it is VpnState.Stopped }, "Stopped")
        } finally {
            BrickVpnService.engineFactoryForTests = null
        }
    }

    /**
     * D2: ACTION_STOP sent when in Stopped publishes STOP / Accepted without crashing,
     * and PigeonVpnApiImpl.stop() in that state returns REJECTED_BUSY without sending an intent.
     */
    @Test
    fun stopWhileInStoppedStatePublishesAcceptedAndPigeonRejectsBusy() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        sendActionStop()
        awaitVerdict(CommandKind.STOP, VpnCommandResult.Accepted, "first stop -> Accepted")
        awaitState(svc, { it is VpnState.Stopped }, "Stopped")

        verdicts.clear()

        // Direct ACTION_STOP intent while in Stopped state publishes Accepted.
        sendActionStop()
        awaitVerdict(CommandKind.STOP, VpnCommandResult.Accepted, "second stop while Stopped -> Accepted")

        // PigeonVpnApiImpl.stop() pre-checks native state and rejects with REJECTED_BUSY.
        verdicts.clear()
        val coordinator = CommandCoordinator(
            setListener = { CommandVerdictHub.listener = it },
        )
        val api = PigeonVpnApiImpl(
            appContext = context,
            coordinator = coordinator,
        )

        val outcome = runBlocking { api.stop() }
        assertEquals(VpnCommandOutcome.REJECTED_BUSY, outcome)
        assertTrue("PigeonVpnApiImpl.stop() must not send an intent while in Stopped", verdicts.isEmpty())
    }
}
