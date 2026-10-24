package dev.brickvpn.harness

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import dev.brickvpn.harness.vpn.CommandCoordinator
import dev.brickvpn.harness.vpn.CommandKind
import dev.brickvpn.harness.vpn.CommandVerdictHub
import dev.brickvpn.harness.vpn.PigeonEventSink
import dev.brickvpn.harness.vpn.PigeonVpnApiImpl
import dev.brickvpn.harness.vpn.ServiceLifecycleHub
import dev.brickvpn.harness.vpn.VpnCommandOutcome
import dev.brickvpn.harness.vpn.VpnConsentStatus
import dev.brickvpn.harness.vpn.VpnNativeState
import dev.brickvpn.harness.vpn.VpnState
import dev.brickvpn.harness.vpn.VpnStateEvent
import dev.brickvpn.harness.vpn.VpnStateMachine
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.PluginRegistry
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.lang.reflect.Proxy

/**
 * Host-JVM unit tests for [VpnEngineAndroidPlugin].
 *
 * Verifies:
 * 1. Observer registration order (installed before currentServiceMachine is queried).
 * 2. Initial snapshot on onListen (with and without attached machine).
 * 3. All 8 state transitions & error reason forwarding (zero drops, correct sequence).
 * 4. Service destruction notification (emits final state, clears attachedMachine, invokes coordinator).
 * 5. Stream cancellation on onCancel (collector job cancelled, no leakage to old sink).
 * 6. Detachment cleanup (clears hubs, resets coordinator, cancels coroutine scope).
 * 7. ActivityAware forwarding to PigeonVpnApiImpl (real behavioral assertions).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class VpnEngineAndroidPluginTest {

    private val testDispatcher = StandardTestDispatcher()
    private val dummyContext: Context = object : ContextWrapper(null) {}

    private class FakeEventSink : EventChannel.EventSink {
        val events = mutableListOf<VpnStateEvent>()
        var endOfStreamCalled = false
        var lastError: Triple<String, String?, Any?>? = null

        override fun success(event: Any?) {
            if (event is VpnStateEvent) {
                events.add(event)
            }
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            lastError = Triple(errorCode, errorMessage, errorDetails)
        }

        override fun endOfStream() {
            endOfStreamCalled = true
        }
    }

    /**
     * A stateful fake [ActivityPluginBinding] built via [Proxy.newProxyInstance].
     * - [getActivity] returns a non-null dummy [Activity].
     * - [addActivityResultListener] captures the listener passed by [PigeonVpnApiImpl].
     * - [removeActivityResultListener] clears it.
     */
    private class StatefulBindingState {
        val dummyActivity: Activity = object : Activity() {}
        var capturedListener: PluginRegistry.ActivityResultListener? = null
    }

    private fun createStatefulBinding(state: StatefulBindingState = StatefulBindingState()): Pair<ActivityPluginBinding, StatefulBindingState> {
        val binding = Proxy.newProxyInstance(
            ActivityPluginBinding::class.java.classLoader,
            arrayOf(ActivityPluginBinding::class.java),
        ) { proxy, method, args ->
            when (method.name) {
                "equals" -> proxy === args?.get(0)
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "StatefulActivityPluginBinding"
                "getActivity" -> state.dummyActivity
                "addActivityResultListener" -> {
                    state.capturedListener = args?.get(0) as? PluginRegistry.ActivityResultListener
                    null
                }
                "removeActivityResultListener" -> {
                    if (args?.get(0) === state.capturedListener) {
                        state.capturedListener = null
                    }
                    null
                }
                else -> null
            }
        } as ActivityPluginBinding
        return binding to state
    }

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        ServiceLifecycleHub.errorLogger = { _, _ -> }
        ServiceLifecycleHub.reset()
        CommandVerdictHub.reset()
    }

    @After
    fun tearDown() {
        ServiceLifecycleHub.reset()
        CommandVerdictHub.reset()
        Dispatchers.resetMain()
    }

    // ------------------------------------------------------------- Item 1: Observer registration order

    @Test
    fun `attachLifecycleObserver registers observer BEFORE querying currentServiceMachine and attaches if non-null`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        val machine = VpnStateMachine(backgroundScope)
        var queriedBeforeObserverInstalled: Boolean? = null

        plugin.attachLifecycleObserver(
            currentServiceMachine = {
                queriedBeforeObserverInstalled = ServiceLifecycleHub.observer != null
                machine
            },
        )

        assertTrue(
            "ServiceLifecycleHub.observer must be installed before currentServiceMachine() is queried",
            queriedBeforeObserverInstalled == true,
        )
        assertNotNull("ServiceLifecycleHub.observer must remain installed", ServiceLifecycleHub.observer)
        assertEquals("stateHandler must attach the returned machine", machine, plugin.stateHandler.attachedMachineState())
    }

    @Test
    fun `attachLifecycleObserver with null currentServiceMachine installs observer but leaves machine unattached`() {
        val plugin = VpnEngineAndroidPlugin()
        plugin.attachLifecycleObserver(currentServiceMachine = { null })

        assertNotNull("ServiceLifecycleHub.observer must be installed", ServiceLifecycleHub.observer)
        assertNull("stateHandler must have no attached machine", plugin.stateHandler.attachedMachineState())
    }

    // ------------------------------------------------------------- Item 2: Initial snapshot on onListen

    @Test
    fun `onListen with no attached machine immediately emits IDLE snapshot`() {
        val plugin = VpnEngineAndroidPlugin()
        val fakeSink = FakeEventSink()
        val sink = PigeonEventSink<VpnStateEvent>(fakeSink)

        plugin.stateHandler.onListen(null, sink)

        assertEquals(listOf(VpnStateEvent(VpnNativeState.IDLE, null)), fakeSink.events)
    }

    @Test
    fun `onListen with attached machine already in Running immediately emits RUNNING snapshot`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        plugin.scope = backgroundScope
        val machine = VpnStateMachine(backgroundScope)
        machine.start()
        val token = machine.activeSession!!
        machine.onPreparingComplete(token)
        machine.onRunning(token)
        assertEquals(VpnState.Running, machine.currentState)

        plugin.stateHandler.attachMachine(machine)

        val fakeSink = FakeEventSink()
        val sink = PigeonEventSink<VpnStateEvent>(fakeSink)

        plugin.stateHandler.onListen(null, sink)

        assertEquals(listOf(VpnStateEvent(VpnNativeState.RUNNING, null)), fakeSink.events)
    }

    // ------------------------------------------------------------- Item 3: All 8 state transitions & error reason

    @Test
    fun `driving attached machine through all 8 states delivers exact VpnStateEvent sequence in order with zero drops`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        plugin.scope = backgroundScope
        val machine = VpnStateMachine(backgroundScope)

        plugin.stateHandler.attachMachine(machine)

        val fakeSink = FakeEventSink()
        val sink = PigeonEventSink<VpnStateEvent>(fakeSink)

        plugin.stateHandler.onListen(null, sink)
        runCurrent()

        // 1. Snapshot: Idle
        assertEquals(listOf(VpnStateEvent(VpnNativeState.IDLE, null)), fakeSink.events)

        // 2. Start -> Preparing
        machine.start()
        runCurrent()
        val token1 = machine.activeSession!!
        assertEquals(VpnState.Preparing, machine.currentState)

        // 3. Preparing -> Starting
        machine.onPreparingComplete(token1)
        runCurrent()
        assertEquals(VpnState.Starting, machine.currentState)

        // 4. Starting -> Running
        machine.onRunning(token1)
        runCurrent()
        assertEquals(VpnState.Running, machine.currentState)

        // 5. Running -> Stopping
        machine.stop()
        runCurrent()
        assertEquals(VpnState.Stopping, machine.currentState)

        // 6. Stopping -> Stopped
        machine.onStopped(token1)
        runCurrent()
        assertEquals(VpnState.Stopped, machine.currentState)

        // Restart to reach Error: Stopped -> Preparing -> Starting -> Running -> Error
        machine.start()
        runCurrent()
        val token2 = machine.activeSession!!

        machine.onPreparingComplete(token2)
        runCurrent()

        machine.onRunning(token2)
        runCurrent()

        // 7. Running -> Error("tunnel crashed")
        val testErrorReason = "native tunnel process crashed unexpectedly"
        machine.onFailure(token2, testErrorReason)
        runCurrent()
        assertTrue(machine.currentState is VpnState.Error)

        // 8. Error -> Revoked
        machine.onRevoke()
        runCurrent()
        assertEquals(VpnState.Revoked, machine.currentState)

        val expected = listOf(
            VpnStateEvent(VpnNativeState.IDLE, null),
            VpnStateEvent(VpnNativeState.PREPARING, null),
            VpnStateEvent(VpnNativeState.STARTING, null),
            VpnStateEvent(VpnNativeState.RUNNING, null),
            VpnStateEvent(VpnNativeState.STOPPING, null),
            VpnStateEvent(VpnNativeState.STOPPED, null),
            VpnStateEvent(VpnNativeState.PREPARING, null),
            VpnStateEvent(VpnNativeState.STARTING, null),
            VpnStateEvent(VpnNativeState.RUNNING, null),
            VpnStateEvent(VpnNativeState.ERROR, testErrorReason),
            VpnStateEvent(VpnNativeState.REVOKED, null),
        )

        assertEquals("All 8 state transitions must be delivered in exact order with zero drops", expected, fakeSink.events)
    }

    // ------------------------------------------------------------- Item 4: Service destruction notification

    @Test
    fun `ServiceLifecycleHub destroyed fires onServiceDestroyed, emits final state, clears attachedMachine, and notifies coordinator`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        plugin.scope = backgroundScope
        val coordinator = CommandCoordinator(
            setListener = { CommandVerdictHub.listener = it },
            mainDispatcher = testDispatcher,
        )
        plugin.coordinator = coordinator

        plugin.attachLifecycleObserver(currentServiceMachine = { null })

        val machine = VpnStateMachine(backgroundScope)
        ServiceLifecycleHub.created(machine)
        assertEquals(machine, plugin.stateHandler.attachedMachineState())

        val fakeSink = FakeEventSink()
        val sink = PigeonEventSink<VpnStateEvent>(fakeSink)
        plugin.stateHandler.onListen(null, sink)
        runCurrent()

        // Start an asynchronous command through coordinator to verify it is terminated on service destroy
        val deferredOutcome = async {
            coordinator.run(CommandKind.START) {
                // simulated start launcher that never returns a verdict because service crashed
            }
        }
        runCurrent()

        // Drive machine to Stopped before destroying
        machine.start()
        val token = machine.activeSession!!
        machine.stop()
        machine.onStopped(token)
        runCurrent()

        fakeSink.events.clear()

        // Fire service destruction
        ServiceLifecycleHub.destroyed()
        runCurrent()

        // Verify:
        // a) final state (STOPPED) was emitted to sink
        assertEquals(listOf(VpnStateEvent(VpnNativeState.STOPPED, null)), fakeSink.events)
        // b) attachedMachine was cleared
        assertNull("attachedMachine must be cleared after onServiceDestroyed", plugin.stateHandler.attachedMachineState())
        // c) coordinator pending command received FAILED
        assertEquals(VpnCommandOutcome.FAILED, deferredOutcome.await())
    }

    // ------------------------------------------------------------- Item 5: Stream cancellation (onCancel)

    @Test
    fun `onCancel cancels collector job so subsequent machine transitions are not emitted to old sink`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        plugin.scope = backgroundScope
        val machine = VpnStateMachine(backgroundScope)
        machine.start()
        val token = machine.activeSession!!
        machine.onPreparingComplete(token)
        machine.onRunning(token)

        plugin.stateHandler.attachMachine(machine)

        val fakeSink = FakeEventSink()
        val sink = PigeonEventSink<VpnStateEvent>(fakeSink)

        plugin.stateHandler.onListen(null, sink)
        runCurrent()

        assertEquals(listOf(VpnStateEvent(VpnNativeState.RUNNING, null)), fakeSink.events)

        // Cancel the stream
        plugin.stateHandler.onCancel(null)
        runCurrent()

        // Subsequent machine transitions must not reach the old sink
        machine.stop()
        machine.onStopped(token)
        runCurrent()

        assertEquals("No transitions should reach sink after onCancel", listOf(VpnStateEvent(VpnNativeState.RUNNING, null)), fakeSink.events)
    }

    // ------------------------------------------------------------- Item 6: Detachment cleanup

    @Test
    fun `detach clears ServiceLifecycleHub observer, CommandVerdictHub listener, and coroutine scope`() {
        val plugin = VpnEngineAndroidPlugin()
        plugin.attachLifecycleObserver(currentServiceMachine = { null })
        assertNotNull(ServiceLifecycleHub.observer)

        CommandVerdictHub.listener = { _, _ -> }
        assertNotNull(CommandVerdictHub.listener)

        val coordinator = CommandCoordinator(
            setListener = { CommandVerdictHub.listener = it },
            mainDispatcher = testDispatcher,
        )
        plugin.coordinator = coordinator

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
        )
        plugin.impl = impl

        plugin.detach()

        assertNull("ServiceLifecycleHub.observer must be cleared on detach", ServiceLifecycleHub.observer)
        assertNull("CommandVerdictHub.listener must be cleared on detach", CommandVerdictHub.listener)
        assertNull("coordinator must be cleared on detach", plugin.coordinator)
        assertNull("impl must be cleared on detach", plugin.impl)
        assertNull("scope must be cleared on detach", plugin.scope)
    }

    // ------------------------------------------------------------- Item 7: ActivityAware forwarding (real behavioral assertions)

    @Test
    fun `ActivityAware attach registers listener on binding and invoking it completes prepare with GRANTED`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        var capturedRequestCode: Int? = null
        val (binding, bindingState) = createStatefulBinding()

        val coordinator = CommandCoordinator(
            setListener = { CommandVerdictHub.listener = it },
            mainDispatcher = testDispatcher,
        )
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            // prepareChecker returns a non-null Intent, triggering the consent flow
            prepareChecker = { Intent() },
            activityStarter = { _, _, requestCode -> capturedRequestCode = requestCode },
        )
        plugin.impl = impl

        // Assertion A: onAttachedToActivity registers impl's ActivityResultListener on binding
        plugin.onAttachedToActivity(binding)
        assertEquals("activityBinding must be set", binding, plugin.activityBinding)
        assertNotNull(
            "PigeonVpnApiImpl must register an ActivityResultListener via binding.addActivityResultListener",
            bindingState.capturedListener,
        )

        // Start an async prepare() call — it should launch startActivityForResult and then suspend
        val prepareResult = async { impl.prepare() }
        runCurrent()

        // The activityStarter must have been called with a requestCode
        assertNotNull("activityStarter must have been invoked with a requestCode", capturedRequestCode)

        // Simulate the Activity result callback: invoke the captured listener with RESULT_OK
        val consumed = bindingState.capturedListener!!.onActivityResult(
            capturedRequestCode!!, Activity.RESULT_OK, null,
        )
        assertTrue("capturedListener must consume the matching requestCode", consumed)
        runCurrent()

        // The pending prepare() call must now complete with GRANTED
        assertEquals(
            "prepare() must complete with GRANTED when onActivityResult returns RESULT_OK",
            VpnConsentStatus.GRANTED,
            prepareResult.await(),
        )
    }

    @Test
    fun `ActivityAware config-change reattach preserves activity and detach aborts pending prepare with DENIED`() = runTest(testDispatcher) {
        val plugin = VpnEngineAndroidPlugin()
        val state1 = StatefulBindingState()
        val (binding1, _) = createStatefulBinding(state1)
        val state2 = StatefulBindingState()
        val (binding2, bindingState2) = createStatefulBinding(state2)

        val coordinator = CommandCoordinator(
            setListener = { CommandVerdictHub.listener = it },
            mainDispatcher = testDispatcher,
        )
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityStarter = { _, _, _ -> /* no-op; leave prepare pending */ },
        )
        plugin.impl = impl

        // Attach initial binding
        plugin.onAttachedToActivity(binding1)
        assertEquals(binding1, plugin.activityBinding)

        // Config change: detach then reattach with binding2
        plugin.onDetachedFromActivityForConfigChanges()
        // activityBinding is NOT cleared on config-change detach (plugin keeps it)
        assertEquals(
            "activityBinding must NOT be cleared on onDetachedFromActivityForConfigChanges",
            binding1,
            plugin.activityBinding,
        )

        plugin.onReattachedToActivityForConfigChanges(binding2)
        assertEquals("activityBinding must be updated to binding2", binding2, plugin.activityBinding)

        // Start a new async prepare() call — it will stay pending because activityStarter is a no-op
        val prepareResult = async { impl.prepare() }
        runCurrent()

        // Now call onDetachedFromActivity — this must abort the pending prepare() with DENIED
        plugin.onDetachedFromActivity()
        runCurrent()

        assertNull("activityBinding must be null after onDetachedFromActivity", plugin.activityBinding)

        // The pending prepare() call must now complete with DENIED
        assertEquals(
            "onDetachedFromActivity must abort pending prepare() with DENIED",
            VpnConsentStatus.DENIED,
            prepareResult.await(),
        )
    }
}
