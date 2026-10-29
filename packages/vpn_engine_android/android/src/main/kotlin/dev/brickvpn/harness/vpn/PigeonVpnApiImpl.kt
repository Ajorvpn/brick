package dev.brickvpn.harness.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import android.net.VpnService
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * P3-T13 Part B: thin adapter from the Pigeon host API to the proven Gate A
 * seams. Contains no lifecycle logic beyond argument translation and delegation.
 */
class PigeonVpnApiImpl(
    private val appContext: Context,
    private val coordinator: CommandCoordinator,
    private val prepareChecker: (Context) -> Intent? = { VpnService.prepare(it) },
    activityProvider: () -> Activity? = { null },
    private val stateProvider: () -> VpnState = {
        BrickVpnService.current?.stateMachine?.currentState ?: VpnState.Idle
    },
    private val startServiceLauncher: () -> Unit = {
        ContextCompat.startForegroundService(
            appContext,
            Intent(appContext, BrickVpnService::class.java).setAction(BrickVpnService.ACTION_START),
        )
    },
    private val stopServiceLauncher: () -> Unit = {
        appContext.startService(
            Intent(appContext, BrickVpnService::class.java).setAction(BrickVpnService.ACTION_STOP),
        )
    },
    private val activityStarter: (Activity, Intent, Int) -> Unit = { act, intent, requestCode ->
        act.startActivityForResult(intent, requestCode)
    },
) : VpnEngineHostApi, ActivityAware {

    @Volatile
    private var activity: Activity? = activityProvider()

    private var activityBinding: ActivityPluginBinding? = null

    private val prepareLock = Any()
    private var pendingPrepare: CompletableDeferred<VpnConsentStatus>? = null
    private var currentRequestCode: Int = 0

    fun handleActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != currentRequestCode || pendingPrepare == null) return false
        val outcome = if (resultCode == Activity.RESULT_OK) VpnConsentStatus.GRANTED else VpnConsentStatus.DENIED
        synchronized(prepareLock) {
            pendingPrepare?.complete(outcome)
            pendingPrepare = null
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            handleActivityResult(requestCode, resultCode)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        synchronized(prepareLock) {
            pendingPrepare?.complete(VpnConsentStatus.DENIED)
            pendingPrepare = null
        }
        activity = null
        activityBinding = null
    }

    override suspend fun prepare(): VpnConsentStatus {
        val intent = prepareChecker(appContext)
        if (intent == null) return VpnConsentStatus.ALREADY_GRANTED

        val deferred: CompletableDeferred<VpnConsentStatus>
        val isNew: Boolean
        synchronized(prepareLock) {
            val existing = pendingPrepare
            if (existing != null) {
                deferred = existing
                isNew = false
            } else {
                deferred = CompletableDeferred()
                pendingPrepare = deferred
                isNew = true
                currentRequestCode = (currentRequestCode + 1) and 0x7fffffff
            }
        }

        if (!isNew) return deferred.await()

        val act = activity
        if (act == null) {
            synchronized(prepareLock) { pendingPrepare = null }
            deferred.complete(VpnConsentStatus.NO_ACTIVITY)
            return VpnConsentStatus.NO_ACTIVITY
        }

        withContext(Dispatchers.Main.immediate) {
            activityStarter(act, intent, currentRequestCode)
        }
        return deferred.await()
    }

    override suspend fun start(profileJson: Map<String, Any?>): VpnCommandOutcome {
        if (profileJson.isEmpty()) return VpnCommandOutcome.REJECTED_INVALID_CONFIG
        val outbound = profileJson["outbound"] as? Map<*, *>
        if (outbound == null || outbound.isEmpty()) return VpnCommandOutcome.REJECTED_INVALID_CONFIG
        if (prepareChecker(appContext) != null) return VpnCommandOutcome.REJECTED_PERMISSION_DENIED

        val isBlock = outbound["type"] == "block"
        val configJson = buildConfigJson(outbound, isBlock)

        return coordinator.run(CommandKind.START) {
            PendingConfigHolder.put(configJson)
            startServiceLauncher()
        }
    }

    private fun buildConfigJson(outbound: Map<*, *>, isBlock: Boolean): String {
        val root = JSONObject()
        root.put("log", JSONObject().put("level", "info").put("timestamp", false))
        val inbounds = JSONArray()
        inbounds.put(
            JSONObject()
                .put("type", "tun")
                .put("tag", "tun-in")
                .put("address", JSONArray().put("10.111.222.1/24"))
                .put("mtu", 9000),
        )
        root.put("inbounds", inbounds)
        val outbounds = JSONArray()
        if (isBlock) {
            outbounds.put(JSONObject().put("type", "block").put("tag", "block-out"))
            root.put("outbounds", outbounds)
            root.put("route", JSONObject().put("auto_detect_interface", true))
        } else {
            val outboundTag = (outbound["tag"] as? String)?.takeIf { it.isNotBlank() } ?: "proxy"
            val primaryOutbound = JSONObject(outbound).put("tag", outboundTag)
            outbounds.put(primaryOutbound)
            outbounds.put(JSONObject().put("type", "direct").put("tag", "direct-out"))
            root.put("outbounds", outbounds)

            val dnsServers = JSONArray()
            dnsServers.put(
                JSONObject()
                    .put("address", "1.1.1.1")
                    .put("tag", "dns-direct")
                    .put("detour", "direct-out"),
            )
            root.put("dns", JSONObject().put("servers", dnsServers))
            root.put(
                "route",
                JSONObject()
                    .put("auto_detect_interface", true)
                    .put("final", outboundTag),
            )
        }
        return root.toString()
    }

    override suspend fun stop(): VpnCommandOutcome {
        return when (stateProvider()) {
            VpnState.Idle,
            VpnState.Stopped,
            VpnState.Stopping,
            VpnState.Revoked -> VpnCommandOutcome.REJECTED_BUSY

            VpnState.Preparing,
            VpnState.Starting,
            VpnState.Running,
            is VpnState.Error -> coordinator.run(CommandKind.STOP) {
                stopServiceLauncher()
            }
        }
    }

    override fun getStatus(): VpnStateEvent {
        val state = stateProvider()
        return VpnStateEvent(
            state = state.toNativeState(),
            errorReason = (state as? VpnState.Error)?.reason,
        )
    }

    private fun VpnState.toNativeState(): VpnNativeState = when (this) {
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