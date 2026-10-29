package dev.brickvpn.harness.vpn

import android.content.Intent
import android.net.VpnService
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import dev.brickvpn.harness.VpnEngineAndroidPlugin
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * On-device end-to-end instrumented tests exercising real [PigeonVpnApiImpl],
 * real [CommandCoordinator], real [CommandVerdictHub], real [ServiceLifecycleHub],
 * and real [BrickVpnService] on the connected device (SM-A205F).
 *
 * Verifies:
 * 1. prepare() returns ALREADY_GRANTED when ACTIVATE_VPN appop is granted.
 * 2. start() triggers BrickVpnService, awaits real verdict, reaches RUNNING,
 *    live stream and getStatus reflect RUNNING, stop() returns ACCEPTED and settles
 *    in STOPPED/IDLE, and subsequent stop() returns REJECTED_BUSY without sending an intent.
 * 3. start() with a failing engine propagates VpnNativeState.ERROR with non-null
 *    errorReason through both getStatus() and the live stream, and stop() from
 *    Error returns ACCEPTED and recovers to STOPPED/IDLE.
 */
@RunWith(AndroidJUnit4::class)
class PigeonVpnApiImplInstrumentedTest {

    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    private val verdicts = CopyOnWriteArrayList<Pair<CommandKind, VpnCommandResult>>()
    private val streamEvents = CopyOnWriteArrayList<VpnStateEvent>()

