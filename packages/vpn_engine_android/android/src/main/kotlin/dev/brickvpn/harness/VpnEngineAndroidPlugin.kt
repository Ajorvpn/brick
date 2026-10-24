package dev.brickvpn.harness

import dev.brickvpn.harness.vpn.BrickVpnService
import dev.brickvpn.harness.vpn.CommandCoordinator
import dev.brickvpn.harness.vpn.CommandVerdictHub
import dev.brickvpn.harness.vpn.PigeonVpnApiImpl
import dev.brickvpn.harness.vpn.ServiceLifecycleHub
import dev.brickvpn.harness.vpn.StateEventsStreamHandler
import dev.brickvpn.harness.vpn.TrafficStatsEventsStreamHandler
import dev.brickvpn.harness.vpn.VpnEngineHostApi
import dev.brickvpn.harness.vpn.VpnNativeState
import dev.brickvpn.harness.vpn.VpnState
import dev.brickvpn.harness.vpn.PigeonEventSink
import dev.brickvpn.harness.vpn.VpnStateEvent
import dev.brickvpn.harness.vpn.ServiceLifecycleObserver
import dev.brickvpn.harness.vpn.VpnStateMachine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.drop
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
                if (lastState != null) {
                    try {
                        s.success(VpnStateEvent(state = lastState.toNative(), errorReason = (lastState as? VpnState.Error)?.reason))
                    } catch (_: Throwable) {}
                }
            }
            collectorJob?.cancel()
            collectorJob = null
            attachedMachine = null
        }

        fun attachedMachineState(): VpnStateMachine? = attachedMachine
    }

    internal val stateHandler = PluginStateEventsStreamHandler()
    private val trafficHandler = object : TrafficStatsEventsStreamHandler() {
        // documented stub: emits nothing
    }

    internal fun attachLifecycleObserver(
        currentServiceMachine: () -> VpnStateMachine? = { BrickVpnService.current?.stateMachine },
    ) {
        ServiceLifecycleHub.observer = object : ServiceLifecycleObserver {
            override fun onCreated(machine: VpnStateMachine) {
                stateHandler.attachMachine(machine)
            }
            override fun onDestroyed() {
                val last = stateHandler.attachedMachineState()?.currentState
                stateHandler.onServiceDestroyed(last)
                coordinator?.onServiceDestroyed()
            }
        }
        currentServiceMachine()?.let { machine ->
            stateHandler.attachMachine(machine)
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