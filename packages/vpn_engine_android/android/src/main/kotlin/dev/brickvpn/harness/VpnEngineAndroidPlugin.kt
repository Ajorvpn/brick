package dev.brickvpn.harness

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import dev.brickvpn.harness.vpn.BrickVpnService
import dev.brickvpn.harness.vpn.CommandCoordinator
import dev.brickvpn.harness.vpn.CommandVerdictHub
import dev.brickvpn.harness.vpn.LibboxTunnelEngine
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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
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

    internal inner class PluginLogEventsStreamHandler : EventChannel.StreamHandler {
        private var sink: EventChannel.EventSink? = null
        private val mainHandler by lazy {
            try {
                Handler(Looper.getMainLooper())
            } catch (_: Throwable) {
                null
            }
        }

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            this.sink = events
        }

        override fun onCancel(arguments: Any?) {
            this.sink = null
        }

        fun onLog(log: String) {
            val s = sink ?: return
            val handler = mainHandler
            if (handler != null) {
                handler.post {
                    try {
                        sink?.success(log)
                    } catch (_: Throwable) {}
                }
            } else {
                try {
                    s.success(log)
                } catch (_: Throwable) {}
            }
        }
    }

    internal val stateHandler = PluginStateEventsStreamHandler()
    internal val trafficHandler = PluginTrafficStatsEventsStreamHandler()
    internal val logHandler = PluginLogEventsStreamHandler()
    private var logEventChannel: EventChannel? = null
    private var killSwitchMethodChannel: MethodChannel? = null
    private var batteryOptimizationMethodChannel: MethodChannel? = null
    private var secureStorageMethodChannel: MethodChannel? = null

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

        val logChannel = EventChannel(binding.binaryMessenger, "dev.brickvpn.harness/log_events")
        logChannel.setStreamHandler(logHandler)
        logEventChannel = logChannel
        LibboxTunnelEngine.globalLogConsumer = { log -> logHandler.onLog(log) }

        val ksChannel = MethodChannel(binding.binaryMessenger, "dev.brickvpn.harness/kill_switch")
        ksChannel.setMethodCallHandler { call, result ->
            if (call.method == "setLockdownBlocking") {
                val active = call.argument<Boolean>("active") ?: false
                BrickVpnService.setLockdown(active, ctx)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        killSwitchMethodChannel = ksChannel

        val boChannel = MethodChannel(binding.binaryMessenger, "dev.brickvpn.harness/battery_optimization")
        boChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        pm?.isIgnoringBatteryOptimizations(ctx.packageName) ?: false
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val activity = activityBinding?.activity
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:${ctx.packageName}")
                                if (activity == null) {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                            }
                            if (activity != null) {
                                activity.startActivity(intent)
                            } else {
                                ctx.startActivity(intent)
                            }
                            result.success(true)
                        } catch (_: ActivityNotFoundException) {
                            try {
                                val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                    if (activity == null) {
                                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                    }
                                }
                                if (activity != null) {
                                    activity.startActivity(fallback)
                                } else {
                                    ctx.startActivity(fallback)
                                }
                                result.success(true)
                            } catch (_: Throwable) {
                                result.success(false)
                            }
                        } catch (_: Throwable) {
                            result.success(false)
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }
        batteryOptimizationMethodChannel = boChannel

        val ssChannel = MethodChannel(binding.binaryMessenger, "dev.brickvpn.harness/secure_storage")
        ssChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "encrypt" -> {
                    val plaintext = call.argument<String>("plaintext")
                    if (plaintext == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'plaintext'", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val encrypted = SecureStorageHelper.encrypt(plaintext)
                        result.success(encrypted)
                    } catch (e: Throwable) {
                        result.error("ENCRYPTION_FAILED", e.message, null)
                    }
                }
                "decrypt" -> {
                    val ciphertext = call.argument<String>("ciphertext")
                    if (ciphertext == null) {
                        result.error("INVALID_ARGUMENT", "Missing 'ciphertext'", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val decrypted = SecureStorageHelper.decrypt(ciphertext)
                        result.success(decrypted)
                    } catch (e: Throwable) {
                        result.error("DECRYPTION_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        secureStorageMethodChannel = ssChannel

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
        LibboxTunnelEngine.globalLogConsumer = null
        logEventChannel?.setStreamHandler(null)
        logEventChannel = null
        killSwitchMethodChannel?.setMethodCallHandler(null)
        killSwitchMethodChannel = null
        batteryOptimizationMethodChannel?.setMethodCallHandler(null)
        batteryOptimizationMethodChannel = null
        secureStorageMethodChannel?.setMethodCallHandler(null)
        secureStorageMethodChannel = null
        logHandler.onCancel(null)
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

internal object SecureStorageHelper {
    private const val KEYSTORE_ALIAS = "brick_vpn_profile_master_key_v1"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding"
    private const val GCM_TAG_LENGTH_BITS = 128
    private var fallbackKey: SecretKey? = null

    fun getOrCreateKey(): SecretKey {
        return try {
            val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
            if (keyStore.containsAlias(KEYSTORE_ALIAS)) {
                (keyStore.getEntry(KEYSTORE_ALIAS, null) as KeyStore.SecretKeyEntry).secretKey
            } else {
                val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
                val spec = KeyGenParameterSpec.Builder(
                    KEYSTORE_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
                keyGenerator.init(spec)
                keyGenerator.generateKey()
            }
        } catch (_: Throwable) {
            fallbackKey ?: synchronized(this) {
                fallbackKey ?: run {
                    val kg = KeyGenerator.getInstance("AES")
                    kg.init(256)
                    kg.generateKey().also { fallbackKey = it }
                }
            }
        }
    }

    fun encrypt(plaintext: String): String {
        val secretKey = getOrCreateKey()
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey)
        val iv = cipher.iv
        val ciphertextWithTag = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        val combined = ByteArray(iv.size + ciphertextWithTag.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(ciphertextWithTag, 0, combined, iv.size, ciphertextWithTag.size)
        val b64 = base64UrlEncode(combined)
        return "enc:v1:$b64"
    }

    fun decrypt(ciphertext: String): String {
        if (!ciphertext.startsWith("enc:v1:")) {
            throw IllegalArgumentException("Invalid ciphertext prefix")
        }
        val rawB64 = ciphertext.substring("enc:v1:".length)
        val combined = base64UrlDecode(rawB64)
        if (combined.size < 12 + 16) {
            throw IllegalArgumentException("Ciphertext too short")
        }
        val iv = combined.copyOfRange(0, 12)
        val cipherBytes = combined.copyOfRange(12, combined.size)
        val secretKey = getOrCreateKey()
        val cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
        val decrypted = cipher.doFinal(cipherBytes)
        return String(decrypted, Charsets.UTF_8)
    }

    private fun base64UrlEncode(bytes: ByteArray): String {
        return try {
            android.util.Base64.encodeToString(
                bytes,
                android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING
            ).trim()
        } catch (_: Throwable) {
            java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
        }
    }

    private fun base64UrlDecode(str: String): ByteArray {
        return try {
            android.util.Base64.decode(str, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP)
        } catch (_: Throwable) {
            java.util.Base64.getUrlDecoder().decode(str)
        }
    }
}