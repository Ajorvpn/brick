package dev.brickvpn.harness.vpn

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PigeonVpnApiImplTest {

    private val testDispatcher = StandardTestDispatcher()
    private val dummyContext: Context = object : ContextWrapper(null) {}
    private var hubListener: ((CommandKind, VpnCommandResult) -> Unit)? = null
    private lateinit var coordinator: CommandCoordinator

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        hubListener = null
        coordinator = CommandCoordinator(
            setListener = { hubListener = it },
            mainDispatcher = testDispatcher,
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        hubListener = null
    }

    // ------------------------------------------------------------- start()

    @Test
    fun `start with empty profileJson returns REJECTED_INVALID_CONFIG immediately`() = runTest(testDispatcher) {
        var prepareCheckerCalled = false
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { prepareCheckerCalled = true; null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val outcome = impl.start(emptyMap())

        assertEquals(VpnCommandOutcome.REJECTED_INVALID_CONFIG, outcome)
        assertFalse("prepareChecker must not be called", prepareCheckerCalled)
        assertFalse("startServiceLauncher must not be called", startLauncherCalled)
    }

    @Test
    fun `start with permission denied returns REJECTED_PERMISSION_DENIED without starting service`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val outcome = impl.start(mapOf("profile" to "test-data"))

        assertEquals(VpnCommandOutcome.REJECTED_PERMISSION_DENIED, outcome)
        assertFalse("startServiceLauncher must not be called", startLauncherCalled)
    }

    @Test
    fun `start with valid config and permission dispatches through coordinator and returns outcome`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val deferredOutcome = async {
            impl.start(mapOf("profile" to "test-data"))
        }
        runCurrent()

        assertTrue("startServiceLauncher must be dispatched", startLauncherCalled)
        hubListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()

        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
    }

    // -------------------------------------------------------------- stop() (Decision D1)

    @Test
    fun `stop in Idle, Stopped, Stopping, or Revoked returns REJECTED_BUSY without sending intent`() = runTest(testDispatcher) {
        val busyStates = listOf(
            VpnState.Idle,
            VpnState.Stopped,
            VpnState.Stopping,
            VpnState.Revoked,
        )

        for (state in busyStates) {
            var stopLauncherCount = 0
            val impl = PigeonVpnApiImpl(
                appContext = dummyContext,
                coordinator = coordinator,
                stateProvider = { state },
                stopServiceLauncher = { stopLauncherCount++ },
            )

            val outcome = impl.stop()

            assertEquals("State $state should return REJECTED_BUSY", VpnCommandOutcome.REJECTED_BUSY, outcome)
            assertEquals("stopServiceLauncher must never be called for $state", 0, stopLauncherCount)
        }
    }

    @Test
    fun `stop in Preparing, Starting, Running, or Error dispatches STOP and returns outcome`() = runTest(testDispatcher) {
        val activeStates = listOf(
            VpnState.Preparing,
            VpnState.Starting,
            VpnState.Running,
            VpnState.Error("test error"),
        )

        for (state in activeStates) {
            var stopLauncherCount = 0
            val impl = PigeonVpnApiImpl(
                appContext = dummyContext,
                coordinator = coordinator,
                stateProvider = { state },
                stopServiceLauncher = { stopLauncherCount++ },
            )

            val deferredOutcome = async {
                impl.stop()
            }
            runCurrent()

            assertEquals("stopServiceLauncher should be called once for $state", 1, stopLauncherCount)
            hubListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
            runCurrent()

            assertEquals("State $state should complete with ACCEPTED", VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
        }
    }

    // --------------------------------------------------------- getStatus()

    @Test
    fun `getStatus maps all 8 VpnState variants to VpnNativeState correctly`() {
        val mappings = listOf(
            VpnState.Idle to (VpnNativeState.IDLE to null),
            VpnState.Preparing to (VpnNativeState.PREPARING to null),
            VpnState.Starting to (VpnNativeState.STARTING to null),
            VpnState.Running to (VpnNativeState.RUNNING to null),
            VpnState.Stopping to (VpnNativeState.STOPPING to null),
            VpnState.Stopped to (VpnNativeState.STOPPED to null),
            VpnState.Revoked to (VpnNativeState.REVOKED to null),
            VpnState.Error("boom") to (VpnNativeState.ERROR to "boom"),
        )

        for ((state, expected) in mappings) {
            val (expectedNative, expectedReason) = expected
            val impl = PigeonVpnApiImpl(
                appContext = dummyContext,
                coordinator = coordinator,
                stateProvider = { state },
            )

            val status = impl.getStatus()
            assertEquals("Native state for $state", expectedNative, status.state)
            assertEquals("Error reason for $state", expectedReason, status.errorReason)
        }
    }

    // ----------------------------------------------------------- prepare() (R2)

    @Test
    fun `prepare when already granted returns ALREADY_GRANTED`() = runTest(testDispatcher) {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
        )

        val status = impl.prepare()
        assertEquals(VpnConsentStatus.ALREADY_GRANTED, status)
    }

    @Test
    fun `prepare when consent required but activity is null returns NO_ACTIVITY`() = runTest(testDispatcher) {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { null },
        )

        val status = impl.prepare()
        assertEquals(VpnConsentStatus.NO_ACTIVITY, status)
    }

    @Test
    fun `prepare when detached from activity while pending returns DENIED`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, _ -> },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        impl.onDetachedFromActivity()
        runCurrent()

        assertEquals(VpnConsentStatus.DENIED, deferred.await())
    }

    @Test
    fun `prepare completes with GRANTED on RESULT_OK via handleActivityResult`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode, Activity.RESULT_OK)
        runCurrent()

        assertTrue(handled)
        assertEquals(VpnConsentStatus.GRANTED, deferred.await())
    }

    @Test
    fun `prepare completes with DENIED on RESULT_CANCELED via handleActivityResult`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode, Activity.RESULT_CANCELED)
        runCurrent()

        assertTrue(handled)
        assertEquals(VpnConsentStatus.DENIED, deferred.await())
    }

    @Test
    fun `concurrent prepare calls reuse existing deferred`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred1 = async { impl.prepare() }
        val deferred2 = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode, Activity.RESULT_OK)
        runCurrent()

        assertTrue(handled)
        assertEquals(VpnConsentStatus.GRANTED, deferred1.await())
        assertEquals(VpnConsentStatus.GRANTED, deferred2.await())
    }

    @Test
    fun `handleActivityResult with mismatched request code returns false and leaves pending`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode + 999, Activity.RESULT_OK)
        runCurrent()

        assertFalse(handled)
        assertFalse(deferred.isCompleted)

        // Complete cleanly with correct code
        impl.handleActivityResult(capturedRequestCode, Activity.RESULT_OK)
        runCurrent()
        assertEquals(VpnConsentStatus.GRANTED, deferred.await())
    }
}
