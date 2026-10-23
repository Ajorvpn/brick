package dev.brickvpn.harness.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CommandCoordinatorTest {

    private var activeListener: ((CommandKind, VpnCommandResult) -> Unit)? = null
    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        activeListener = null
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        activeListener = null
    }

    private fun createCoordinator(
        timeoutMillis: Long = CommandCoordinator.TIMEOUT_MILLIS,
    ): CommandCoordinator {
        return CommandCoordinator(
            setListener = { activeListener = it },
            mainDispatcher = testDispatcher,
            timeoutMillis = timeoutMillis,
        )
    }

    @Test
    fun `START maps all 5 VpnCommandResult variants to VpnCommandOutcome`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        val cases = listOf(
            VpnCommandResult.Accepted to VpnCommandOutcome.ACCEPTED,
            VpnCommandResult.RejectedBusy to VpnCommandOutcome.REJECTED_BUSY,
            VpnCommandResult.RejectedInvalidConfig to VpnCommandOutcome.REJECTED_INVALID_CONFIG,
            VpnCommandResult.RejectedPermissionDenied to VpnCommandOutcome.REJECTED_PERMISSION_DENIED,
            VpnCommandResult.Failed to VpnCommandOutcome.FAILED,
        )

        for ((result, expectedOutcome) in cases) {
            val deferredOutcome = async {
                coordinator.run(CommandKind.START) {}
            }
            runCurrent()
            assertNotNull("listener should be installed", activeListener)
            activeListener?.invoke(CommandKind.START, result)
            runCurrent()
            assertEquals(expectedOutcome, deferredOutcome.await())
            assertNull("listener should be cleared after completion", activeListener)
        }
    }

    @Test
    fun `STOP maps Accepted to ACCEPTED`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        val deferredOutcome = async {
            coordinator.run(CommandKind.STOP) {}
        }
        runCurrent()
        assertNotNull("listener should be installed", activeListener)
        activeListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
        assertNull("listener should be cleared after completion", activeListener)
    }

    @Test
    fun `listener is installed before sendIntent executes`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        var listenerInstalledDuringSendIntent = false

        val deferredOutcome = async {
            coordinator.run(CommandKind.START) {
                listenerInstalledDuringSendIntent = (activeListener != null)
            }
        }
        runCurrent()
        assertTrue("listener must be installed before sendIntent is called", listenerInstalledDuringSendIntent)
        activeListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
    }

    @Test
    fun `second command while in-flight immediately returns REJECTED_BUSY`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        var secondSendIntentCalled = false

        val firstDeferred = async {
            coordinator.run(CommandKind.START) {}
        }
        runCurrent()
        assertNotNull(activeListener)
        val originalListener = activeListener

        val secondOutcome = coordinator.run(CommandKind.STOP) {
            secondSendIntentCalled = true
        }

        assertEquals(VpnCommandOutcome.REJECTED_BUSY, secondOutcome)
        assertFalse("second command must not call sendIntent", secondSendIntentCalled)
        assertEquals("active listener must not be overwritten", originalListener, activeListener)

        // Complete the first command cleanly
        activeListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, firstDeferred.await())
        assertNull(activeListener)
    }

    @Test
    fun `STOP ignores START verdict and only completes on STOP verdict`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        val deferred = async {
            coordinator.run(CommandKind.STOP) {}
        }
        runCurrent()

        // Send unmatched START verdict
        activeListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertFalse("STOP should not be completed by START verdict", deferred.isCompleted)

        // Send matching STOP verdict
        activeListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
        runCurrent()
        assertTrue("STOP should be completed by STOP verdict", deferred.isCompleted)
        assertEquals(VpnCommandOutcome.ACCEPTED, deferred.await())
    }

    @Test
    fun `START ignores STOP verdict and only completes on START verdict`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        val deferred = async {
            coordinator.run(CommandKind.START) {}
        }
        runCurrent()

        // Send unmatched STOP verdict
        activeListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
        runCurrent()
        assertFalse("START should not be completed by STOP verdict", deferred.isCompleted)

        // Send matching START verdict
        activeListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertTrue("START should be completed by START verdict", deferred.isCompleted)
        assertEquals(VpnCommandOutcome.ACCEPTED, deferred.await())
    }

    @Test
    fun `timeout returns FAILED and clears listener so subsequent command can run`() = runTest(testDispatcher) {
        val coordinator = createCoordinator(timeoutMillis = 1_000L)
        val deferred = async {
            coordinator.run(CommandKind.START) {}
        }
        runCurrent()
        assertNotNull(activeListener)

        advanceTimeBy(1_001L)
        runCurrent()

        assertTrue(deferred.isCompleted)
        assertEquals(VpnCommandOutcome.FAILED, deferred.await())
        assertNull("listener must be cleared in finally", activeListener)

        // Verify a subsequent command runs cleanly
        val nextDeferred = async {
            coordinator.run(CommandKind.STOP) {}
        }
        runCurrent()
        assertNotNull(activeListener)
        activeListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, nextDeferred.await())
    }

    @Test
    fun `sendIntent exception returns FAILED and cleans up pendingKind and listener`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        val outcome = coordinator.run(CommandKind.START) {
            throw RuntimeException("send failed")
        }
        assertEquals(VpnCommandOutcome.FAILED, outcome)
        assertNull("listener must be cleaned up", activeListener)

        // Subsequent command can run without being blocked
        val nextDeferred = async {
            coordinator.run(CommandKind.STOP) {}
        }
        runCurrent()
        assertNotNull(activeListener)
        activeListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, nextDeferred.await())
    }

    @Test
    fun `onServiceDestroyed while command pending completes with FAILED immediately`() = runTest(testDispatcher) {
        val coordinator = createCoordinator()
        val deferred = async {
            coordinator.run(CommandKind.START) {}
        }
        runCurrent()
        assertNotNull(activeListener)

        coordinator.onServiceDestroyed()
        runCurrent()

        assertTrue("deferred must be completed immediately", deferred.isCompleted)
        assertEquals(VpnCommandOutcome.FAILED, deferred.await())
        assertNull("listener should be cleared in finally", activeListener)

        // Subsequent command can run
        val nextDeferred = async {
            coordinator.run(CommandKind.START) {}
        }
        runCurrent()
        activeListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, nextDeferred.await())
    }

    @Test
    fun `verdict arriving with nothing pending throws nothing`() {
        var listener: ((CommandKind, VpnCommandResult) -> Unit)? = null
        CommandCoordinator(setListener = { listener = it })
        assertNull(listener)
    }
}
