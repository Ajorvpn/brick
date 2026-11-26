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

        val outcome = coordinator.run(CommandKind.START) {
            PendingConfigHolder.put(configJson)
            try {
                startServiceLauncher()
            } catch (t: Throwable) {
                PendingConfigHolder.clearIfMatches(configJson)
                throw t
            }
        }
        if (outcome != VpnCommandOutcome.ACCEPTED) {
            PendingConfigHolder.clearIfMatches(configJson)
        }
        return outcome
    }

    internal fun buildConfigJson(outbound: Map<*, *>, isBlock: Boolean): String {
        val root = JSONObject()
        root.put("log", JSONObject().put("level", "info").put("timestamp", false))
        val inbounds = JSONArray()
        inbounds.put(
            JSONObject()
                .put("type", "tun")
                .put("tag", "tun-in")
                .put("address", JSONArray().put("10.111.222.1/24"))
                .put("mtu", 9000)
                .put("auto_route", true)
                .put("strict_route", true),
        )
        root.put("inbounds", inbounds)
        val outbounds = JSONArray()
        if (isBlock) {
            outbounds.put(JSONObject().put("type", "block").put("tag", "block-out"))
            root.put("outbounds", outbounds)
            root.put("route", JSONObject().put("auto_detect_interface", true))
        } else {
            val outboundTag = (outbound["tag"] as? String)?.takeIf { it.isNotBlank() } ?: "proxy"
            val isWireGuard = outbound["type"] == "wireguard"
            if (isWireGuard) {
                root.put("endpoints", JSONArray().put(buildWireGuardEndpoint(outbound, outboundTag)))
            } else {
                val primaryOutbound = JSONObject(outbound).put("tag", outboundTag)
                outbounds.put(primaryOutbound)
            }
            outbounds.put(JSONObject().put("type", "direct").put("tag", "direct-out"))
            root.put("outbounds", outbounds)

            // v1.14.4 typed DNS servers (`address` legacy format was removed in 1.14.0).
            // `dns-direct` omits `detour` intentionally: common/dialer/detour.go rejects
            // detouring to an empty direct outbound; default dialer routes direct via
            // route.auto_detect_interface = true.
            val dnsServers = JSONArray()
            dnsServers.put(
                JSONObject()
                    .put("type", "udp")
                    .put("tag", "dns-direct")
                    .put("server", "1.1.1.1"),
            )
            // P10-HF1 / v1.14.4 fix: plain UDP/TCP DNS is intercepted on Iranian
            // carriers, HTTP/2 DoH stalls 10.0s on dead ClientConn pools, and DoT
            // (tls) pools idle sockets across silent proxy drops causing 2s+ retries;
            // forcing HTTP/1.1 ALPN with Connection: close uses a fresh encrypted
            // DoH connection per query inside outboundTag with a bounded 4s timeout.
            dnsServers.put(
                JSONObject()
                    .put("type", "https")
                    .put("tag", "dns-remote")
                    .put("server", "1.1.1.1")
                    .put("path", "/dns-query")
                    .put("detour", outboundTag)
                    .put("headers", JSONObject().put("Connection", "close"))
                    .put(
                        "tls",
                        JSONObject()
                            .put("enabled", true)
                            .put("alpn", JSONArray().put("http/1.1")),
                    ),
            )
            val dnsObj = JSONObject()
                .put("servers", dnsServers)
                .put("final", "dns-remote")
                .put("strategy", "prefer_ipv4")
                .put("timeout", "4s")
            root.put("dns", dnsObj)

            val routeRules = JSONArray()
            routeRules.put(JSONObject().put("action", "sniff"))
            routeRules.put(
                JSONObject()
                    .put("protocol", "dns")
                    .put("action", "hijack-dns"),
            )
            root.put(
                "route",
                JSONObject()
                    .put("auto_detect_interface", true)
                    .put("default_domain_resolver", "dns-direct")
                    .put("rules", routeRules)
                    .put("final", outboundTag),
            )
        }
        return root.toString()
    }

    private fun buildWireGuardEndpoint(outbound: Map<*, *>, tag: String): JSONObject {
        val endpoint = JSONObject()
            .put("type", "wireguard")
            .put("tag", tag)
            .put("system", (outbound["system_interface"] as? Boolean) ?: false)
        (outbound["mtu"] as? Number)?.let { endpoint.put("mtu", it.toInt()) }
        (outbound["workers"] as? Number)?.let { endpoint.put("workers", it.toInt()) }
        val localAddresses = JSONArray()
        when (val rawAddr = outbound["local_address"]) {
            is Iterable<*> -> rawAddr.filterIsInstance<String>().forEach { localAddresses.put(it) }
            is Array<*> -> rawAddr.filterIsInstance<String>().forEach { localAddresses.put(it) }
            is String -> if (rawAddr.isNotBlank()) localAddresses.put(rawAddr)
        }
        endpoint.put("address", localAddresses)
        (outbound["private_key"] as? String)?.let { endpoint.put("private_key", it) }

        val peer = JSONObject()
        (outbound["server"] as? String)?.let { peer.put("address", it) }
        (outbound["server_port"] as? Number)?.let { peer.put("port", it.toInt()) }
        (outbound["peer_public_key"] as? String)?.let { peer.put("public_key", it) }
        (outbound["pre_shared_key"] as? String)?.takeIf { it.isNotBlank() }?.let {
            peer.put("pre_shared_key", it)
        }
        val reservedRaw = outbound["reserved"]
        if (reservedRaw is Iterable<*>) {
            val reserved = JSONArray()
            reservedRaw.filterIsInstance<Number>().forEach { reserved.put(it.toInt()) }
            if (reserved.length() > 0) peer.put("reserved", reserved)
        }
        peer.put("allowed_ips", JSONArray().put("0.0.0.0/0").put("::/0"))

        endpoint.put("peers", JSONArray().put(peer))
        return endpoint
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