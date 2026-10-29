// SPDX-License-Identifier: GPL-3.0-or-later

package dev.brickvpn.harness.vpn

import android.content.Intent
import android.net.VpnService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * P3-T13 Part A — investigation of the STOP verdict seam in
 * [BrickVpnService.requestStop].
 *
 * ## What was suspected
 *
 * `requestStop` obtains and publishes the STOP verdict *inside*
 * `ioScope.launch { ... }`, while `stopSelf()` runs on the very next line on the
 * caller's thread. `onDestroy()` later calls `ioScope.cancel()`, which drops a
 * coroutine that has been dispatched but has not started yet. Two contract
 * violations therefore seemed reachable:
 *
 *  - `CommandVerdictHub`'s *"publish is called ... immediately after obtaining a
 *    verdict, before the verdict is acted on"* — teardown starts before the
 *    verdict even exists.
 *  - *"Every verdict is published"* — `ioScope.cancel()` can erase the coroutine
 *    before it runs, so the STOP verdict is lost outright.
 *
 * ## Why this class contains no failing reproduction
 *
 * Two instrumented runs were made on SM-A205F to make the race deterministic by
 * parking 192 blocking tasks on the process-wide `Dispatchers.IO` (the
 * instrumentation runs in the same process as the service), which caps it at
 * `max(64, cores)` workers:
 *
 *  - **Unsaturated:** the verdict coroutine runs ~4 ms after
 *    `onStartCommand(ACTION_STOP)`, whereas `onDestroy` arrives ~138 ms after
 *    it. The publish wins by two orders of magnitude every time.
 *  - **Saturated:** the queued coroutine and the service's destruction are
 *    gated behind the *same* parked pool, so the pool release unlocks both —
 *    `state -> Stopping` (i.e. `stateMachine.stop()`, immediately followed by
 *    the publish) was logged at 20:05:41.264 and `onDestroy` followed at
 *    20:05:41.300, ~36 ms later. The coroutine still wins.
 *  - The saturated run never even reached its verdict assertion: it timed out
 *    after 20 s waiting for `destroyed`, because destruction itself stalls until
 *    the pool drains — which is precisely why the ordering cannot be inverted.
 *
 * The verdict-loss ordering could not be reproduced. Per the agreed rule the
 * seam was left **unchanged**, and this class keeps only the observable,
 * requested behaviour: a full stop cycle publishes **exactly one** STOP verdict.
 *
 * ## Documented decision: `onDestroy` never publishes
 *
 * `onDestroy` calls `stateMachine.stop()` purely as internal cleanup of a
 * teardown the service performs on its own — that is not a command. Publishing
 * it would inject a second STOP verdict capable of completing a later pending
 * stop with the wrong answer.
 */
@RunWith(AndroidJUnit4::class)
class BrickVpnServiceVerdictRaceTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private val verdicts = CopyOnWriteArrayList<Pair<CommandKind, VpnCommandResult>>()
    private val lifecycle = CopyOnWriteArrayList<String>()

    private fun startService() {
        context.startForegroundService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_START),
        )
    }
    private fun sendActionStop() {
        // Deliberately startService(), NOT startForegroundService(), matching the
        // rest of the Gate A suites: a stop must not re-promote the service.
        context.startService(
            Intent(context, BrickVpnService::class.java)
                .setAction(BrickVpnService.ACTION_STOP),
        )
    }

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

    private fun awaitLifecycle(expected: List<String>, label: String) {
        val deadline = System.currentTimeMillis() + 20_000
        while (System.currentTimeMillis() < deadline) {
            if (lifecycle.toList() == expected) return
            Thread.sleep(50)
        }
        throw AssertionError("timed out waiting for $label; recorded $lifecycle")
    }

    @Before
    fun setUp() {
        VpnService.prepare(context)
        runCatching {
            context.stopService(Intent(context, BrickVpnService::class.java))
        }
        Thread.sleep(500)

        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        verdicts.clear()
        lifecycle.clear()

        // Hooks installed BEFORE the intent, as the seam contract requires.
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
        runCatching {
            context.stopService(Intent(context, BrickVpnService::class.java))
        }
        Thread.sleep(1_000)
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        verdicts.clear()
        lifecycle.clear()
    }

    /**
     * A full start -> stop -> destroy cycle publishes **exactly one** STOP
     * verdict: the command seam's single STOP, and never a second one from
     * `onDestroy`'s internal `stateMachine.stop()` cleanup.
     */
    @Test
    fun fullStopCyclePublishesExactlyOneStopVerdict() {
        startService()
        val svc = awaitService()
        awaitState(svc, { it is VpnState.Running }, "Running")

        sendActionStop()
        awaitState(svc, { it is VpnState.Stopped }, "Stopped")
        awaitLifecycle(listOf("created", "destroyed"), "service destroyed after stop")
        Thread.sleep(1_500)

        assertEquals(
            "a full start/stop/destroy cycle publishes exactly one STOP verdict",
            1,
            verdicts.count { it.first == CommandKind.STOP },
        )
        assertEquals(
            listOf(
                CommandKind.START to VpnCommandResult.Accepted,
                CommandKind.STOP to VpnCommandResult.Accepted,
            ),
            verdicts.toList(),
        )
    }
}

