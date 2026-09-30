package dev.brickvpn.harness.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import dev.brickvpn.harness.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Gate A `VpnService` skeleton. Wires real Android lifecycle events to the
 * P3-T5 [VpnStateMachine].
 *
 * **No libbox call is made anywhere in this class** — see the note below.
 *
 * ## Why no libbox here
 *
 * `ROADMAP.md` P3-T6 is titled "VpnService skeleton wired to the state machine
 * *(no libbox yet)*" and its Notes for Agent say to "preserve this separation
 * strictly; do not 'just wire in libbox while I'm here' even if it seems
 * convenient". The engine here is [FakeTunnelEngine]. Real libbox startup, the
 * 18-method `PlatformInterface` binding, and the TUN-fd handoff into Go are
 * **P3-T7's** job, deliberately, so a bug found in this task is unambiguously
 * an Android-lifecycle bug rather than a native-bridge bug.
 *
 * ## Threading
 *
 * `onStartCommand` / `onDestroy` / `onRevoke` run on the main thread and do
 * **no** blocking work there: descriptor establishment, descriptor close, and
 * every deferrable state-machine call run on [ioScope] ([Dispatchers.IO]).
 * The state machine is internally synchronized, so this is about not blocking
 * the main thread, not about thread-safety.
 */
class BrickVpnService : VpnService() {

    /** P3-T5 machine. Public so instrumented tests can observe real transitions. */
    val stateMachine: VpnStateMachine =
        VpnStateMachine(scope = CoroutineScope(SupervisorJob() + Dispatchers.IO))

    /** Engine seam. Always fake in P3-T6. */
    var engine: TunnelEngine = FakeTunnelEngine()

    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Survives `onDestroy` so the descriptor close is *guaranteed*: on a scope
     * cancelled during `onDestroy` the close could be skipped and the TUN
     * interface leaked — the exact legacy bug this project must not inherit.
     */
    private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * The retained TUN descriptor. Kotlin owns it; libbox (in P3-T7) receives
     * only the borrowed `fd` int. `detachFd()` is never called — see
     * `REFERENCE_ARCHITECTURE_STUDY.md` Domain 2.
     */
    @Volatile
    private var tunPfd: ParcelFileDescriptor? = null

    /** Makes the close idempotent so it happens exactly once on every path. */
    private val tunClosed = AtomicBoolean(false)

    override fun onCreate() {
        super.onCreate()
        current = this
        Log.i(TAG, "service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must be called for EVERY action, including ACTION_STOP. The framework
        // kills a service that was started with startForegroundService() and did
        // not call startForeground() within its window — which is exactly what
        // happened when ACTION_STOP skipped it:
        //   android.app.RemoteServiceException: Context.startForegroundService()
        //   did not then call Service.startForeground()
        startForegroundSafely()

        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "onStartCommand: ACTION_STOP")
                requestStop(StopReason.ACTION_STOP)
            }