    private lateinit var coordinator: CommandCoordinator
    private lateinit var impl: PigeonVpnApiImpl
    private lateinit var plugin: VpnEngineAndroidPlugin

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
    }

    private fun awaitService(): BrickVpnService {
        val deadline = System.currentTimeMillis() + 10_000
        while (System.currentTimeMillis() < deadline) {
            BrickVpnService.current?.let { return it }
            Thread.sleep(50)
        }
        throw AssertionError("service was never created")
    }

    private fun awaitStatus(
        predicate: (VpnNativeState) -> Boolean,
        label: String,
        timeoutMs: Long = 15_000,
    ): VpnStateEvent {
        val deadline = System.currentTimeMillis() + timeoutMs
        var last: VpnStateEvent = impl.getStatus()
        while (System.currentTimeMillis() < deadline) {
            last = impl.getStatus()
            if (predicate(last.state)) return last
            Thread.sleep(50)
        }
        throw AssertionError(
            "timed out waiting for status $label; last was $last, streamEvents=${streamEvents.joinToString()}",
        )
    }

    @Before
    fun setUp() {
        VpnService.prepare(context)
        stopLeftoverService()
        Thread.sleep(500)

        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        verdicts.clear()
        streamEvents.clear()

        plugin = VpnEngineAndroidPlugin()
        plugin.scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

        coordinator = CommandCoordinator(
            setListener = { listener ->
                CommandVerdictHub.listener = { kind, result ->
                    verdicts += kind to result
                    listener?.invoke(kind, result)
                }
            },
        )

        impl = PigeonVpnApiImpl(
            appContext = context,
            coordinator = coordinator,
        )

        plugin.impl = impl
        plugin.coordinator = coordinator

        // Wire plugin lifecycle observer to ServiceLifecycleHub
        plugin.attachLifecycleObserver()

        // Connect fake sink to plugin's stateHandler to capture stream events
        val fakeSink = object : EventChannel.EventSink {
            override fun success(event: Any?) {
                if (event is VpnStateEvent) {
                    streamEvents += event
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

            override fun endOfStream() {}
        }
        plugin.stateHandler.onListen(null, PigeonEventSink(fakeSink))
    }

    @After
    fun tearDown() {
        BrickVpnService.engineFactoryForTests = null
        runCatching {
            context.startService(
                Intent(context, BrickVpnService::class.java)
                    .setAction(BrickVpnService.ACTION_STOP),
            )
        }
        Thread.sleep(1_500)
        plugin.detach()
        stopLeftoverService()
        CommandVerdictHub.reset()
        ServiceLifecycleHub.reset()
        verdicts.clear()
        streamEvents.clear()
    }

    /**
     * Test 1: prepare() when ACTIVATE_VPN appop is granted returns ALREADY_GRANTED.
     */
    @Test
    fun prepareWhenConsentGrantedReturnsAlreadyGranted() = runBlocking {
        val consent = impl.prepare()
        assertEquals(VpnConsentStatus.ALREADY_GRANTED, consent)
    }

    /**
     * Test 2: start, live state stream, getStatus, and stop end-to-end through PigeonVpnApiImpl.
     */
    @Test
    fun startLiveStateStreamGetStatusAndStopEndToEnd() = runBlocking {
        // Baseline: initial status before start must be IDLE
        val initialStatus = impl.getStatus()
        assertEquals(VpnNativeState.IDLE, initialStatus.state)

        // 1. Calling impl.start() with valid profile starts BrickVpnService and returns ACCEPTED
        val startOutcome = impl.start(mapOf("id" to "test-e2e-profile", "name" to "Test Profile", "outbound" to mapOf("type" to "block", "tag" to "block-out")))
        assertEquals(
            "start() must await real verdict and return ACCEPTED",
            VpnCommandOutcome.ACCEPTED,
            startOutcome,
        )

        // 2. Service reaches RUNNING; confirmed via awaitService() and impl.getStatus()
        awaitService()
        awaitStatus({ it == VpnNativeState.RUNNING }, "RUNNING")
        val runningStatus = impl.getStatus()
        assertEquals(VpnNativeState.RUNNING, runningStatus.state)

        // Confirm live event stream also recorded RUNNING
        assertTrue(
            "streamEvents must observe RUNNING; recorded=${streamEvents.joinToString()}",
            streamEvents.any { it.state == VpnNativeState.RUNNING },
        )

        // 3. Calling impl.stop() while Running sends ACTION_STOP and returns ACCEPTED
        val stopOutcome = impl.stop()
        assertEquals(
            "stop() while Running must await verdict and return ACCEPTED",
            VpnCommandOutcome.ACCEPTED,
            stopOutcome,
        )

        // 4. Polling impl.getStatus() observes STOPPED or IDLE (after service destruction)
        awaitStatus(
            { it == VpnNativeState.STOPPED || it == VpnNativeState.IDLE },
            "STOPPED or IDLE",
        )

        // 5. Calling impl.stop() a second time when already stopped returns REJECTED_BUSY
        //    without dispatching an intent through coordinator
        val verdictCountBeforeSecondStop = verdicts.size
        val secondStopOutcome = impl.stop()
        assertEquals(
            "stop() while stopped must return REJECTED_BUSY",
            VpnCommandOutcome.REJECTED_BUSY,
            secondStopOutcome,
        )
        assertEquals(
            "stop() while stopped must not publish any new command verdict",
            verdictCountBeforeSecondStop,
            verdicts.size,
        )
    }

    /**
     * Test 3: start() with a failing engine propagates ERROR state + errorReason
     * through getStatus() and the live stream, and stop() from Error recovers.
     */
    @Test
    fun startWithFailingEnginePropagatesErrorStateAndStopRecovers(): Unit = runBlocking {
        val errorMessage = "simulated native engine failure"
        BrickVpnService.engineFactoryForTests = {
            FakeTunnelEngine(failWith = IllegalStateException(errorMessage))
        }
        try {
            // 1. start() returns ACCEPTED (command acceptance is separate from async startup failure)
            val startOutcome = impl.start(mapOf("id" to "err-test", "name" to "Error Test", "outbound" to mapOf("type" to "block", "tag" to "block-out")))
            assertEquals(
                "start() must return ACCEPTED even when engine will fail asynchronously",
                VpnCommandOutcome.ACCEPTED,
                startOutcome,
            )

            // 2. Poll until state reaches ERROR
            awaitStatus({ it == VpnNativeState.ERROR }, "ERROR")
            val errorStatus = impl.getStatus()
            assertEquals(
                "getStatus().state must be ERROR after engine failure",
                VpnNativeState.ERROR,
                errorStatus.state,
            )
            assertNotNull(
                "getStatus().errorReason must be non-null after engine failure",
                errorStatus.errorReason,
            )
            assertTrue(
                "getStatus().errorReason must contain the simulated failure message; " +
                    "actual='${errorStatus.errorReason}'",
                errorStatus.errorReason!!.contains(errorMessage),
            )

            // 3. Verify live stream also captured the ERROR event
            val streamErrorEvent = streamEvents.find { it.state == VpnNativeState.ERROR }
            assertNotNull(
                "streamEvents must contain an ERROR event; recorded=${streamEvents.joinToString()}",
                streamErrorEvent,
            )
            assertNotNull(
                "stream ERROR event errorReason must be non-null",
                streamErrorEvent!!.errorReason,
            )
            assertTrue(
                "stream ERROR event errorReason must contain the simulated failure message; " +
                    "actual='${streamErrorEvent.errorReason}'",
                streamErrorEvent.errorReason!!.contains(errorMessage),
            )

            // 4. stop() while in ERROR must return ACCEPTED (D1 & D2 recovery from Error)
            val stopOutcome = impl.stop()
            assertEquals(
                "stop() while in ERROR must return ACCEPTED",
                VpnCommandOutcome.ACCEPTED,
                stopOutcome,
            )

            // 5. Poll until state settles to STOPPED or IDLE (clean recovery)
            awaitStatus(
                { it == VpnNativeState.STOPPED || it == VpnNativeState.IDLE },
                "STOPPED or IDLE",
            )
        } finally {
            BrickVpnService.engineFactoryForTests = null
        }
    }

    /**
     * Test 4: start() with untagged VLESS outbound proves that buildConfigJson
     * injects "tag": "proxy", "direct-out", and DNS detour, allowing sing-box
     * to reach RUNNING on a real device without detour or cache errors, and stop cleanly.
     */
    @Test
    fun startWithUntaggedVlessOutboundReachesRunningAndStopsCleanly(): Unit = runBlocking {
        val initialStatus = impl.getStatus()
        assertEquals(VpnNativeState.IDLE, initialStatus.state)

        val vlessProfile = mapOf(
            "id" to "vless-e2e-profile",
            "name" to "VLESS E2E Test",
            "outbound" to mapOf(
                "type" to "vless",
                "server" to "example.com",
                "server_port" to 443,
                "uuid" to "00000000-0000-0000-0000-000000000000",
            ),
        )

        // 1. Calling impl.start() with untagged VLESS returns ACCEPTED
        val startOutcome = impl.start(vlessProfile)
        assertEquals(
            "start() with untagged VLESS outbound must return ACCEPTED",
            VpnCommandOutcome.ACCEPTED,
            startOutcome,
        )

        // 2. Service reaches RUNNING; proves sing-box parsed VLESS config without detour errors
        awaitService()
        awaitStatus({ it == VpnNativeState.RUNNING }, "RUNNING")
        val runningStatus = impl.getStatus()
        assertEquals(VpnNativeState.RUNNING, runningStatus.state)

        // 3. Calling impl.stop() while Running returns ACCEPTED and settles to STOPPED or IDLE
        val stopOutcome = impl.stop()
        assertEquals(
            "stop() while Running must await verdict and return ACCEPTED",
            VpnCommandOutcome.ACCEPTED,
            stopOutcome,
        )

        awaitStatus(
            { it == VpnNativeState.STOPPED || it == VpnNativeState.IDLE },
            "STOPPED or IDLE",
        )
    }
}
