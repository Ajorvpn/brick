package dev.brickvpn.harness.vpn

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Host-JVM unit tests for [VpnStateMachine]. No emulator, no Robolectric, no
 * Android framework class — the whole point of the PURE KOTLIN requirement.
 *
 * The 5000 ms watchdog is exercised with `kotlinx-coroutines-test` **virtual
 * time**, so these run in milliseconds while still proving the timeout.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class VpnStateMachineTest {

    // ------------------------------------------------------------- transition graph

    /**
     * Exhaustive proof of the transition table. Every ordered pair is asserted,
     * so a newly-added state cannot silently be legal from the wrong place.
     */
    @Test
    fun `transition graph matches the normative table exactly`() {
        val expected: Map<String, Set<String>> = mapOf(
            VpnState.ID_IDLE to setOf(VpnState.ID_PREPARING, VpnState.ID_REVOKED),
            VpnState.ID_PREPARING to setOf(
                VpnState.ID_STARTING, VpnState.ID_STOPPING, VpnState.ID_ERROR, VpnState.ID_REVOKED,
            ),
            VpnState.ID_STARTING to setOf(
                VpnState.ID_RUNNING, VpnState.ID_STOPPING, VpnState.ID_ERROR, VpnState.ID_REVOKED,
            ),
            VpnState.ID_RUNNING to setOf(
                VpnState.ID_STOPPING, VpnState.ID_ERROR, VpnState.ID_REVOKED,
            ),
            VpnState.ID_STOPPING to setOf(VpnState.ID_STOPPED, VpnState.ID_REVOKED),
            VpnState.ID_STOPPED to setOf(
                VpnState.ID_PREPARING, VpnState.ID_IDLE, VpnState.ID_REVOKED,
            ),
            VpnState.ID_ERROR to setOf(
                VpnState.ID_PREPARING, VpnState.ID_STOPPING, VpnState.ID_REVOKED,
            ),
            VpnState.ID_REVOKED to setOf(VpnState.ID_IDLE),
        )

        val all = allStates()
        var checked = 0
        for (from in all) {
            for (to in all) {
                val want = to.id in expected.getValue(from.id)
                assertEquals("$from -> $to", want, from.canTransitionTo(to))
                checked++
            }
        }
        assertEquals("must check every ordered pair", 64, checked)
    }

    /** The legacy bug class: never layer a second attempt over a live tunnel. */
    @Test
    fun `Running cannot go directly back to Preparing or Starting`() {
        assertFalse(VpnState.Running.canTransitionTo(VpnState.Preparing))
        assertFalse(VpnState.Running.canTransitionTo(VpnState.Starting))
    }

    /** Teardown must converge; these are the escapes the watchdog must never need. */
    @Test
    fun `Stopping has exactly one non-revoke exit`() {
        assertTrue(VpnState.Stopping.canTransitionTo(VpnState.Stopped))
        assertFalse(VpnState.Stopping.canTransitionTo(VpnState.Error("x")))
        assertFalse(VpnState.Stopping.canTransitionTo(VpnState.Preparing))
        assertFalse(VpnState.Stopping.canTransitionTo(VpnState.Starting))
    }

    /** Nothing attempted, so no failure to report and nothing to tear down. */
    @Test
    fun `Idle cannot reach Running Error or Stopping`() {
        assertFalse(VpnState.Idle.canTransitionTo(VpnState.Running))
        assertFalse(VpnState.Idle.canTransitionTo(VpnState.Error("x")))
        assertFalse(VpnState.Idle.canTransitionTo(VpnState.Stopping))
    }

    /** Permission must be re-granted before anything else. */

    /**
     * Regression test for a JVM class-initialization-order bug found while
     * building this.
     *
     * `LEGAL` used to be `Map<VpnState, Set<VpnState>>` built in the companion
     * object. `VpnStateMachine`'s field initializer touches `VpnState.Idle`
     * first, so `VpnState$Idle.<clinit>` ran BEFORE
     * `VpnState$Companion.<clinit>`, and the companion captured the
     * still-uninitialized `Idle` and `Revoked` singletons as `null`:
     *
     * ```
     * key=null       -> [Preparing, Revoked]
     * key=Revoked    -> [null]
     * Idle.canTransitionTo(Preparing) == false     // silently wrong
     * ```
     *
     * The table is now keyed by String id, so no lookup can depend on object
     * initialization order. This test pins that by touching `Idle` (the state
     * the machine starts in) before reading the table — the exact order that
     * used to break it.
     */
    @Test
    fun `transition table is immune to class initialization order`() {
        val touched = VpnState.Idle // force VpnState$Idle.<clinit> first
        assertEquals(VpnState.ID_IDLE, touched.id)

        for ((id, targets) in VpnState.LEGAL) {
            assertTrue("table key must not be null (got $id)", id != null)
            for (t in targets) assertTrue("target must not be null (in $id)", t != null)
        }
        assertEquals(8, VpnState.LEGAL.size)
        assertTrue(VpnState.Idle.canTransitionTo(VpnState.Preparing))
        assertTrue(VpnState.Revoked.canTransitionTo(VpnState.Idle))
    }

    /** Every state must expose a distinct, non-blank id. */
    @Test
    fun `every state has a distinct non-blank id`() {
        val ids = allStates().map { it.id }
        assertEquals(8, ids.size)
        assertEquals("ids must be unique", 8, ids.toSet().size)
        assertTrue(ids.none { it.isBlank() })
    }

    // ------------------------------------------------------------- happy path

    @Test
    fun `initial state is Idle with no session`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        assertEquals(VpnState.Idle, m.currentState)
        assertNull(m.activeSession)
        m.close()
    }

    @Test
    fun `full happy path Idle Preparing Starting Running Stopping Stopped`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        assertEquals(VpnCommandResult.Accepted, m.start())
        assertEquals(VpnState.Preparing, m.currentState)

        val t = m.activeSession!!
        assertTrue(m.onPreparingComplete(t))
        assertEquals(VpnState.Starting, m.currentState)

        assertTrue(m.onRunning(t))
        assertEquals(VpnState.Running, m.currentState)

        assertEquals(VpnCommandResult.Accepted, m.stop())
        assertEquals(VpnState.Stopping, m.currentState)

        assertTrue(m.onStopped(t))
        assertEquals(VpnState.Stopped, m.currentState)
        m.close()
    }

    @Test
    fun `happy path emits the expected StateFlow sequence`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        val seen = mutableListOf(m.state.value)
        m.start()
        seen += m.state.value
        val t = m.activeSession!!
        m.onPreparingComplete(t); seen += m.state.value
        m.onRunning(t); seen += m.state.value
        m.stop(); seen += m.state.value
        m.onStopped(t); seen += m.state.value

        assertEquals(
            listOf(
                VpnState.Idle, VpnState.Preparing, VpnState.Starting,
                VpnState.Running, VpnState.Stopping, VpnState.Stopped,
            ),
            seen,
        )
        m.close()
    }

    // ------------------------------------------------------------- command results

    @Test
    fun `start while Preparing Starting Running or Stopping is RejectedBusy`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        assertEquals(VpnCommandResult.RejectedBusy, m.start())
        val t = m.activeSession!!
        m.onPreparingComplete(t)
        assertEquals(VpnCommandResult.RejectedBusy, m.start())
        m.onRunning(t)
        assertEquals(VpnCommandResult.RejectedBusy, m.start())
        m.stop()
        assertEquals(VpnCommandResult.RejectedBusy, m.start())
        m.close()
    }

    @Test
    fun `rejectedBusy does not corrupt state`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)
        val before = m.currentState
        val tokenBefore = m.activeSession

        m.start()

        assertEquals(before, m.currentState)
        assertEquals(tokenBefore, m.activeSession)
        m.close()
    }

    @Test
    fun `start while Revoked is RejectedPermissionDenied`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        m.onRevoke()
        assertEquals(VpnState.Revoked, m.currentState)
        assertEquals(VpnCommandResult.RejectedPermissionDenied, m.start())
        m.close()
    }

    @Test
    fun `stop is idempotent while Stopping`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)
        m.stop()
        assertEquals(VpnState.Stopping, m.currentState)

        repeat(5) { assertEquals(VpnCommandResult.Accepted, m.stop()) }
        assertEquals(VpnState.Stopping, m.currentState)
        m.close()
    }

    @Test
    fun `repeated stop does not keep re-arming the watchdog`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)
        m.stop()
        repeat(5) { m.stop() }

        // If stop() re-armed the watchdog, this would never converge.
        advanceTimeBy(5_001)
        runCurrent()
        assertEquals(VpnState.Stopped, m.currentState)
        m.close()
    }

    @Test
    fun `stop from Idle and Stopped is accepted and inert`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        assertEquals(VpnCommandResult.Accepted, m.stop())
        assertEquals(VpnState.Idle, m.currentState)

        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t); m.stop(); m.onStopped(t)
        assertEquals(VpnState.Stopped, m.currentState)
        assertEquals(VpnCommandResult.Accepted, m.stop())
        assertEquals(VpnState.Stopped, m.currentState)
        m.close()
    }

    @Test
    fun `stop while Starting cancels the in-flight start cleanly`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t)
        assertEquals(VpnState.Starting, m.currentState)

        assertEquals(VpnCommandResult.Accepted, m.stop())
        // One clean state, not a hybrid, and never Running.
        assertEquals(VpnState.Stopping, m.currentState)
        assertFalse(m.onRunning(t))
        assertEquals(VpnState.Stopping, m.currentState)
        m.close()
    }

    @Test
    fun `stop while Preparing cancels the in-flight start cleanly`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        assertEquals(VpnState.Preparing, m.currentState)
        assertEquals(VpnCommandResult.Accepted, m.stop())
        assertEquals(VpnState.Stopping, m.currentState)
        assertFalse(m.onRunning(t))
        m.close()
    }

    @Test
    fun `Revoked can only return to Idle`() {
        assertTrue(VpnState.Revoked.canTransitionTo(VpnState.Idle))
        assertFalse(VpnState.Revoked.canTransitionTo(VpnState.Running))
        assertFalse(VpnState.Revoked.canTransitionTo(VpnState.Preparing))
    }

    /** `Running -> Error` is the P1-T5 hardening: a live tunnel can die. */
    @Test
    fun `Running can fail unexpectedly`() {
        assertTrue(VpnState.Running.canTransitionTo(VpnState.Error("tunnel died")))
    }

    // ------------------------------------------------------------- failure + retry

    @Test
    fun `failure from Preparing Starting and Running lands in Error with the reason`() =
        runTest {
            val settles = listOf<(VpnStateMachine, SessionToken) -> Unit>(
                { _, _ -> },
                { m, t -> m.onPreparingComplete(t) },
                { m, t -> m.onPreparingComplete(t); m.onRunning(t) },
            )
            for (settle in settles) {
                val m = VpnStateMachine(backgroundScope)
                m.start()
                val t = m.activeSession!!
                settle(m, t)
                assertTrue(m.onFailure(t, "boom"))
                assertEquals(VpnState.Error("boom"), m.currentState)
                m.close()
            }
        }

    @Test
    fun `Error supports explicit retry and dismissal`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onFailure(t, "boom")
        assertEquals(VpnState.Error("boom"), m.currentState)

        // Explicit retry.
        assertEquals(VpnCommandResult.Accepted, m.start())
        assertEquals(VpnState.Preparing, m.currentState)

        // Dismissal.
        m.onFailure(m.activeSession!!, "boom2")
        assertEquals(VpnCommandResult.Accepted, m.stop())
        assertEquals(VpnState.Stopping, m.currentState)
        m.close()
    }

    @Test
    fun `Stopped can restart a fresh session`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t); m.stop(); m.onStopped(t)
        assertEquals(VpnState.Stopped, m.currentState)

        assertEquals(VpnCommandResult.Accepted, m.start())
        assertEquals(VpnState.Preparing, m.currentState)
        assertFalse("a fresh session cannot reuse the old token", t == m.activeSession)
        m.close()
    }

    // ------------------------------------------------------------- revocation

    @Test
    fun `revoke is reachable from a live session and restoration returns to Idle`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)

        assertTrue(m.onRevoke())
        assertEquals(VpnState.Revoked, m.currentState)
        assertEquals(VpnCommandResult.RejectedPermissionDenied, m.start())

        assertTrue(m.onPermissionRestored())
        assertEquals(VpnState.Idle, m.currentState)
        assertEquals(VpnCommandResult.Accepted, m.start())
        m.close()
    }

    @Test
    fun `revoke before any start is a no-op`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        assertFalse(m.onRevoke())
        assertEquals(VpnState.Idle, m.currentState)
        m.close()
    }

    // ------------------------------------------------------------- session tokens

    @Test
    fun `a stale token callback is ignored`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val stale = m.activeSession!!
        m.onPreparingComplete(stale); m.onRunning(stale)
        m.stop(); m.onStopped(stale)

        // New session mints a fresh token.
        m.start()
        val fresh = m.activeSession!!
        assertFalse("tokens must be unique", stale == fresh)
        assertEquals(VpnState.Preparing, m.currentState)

        // A late callback from the superseded session must not apply.
        assertFalse(m.onRunning(stale))
        assertFalse(m.onStopped(stale))
        assertFalse(m.onFailure(stale, "late"))
        assertEquals(VpnState.Preparing, m.currentState)
        assertNotNull(m.lastRejection)
        assertTrue(m.lastRejection!!.contains("stale token"))
        m.close()
    }

    @Test
    fun `a late callback cannot resurrect a stopped session`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)
        m.stop(); m.onStopped(t)
        assertEquals(VpnState.Stopped, m.currentState)

        // The old session's Running callback arrives after teardown completed.
        assertFalse(m.onRunning(t))
        assertEquals(VpnState.Stopped, m.currentState)
        m.close()
    }

    @Test
    fun `an illegal in-session transition is refused not applied`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        // Preparing cannot go straight to Running.
        assertFalse(m.onRunning(t))
        assertEquals(VpnState.Preparing, m.currentState)
        assertTrue(m.lastRejection!!.contains("illegal transition"))
        m.close()
    }

    // ------------------------------------------------------------- watchdogs

    @Test
    fun `start watchdog forces Error when a start never settles`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        assertEquals(VpnState.Preparing, m.currentState)

        advanceTimeBy(4_999)
        runCurrent()
        assertEquals("must not fire early", VpnState.Preparing, m.currentState)

        advanceTimeBy(2)
        runCurrent()
        assertEquals(VpnState.Error("Watchdog timeout after 5000ms"), m.currentState)
        assertNotNull(m.lastWatchdogMessage)
        m.close()
    }

    @Test
    fun `start watchdog is disarmed by a successful start`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)

        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(VpnState.Running, m.currentState)
        m.close()
    }

    @Test
    fun `stop watchdog forces Stopped not Error when teardown hangs`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        val t = m.activeSession!!
        m.onPreparingComplete(t); m.onRunning(t)
        m.stop()
        assertEquals(VpnState.Stopping, m.currentState)

        advanceTimeBy(5_001)
        runCurrent()
        // Stopped, NOT Error: `Stopping -> Error` is illegal and the watchdog
        // exists to reach a legal resting state.
        assertEquals(VpnState.Stopped, m.currentState)
        assertTrue(m.lastWatchdogMessage!!.contains("forced to Stopped"))
        m.close()
    }

    @Test
    fun `a hung start followed by stop converges within one watchdog window`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        m.stop()
        advanceTimeBy(5_001)
        runCurrent()
        assertEquals(VpnState.Stopped, m.currentState)
        m.close()
    }

    @Test
    fun `watchdog uses the configured timeout when overridden`() = runTest {
        val m = VpnStateMachine(backgroundScope, watchdogTimeoutMillis = 1_000)
        assertEquals(1_000L, m.watchdogTimeoutMillis)
        m.start()
        advanceTimeBy(1_001)
        runCurrent()
        assertEquals(VpnState.Error("Watchdog timeout after 1000ms"), m.currentState)
        m.close()
    }

    @Test
    fun `default watchdog timeout is the mandated 5000ms`() {
        assertEquals(5_000L, VpnStateMachine.DEFAULT_WATCHDOG_TIMEOUT_MILLIS)
    }

    @Test
    fun `close cancels the watchdog`() = runTest {
        val m = VpnStateMachine(backgroundScope)
        m.start()
        m.close()
        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(VpnState.Preparing, m.currentState)
    }

    // ------------------------------------------------------------- concurrency

    @Test
    fun `concurrent starts yield exactly one Accepted`() {
        val m = VpnStateMachine()
        val results = java.util.concurrent.ConcurrentLinkedQueue<VpnCommandResult>()
        val threads = (1..32).map { Thread { results += m.start() } }
        threads.forEach { it.start() }
        threads.forEach { it.join() }

        assertEquals(1, results.count { it == VpnCommandResult.Accepted })
        assertEquals(31, results.count { it == VpnCommandResult.RejectedBusy })
        assertEquals(VpnState.Preparing, m.currentState)
        m.close()
    }

    // ------------------------------------------------------------- acceptance values

    @Test
    fun `all five acceptance results exist and are distinguishable`() {
        val all = listOf(
            VpnCommandResult.Accepted,
            VpnCommandResult.RejectedBusy,
            VpnCommandResult.RejectedInvalidConfig,
            VpnCommandResult.RejectedPermissionDenied,
            VpnCommandResult.Failed,
        )
        assertEquals(5, all.size)
        assertEquals(5, all.map { it.toString() }.toSet().size)
        assertEquals(5, all.map { it::class }.toSet().size)
    }

    private fun allStates(): List<VpnState> = listOf(
        VpnState.Idle, VpnState.Preparing, VpnState.Starting, VpnState.Running,
        VpnState.Stopping, VpnState.Stopped, VpnState.Error("x"), VpnState.Revoked,
    )
}
