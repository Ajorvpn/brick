package dev.brickvpn.harness.vpn

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/**
 * P3-T13 Part B: serialises Pigeon commands so that at most ONE is in flight
 * at any time.
 *
 * - A second command arriving while one is pending returns
 *   [VpnCommandOutcome.REJECTED_BUSY] immediately, with no queue.
 * - The verdict listener is installed BEFORE [sendIntent] runs.
 * - A [CompletableDeferred] is completed only from a verdict of the SAME kind.
 * - A 10_000 ms timeout returns [VpnCommandOutcome.FAILED] (never an
 *   unobserved verdict).
 * - If [sendIntent] throws, returns [VpnCommandOutcome.FAILED].
 * - If the service is destroyed while a command is pending and no verdict
 *   arrived, completes with [VpnCommandOutcome.FAILED] immediately.
 * - The listener is always cleared in `finally`.
 * - Verdicts arriving with nothing pending are ignored.
 */
class CommandCoordinator(
    private val setListener: (( (CommandKind, VpnCommandResult) -> Unit)? ) -> Unit,
    private val mainDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
    private val timeoutMillis: Long = TIMEOUT_MILLIS,
) {

    private val lock = Any()
    private var pendingKind: CommandKind? = null
    private var deferred: CompletableDeferred<VpnCommandOutcome>? = null

    /** Called by the plugin when [ServiceLifecycleHub] reports destruction. */
    fun onServiceDestroyed() {
        synchronized(lock) {
            deferred?.complete(VpnCommandOutcome.FAILED)
        }
    }

    suspend fun run(
        kind: CommandKind,
        sendIntent: suspend () -> Unit,
    ): VpnCommandOutcome {
        // At most one pending command.
        synchronized(lock) {
            if (pendingKind != null) {
                return VpnCommandOutcome.REJECTED_BUSY
            }
            pendingKind = kind
            deferred = CompletableDeferred()
        }

        val d = deferred!!
        val listener: (CommandKind, VpnCommandResult) -> Unit = { k, r ->
            if (k == kind) {
                val stillPending = synchronized(lock) { pendingKind == kind }
                if (stillPending) {
                    d.complete(r.toOutcome())
                }
            }
        }

        setListener(listener)
        try {
            // Install listener already done above (before sendIntent).
            val sendResult: VpnCommandOutcome? = try {
                sendIntent()
                null
            } catch (t: Throwable) {
                VpnCommandOutcome.FAILED
            }
            if (sendResult != null) {
                return sendResult
            }

            val outcome = withTimeoutOrNull(timeoutMillis) {
                withContext(mainDispatcher) { d.await() }
            }
            return outcome ?: VpnCommandOutcome.FAILED
        } finally {
            synchronized(lock) {
                pendingKind = null
                deferred = null
            }
            setListener(null)
        }
    }

    private fun VpnCommandResult.toOutcome(): VpnCommandOutcome = when (this) {
        VpnCommandResult.Accepted -> VpnCommandOutcome.ACCEPTED
        VpnCommandResult.RejectedBusy -> VpnCommandOutcome.REJECTED_BUSY
        VpnCommandResult.RejectedInvalidConfig -> VpnCommandOutcome.REJECTED_INVALID_CONFIG
        VpnCommandResult.RejectedPermissionDenied -> VpnCommandOutcome.REJECTED_PERMISSION_DENIED
        VpnCommandResult.Failed -> VpnCommandOutcome.FAILED
    }

    companion object {
        const val TIMEOUT_MILLIS: Long = 10_000L
    }
}