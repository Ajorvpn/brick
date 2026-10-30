package dev.brickvpn.harness

import android.net.TrafficStats
import android.os.Process
import dev.brickvpn.harness.vpn.BrickVpnService
import dev.brickvpn.harness.vpn.CommandCoordinator
import dev.brickvpn.harness.vpn.CommandVerdictHub
import dev.brickvpn.harness.vpn.PigeonEventSink
import dev.brickvpn.harness.vpn.PigeonVpnApiImpl
import dev.brickvpn.harness.vpn.ServiceLifecycleHub
import dev.brickvpn.harness.vpn.ServiceLifecycleObserver
import dev.brickvpn.harness.vpn.StateEventsStreamHandler
import dev.brickvpn.harness.vpn.TrafficStatsEvent
import dev.brickvpn.harness.vpn.TrafficStatsEventsStreamHandler
import dev.brickvpn.harness.vpn.VpnEngineHostApi
import dev.brickvpn.harness.vpn.VpnNativeState
import dev.brickvpn.harness.vpn.VpnState
import dev.brickvpn.harness.vpn.VpnStateEvent
import dev.brickvpn.harness.vpn.VpnStateMachine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class VpnEngineAndroidPlugin : FlutterPlugin, ActivityAware {

    internal var scope: CoroutineScope? = null
    internal var activityBinding: ActivityPluginBinding? = null
    internal var impl: PigeonVpnApiImpl? = null
    internal var coordinator: CommandCoordinator? = null

    internal inner class PluginStateEventsStreamHandler : StateEventsStreamHandler() {
        private var sink: PigeonEventSink<VpnStateEvent>? = null
        private var collectorJob: kotlinx.coroutines.Job? = null
        private var attachedMachine: VpnStateMachine? = null

        override fun onListen(p0: Any?, sink: PigeonEventSink<VpnStateEvent>) {
            this.sink = sink
            val current = attachedMachine?.currentState ?: VpnState.Idle
            try {
                sink.success(VpnStateEvent(state = current.toNative(), errorReason = (current as? VpnState.Error)?.reason))
            } catch (_: Throwable) {}
            attachedMachine?.let { collectMachine(it) }
        }

        override fun onCancel(p0: Any?) {
            collectorJob?.cancel()
            collectorJob = null
            sink = null
        }

        fun attachMachine(machine: VpnStateMachine) {
            if (attachedMachine === machine) return
            collectorJob?.cancel()
            attachedMachine = machine
            sink?.let { s ->
                val current = machine.currentState
                try {
                    s.success(VpnStateEvent(state = current.toNative(), errorReason = (current as? VpnState.Error)?.reason))
                } catch (_: Throwable) {}
                collectMachine(machine)
            }
        }

        private fun collectMachine(machine: VpnStateMachine) {
            collectorJob?.cancel()
            collectorJob = scope?.launch {
                machine.state.drop(1).collect { st ->
                    val s = sink ?: return@collect
                    try {
                        s.success(VpnStateEvent(state = st.toNative(), errorReason = (st as? VpnState.Error)?.reason))
                    } catch (_: Throwable) {}
                }
            }
        }

        fun onServiceDestroyed(lastState: VpnState?) {
            sink?.let { s ->
                val finalState = when (lastState) {
                    is VpnState.Stopping, is VpnState.Running, is VpnState.Starting, is VpnState.Preparing -> VpnState.Stopped
                    is VpnState.Error -> lastState
                    is VpnState.Revoked -> lastState
                    null, is VpnState.Idle, is VpnState.Stopped -> VpnState.Stopped
                }
                try {
                    s.success(VpnStateEvent(state = finalState.toNative(), errorReason = (finalState as? VpnState.Error)?.reason))
                } catch (_: Throwable) {}
            }
            collectorJob?.cancel()
            collectorJob = null
            attachedMachine = null
        }

        fun attachedMachineState(): VpnStateMachine? = attachedMachine
    }

    // TEMP-ARTIFACT(P3-T16): Minimal real stats publisher. To be robustly upgraded in P3-T8.
    internal inner class PluginTrafficStatsEventsStreamHandler : TrafficStatsEventsStreamHandler() {
        private var sink: PigeonEventSink<TrafficStatsEvent>? = null
        private var pollingJob: kotlinx.coroutines.Job? = null
        private var attachedMachine: VpnStateMachine? = null

        override fun onListen(p0: Any?, sink: PigeonEventSink<TrafficStatsEvent>) {
            this.sink = sink
            attachedMachine?.let { startPollingIfRunning(it) }
        }

        override fun onCancel(p0: Any?) {
            pollingJob?.cancel()
            pollingJob = null
            sink = null
        }

        fun attachMachine(machine: VpnStateMachine) {
            attachedMachine = machine
            startPollingIfRunning(machine)
        }

        fun onServiceDestroyed() {
            pollingJob?.cancel()
            pollingJob = null
            attachedMachine = null
        }

        private fun startPollingIfRunning(machine: VpnStateMachine) {
            pollingJob?.cancel()
            pollingJob = scope?.launch {
                machine.state.collect { st ->
                    if (st is VpnState.Running) {
                        while (isActive && machine.currentState is VpnState.Running) {
                            val s = sink ?: break
                            val uidRx = TrafficStats.getUidRxBytes(Process.myUid())
                            val uidTx = TrafficStats.getUidTxBytes(Process.myUid())
                            val tunRx = runCatching {
                                java.io.File("/sys/class/net/tun0/statistics/rx_bytes").readText().trim().toLong()
                            }.getOrDefault(0L)
                            val tunTx = runCatching {
                                java.io.File("/sys/class/net/tun0/statistics/tx_bytes").readText().trim().toLong()
                            }.getOrDefault(0L)

                            val rx = if (tunRx > 0L) tunRx else if (uidRx >= 0L) uidRx else 0L
                            val tx = if (tunTx > 0L) tunTx else if (uidTx >= 0L) uidTx else 0L

                            try {
                                s.success(
                                    TrafficStatsEvent(
                                        txBytes = tx,
                                        rxBytes = rx,
                                        epochMillis = System.currentTimeMillis(),
                                    ),
                                )
                            } catch (_: Throwable) {}
                            delay(1000L)
                        }
                    }
                }
            }
        }
    }

    internal val stateHandler = PluginStateEventsStreamHandler()
    internal val trafficHandler = PluginTrafficStatsEventsStreamHandler()

    internal fun attachLifecycleObserver(
        currentServiceMachine: () -> VpnStateMachine? = { BrickVpnService.current?.stateMachine },
    ) {
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                stateHandler.attachMachine(machine)
                trafficHandler.attachMachine(machine)
            }
            override fun onDestroyed() {
                val last = stateHandler.attachedMachineState()?.currentState
                stateHandler.onServiceDestroyed(last)
                trafficHandler.onServiceDestroyed()
                coordinator?.onServiceDestroyed()
            }
        }
        currentServiceMachine()?.let { machine ->
            stateHandler.attachMachine(machine)
            trafficHandler.attachMachine(machine)
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

        coordinator = CommandCoordinator(
            setListener = { CommandVerdictHub.listener = it },
        )
        val ctx = binding.applicationContext
        impl = PigeonVpnApiImpl(
            appContext = ctx,
            coordinator = coordinator!!,
            activityProvider = { activityBinding?.activity },
        )

        VpnEngineHostApi.setUp(binding.binaryMessenger, impl!!)
        StateEventsStreamHandler.register(binding.binaryMessenger, stateHandler)
        TrafficStatsEventsStreamHandler.register(binding.binaryMessenger, trafficHandler)

        attachLifecycleObserver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detach()
    }

    internal fun detach() {
        ServiceLifecycleHub.observer = null
        ServiceLifecycleHub.reset()
        CommandVerdictHub.listener = null
        CommandVerdictHub.reset()
        scope?.cancel()
        scope = null
        impl = null
        coordinator = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        impl?.onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        impl?.onDetachedFromActivityForConfigChanges()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        impl?.onReattachedToActivityForConfigChanges(binding)
    }

    override fun onDetachedFromActivity() {
        impl?.onDetachedFromActivity()
        activityBinding = null
    }

    internal fun VpnState.toNative(): VpnNativeState = when (this) {
        VpnState.Idle -> VpnNativeState.IDLE
        VpnState.Preparing -> VpnNativeState.PREPARING
        VpnState.Starting -> VpnNativeState.STARTING
        VpnState.Running -> VpnNativeState.RUNNING
        VpnState.Stopping -> VpnNativeState.STOPPING
        VpnState.Stopped -> VpnNativeState.STOPPED
        is VpnState.Error -> VpnNativeState.ERROR
        VpnState.Revoked -> VpnNativeState.REVOKED
    }
}