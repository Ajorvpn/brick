package dev.brickvpn.harness.vpn

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import android.net.VpnService
import kotlinx.coroutines.cancel
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
) : VpnEngineHostApi, ActivityAware {

    @Volatile
    private var activity: Activity? = activityProvider()

    private var activityBinding: ActivityPluginBinding? = null

    private val prepareLock = Any()
    private var pendingPrepare: CompletableDeferred<VpnConsentStatus>? = null
    private var currentRequestCode: Int = 0

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener { requestCode, resultCode, _ ->
            if (requestCode != currentRequestCode || pendingPrepare == null) return@addActivityResultListener false
            val outcome = if (resultCode == Activity.RESULT_OK) VpnConsentStatus.GRANTED else VpnConsentStatus.DENIED
            synchronized(prepareLock) {
                pendingPrepare?.complete(outcome)
                pendingPrepare = null
            }
            true
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
            act.startActivityForResult(intent, currentRequestCode)
        }
        return deferred.await()
    }

    override suspend fun start(profileJson: Map<String, Any?>): VpnCommandOutcome {
        if (profileJson.isEmpty()) return VpnCommandOutcome.REJECTED_INVALID_CONFIG
        if (prepareChecker(appContext) != null) return VpnCommandOutcome.REJECTED_PERMISSION_DENIED
        return coordinator.run(CommandKind.START) {
            val intent = Intent(appContext, BrickVpnService::class.java).setAction(BrickVpnService.ACTION_START)
            ContextCompat.startForegroundService(appContext, intent)
        }
    }

    override suspend fun stop(): VpnCommandOutcome {
        if (BrickVpnService.current == null) {
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            val machine = VpnStateMachine(scope = scope)
            val result = machine.stop()
            scope.cancel()
            return result.toOutcome()
        }
        return coordinator.run(CommandKind.STOP) {
            val intent = Intent(appContext, BrickVpnService::class.java).setAction(BrickVpnService.ACTION_STOP)
            appContext.startService(intent)
        }
    }

    override fun getStatus(): VpnStateEvent {
        val state = BrickVpnService.current?.stateMachine?.currentState
            ?: VpnStateMachine().currentState
        return VpnStateEvent(
            state = state.toNativeState(),
            errorReason = (state as? VpnState.Error)?.reason,
        )
    }

    private fun VpnCommandResult.toOutcome(): VpnCommandOutcome = when (this) {
        VpnCommandResult.Accepted -> VpnCommandOutcome.ACCEPTED
        VpnCommandResult.RejectedBusy -> VpnCommandOutcome.REJECTED_BUSY
        VpnCommandResult.RejectedInvalidConfig -> VpnCommandOutcome.REJECTED_INVALID_CONFIG
        VpnCommandResult.RejectedPermissionDenied -> VpnCommandOutcome.REJECTED_PERMISSION_DENIED
        VpnCommandResult.Failed -> VpnCommandOutcome.FAILED
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