package dev.brickvpn.harness.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import android.net.VpnService
import kotlinx.coroutines.withContext

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
) : VpnEngineHostApi {

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

    fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            handleActivityResult(requestCode, resultCode)
        }
    }

    fun onDetachedFromActivityForConfigChanges() {}

    fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
    }

    fun onDetachedFromActivity() {
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
        if (prepareChecker(appContext) != null) return VpnCommandOutcome.REJECTED_PERMISSION_DENIED
        return coordinator.run(CommandKind.START) {
            startServiceLauncher()
        }
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