            else -> {
                Log.i(TAG, "onStartCommand: start")
                requestStart()
            }
        }
        return START_STICKY
    }

    /**
     * OS-initiated VPN permission withdrawal. Per the P3-T6 architecture study
     * this maps to the dedicated `Revoked` transition, **not** to a parallel
     * teardown path — the state machine stays the single source of truth.
     */
    override fun onRevoke() {
        Log.w(TAG, "onRevoke: VPN permission withdrawn by the system")
        val token = stateMachine.activeSession
        ioScope.launch {
            if (token != null) stateMachine.onRevoke()
            runCatching { engine.stop() }
            closeTunOnce()
        }
        stopSelf()
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        // Deliberately NOT cancelling ioScope before the descriptor is closed.
        // Force a final stop, then close on cleanupScope, which outlives the
        // service. Nothing here blocks the main thread.
        val token = stateMachine.activeSession
        cleanupScope.launch {
            try {
                if (token != null && stateMachine.stop() == VpnCommandResult.Accepted) {
                    runCatching { engine.stop() }
                    stateMachine.onStopped(token)
                }
                closeTunOnce()
            } finally {
                cleanupScope.cancel()
                stateMachine.close()
            }
        }
        ioScope.cancel()
        if (current === this) current = null
        super.onDestroy()
    }


    // ------------------------------------------------------------- transitions

    private fun requestStart() {
        when (val result = stateMachine.start()) {
            VpnCommandResult.Accepted -> ioScope.launch { runStartSequence() }
            else -> Log.w(TAG, "start rejected: $result (state=${stateMachine.currentState})")
        }
    }

    /**
     * Preparing -> Starting -> Running. Mirrors the study's Domain 1 startup
     * sequence, with the fake engine standing in for `libbox`.
     */
    private suspend fun runStartSequence() {
        val token = stateMachine.activeSession ?: return
        try {
            val pfd = withContext(Dispatchers.IO) { establishTun() }
            if (pfd == null) {
                Log.e(TAG, "establish() returned null; treating as permission/revocation")
                stateMachine.onFailure(token, "establish() returned null")
                return
            }
            tunPfd = pfd
            Log.i(TAG, "TUN descriptor acquired (fd=${pfd.fd})")

            if (!stateMachine.onPreparingComplete(token)) return
            Log.i(TAG, "state -> Starting")

            engine.start(pfd.fd) // fake: fixed-delay sleep, no libbox, no network

            if (stateMachine.onRunning(token)) Log.i(TAG, "state -> Running")
        } catch (t: Throwable) {
            Log.e(TAG, "start failed: ${t.javaClass.simpleName}: ${t.message}")
            stateMachine.onFailure(token, "start failed: ${t.javaClass.simpleName}")
        }
    }

    private fun requestStop(reason: StopReason) {
        val token = stateMachine.activeSession
        ioScope.launch {
            if (token != null && stateMachine.stop() == VpnCommandResult.Accepted) {
                Log.i(TAG, "state -> Stopping (reason=$reason)")
                runCatching { engine.stop() }
                closeTunOnce()
                if (stateMachine.onStopped(token)) Log.i(TAG, "state -> Stopped")
            }
        }
        stopSelf()
    }

    /** Idempotent, off-main-thread, safe to call from any teardown path. */
    private suspend fun closeTunOnce() {
        if (!tunClosed.compareAndSet(false, true)) return
        val pfd = tunPfd ?: return
        tunPfd = null
        withContext(Dispatchers.IO) {
            runCatching { pfd.close() }
                .onSuccess { Log.i(TAG, "TUN descriptor closed") }
                .onFailure { Log.w(TAG, "descriptor close failed: ${it.message}") }
        }
    }

    // ------------------------------------------------------------------- TUN

    /**
     * Builds a deliberately **restricted** TUN. These are placeholder values, not
     * a working tunnel:
     *
     *  - Address `10.111.222.1/24` — an RFC1918 address in a range chosen to be
     *    unlikely to collide with the test device's real network.
     *  - Route `10.111.222.0/24` — the same test range only. A real tunnel uses
     *    `0.0.0.0/0`; restricting the route here means this lifecycle test
     *    cannot hijack the device's actual traffic, which matters because the
     *    engine is fake and would black-hole it.
     *  - DNS `10.111.222.2` — inside the same reserved range and therefore
     *    unroutable, so DNS cannot be perturbed.
     */
    private fun establishTun(): ParcelFileDescriptor? =
        Builder()
            .setSession("Brick VPN Gate A")
            .addAddress(TUN_ADDRESS, TUN_PREFIX)
            .addRoute(TUN_SUBNET, TUN_PREFIX)
            .addDnsServer(TUN_DNS)
            .establish()

    // ---------------------------------------------------- foreground / notification

    private fun startForegroundSafely() {
        ensureNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // API 34+ requires an explicit, manifest-declared type.
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
        )
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("Brick VPN")
            .setContentText("Tunnel active")
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
    }

    enum class StopReason { ACTION_STOP, USER_STOP, ON_DESTROY }

    companion object {
        private const val TAG = "BrickVpnService"
        private const val CHANNEL_ID = "brick_vpn_gate_a"
        private const val CHANNEL_NAME = "VPN status"
        private const val NOTIFICATION_ID = 1001
        private const val TUN_ADDRESS = "10.111.222.1"
        private const val TUN_SUBNET = "10.111.222.0"
        private const val TUN_DNS = "10.111.222.2"
        private const val TUN_PREFIX = 24

        const val ACTION_START = "dev.brickvpn.harness.action.START"
        const val ACTION_STOP = "dev.brickvpn.harness.action.STOP"

        /** The running instance, for instrumented tests. */
        @Volatile
        var current: BrickVpnService? = null
            private set
    }
}
