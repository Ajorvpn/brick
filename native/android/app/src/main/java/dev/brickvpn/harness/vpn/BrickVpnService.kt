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
import java.util.concurrent.atomic.AtomicReference

/**
 * Gate A `VpnService`. Wires real Android lifecycle events to the P3-T5
 * [VpnStateMachine], and (since P3-T7) to a real libbox instance.
 *
 * ## P3-T6 -> P3-T7: the engine changed, the lifecycle did not
 *
 * P3-T6 ran [FakeTunnelEngine], so `Running` meant "a timer elapsed". P3-T7
 * replaces it with [LibboxTunnelEngine], so `Running` means "libbox actually
 * started". What deliberately did **not** change is the shape of this class:
 * it still owns the Android objects, still borrows a descriptor rather than
 * taking it, and still delegates every decision to [VpnStateMachine]. That
 * separation is what made P3-T6's bugs attributable to the Android layer
 * instead of the native bridge, and it is why swapping the engine was a
 * one-line change here rather than a rewrite.
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

    /**
     * Engine seam. A real [LibboxTunnelEngine] since P3-T7.
     *
     * Still a `var` so a test can inject [FakeTunnelEngine] to exercise the
     * Android layer without libbox; production never overrides it.
     */
    var engine: TunnelEngine = LibboxTunnelEngine()

    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * Survives `onDestroy` so the descriptor close is *guaranteed*: on a scope
     * cancelled during `onDestroy` the close could be skipped and the TUN
     * interface leaked — the exact legacy bug this project must not inherit.
     */
    private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /**
     * The retained TUN descriptor. Kotlin owns it; libbox receives only the
     * borrowed `fd` int, which `LibboxPlatformInterface.openTun` hands back to
     * Go and `LibboxTunnelEngine` invalidates before teardown.
     * `detachFd()` is never called — see `REFERENCE_ARCHITECTURE_STUDY.md`
     * Domain 2.
     *
     * ## Why an `AtomicReference` and not a flag + field
     *
     * This was previously a `@Volatile var` beside a one-shot `AtomicBoolean`
     * "already closed" flag, and that pair **leaked a descriptor** on the
     * start/stop race, observed on-device during P3-T7:
     *
     * ```
     * ACTION_STOP -> state -> Stopping -> state -> Stopped   // close runs, tunPfd is null
     * TUN descriptor acquired (fd=67)                        // in-flight start, too late
     * ```
     *
     * The teardown consumed the one-shot flag while `tunPfd` was still `null`,
     * then the racing `runStartSequence` published a descriptor that no future
     * `closeTunOnce()` could ever release — the flag was permanently spent.
     *
     * An `AtomicReference` makes the close a **claim on the descriptor itself**
     * via [getAndSet]: whichever caller observes a descriptor closes it, exactly
     * once, and a descriptor published *after* an earlier close is still
     * released. There is no global flag to spend prematurely.
     */
    private val tunPfd = AtomicReference<ParcelFileDescriptor?>(null)

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
            stopEngine(StopReason.USER_STOP)
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
                    stopEngine(StopReason.ON_DESTROY)
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
     * sequence, driving the real `libbox` engine since P3-T7.
     *
     * ## The start/stop race (a real descriptor leak this sequence now closes)
     *
     * A stop can arrive while `establish()` is still in flight. The machine
     * correctly lands on `Stopped`, the teardown's [closeTunOnce] finds no
     * descriptor yet, and then this sequence acquires one — which, before the
     * [tunPfd] fix, could never be released. The `onPreparingComplete` check
     * below is therefore not just a legality guard: when it is refused, this
     * sequence owns a descriptor nobody else will close, so it releases it.
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
            tunPfd.set(pfd)
            Log.i(TAG, "TUN descriptor acquired (fd=${pfd.fd})")

            if (!stateMachine.onPreparingComplete(token)) {
                // The session was superseded while establish() was in flight (a
                // stop arrived first), so `Stopped -> Starting` is *refused* --
                // correctly. This descriptor belongs to a dead session and is
                // nobody else's to release, so release it here.
                Log.i(TAG, "start superseded before Running; releasing TUN descriptor")
                closeTunOnce()
                return
            }
            Log.i(TAG, "state -> Starting")

            engine.start(pfd.fd) // real: Libbox.newService(...) + BoxService.start()

            if (stateMachine.onRunning(token)) Log.i(TAG, "state -> Running")
        } catch (t: Throwable) {
            // The reason must be SPECIFIC (ROADMAP P3-T7 "Notes for Agent"): the
            // bare class name `proxyerror` is only gomobile's proxy wrapper and
            // says nothing about the cause. The real Go error travels in the
            // message -- observed on-device as "pre-start cache file: open
            // cache.db: read-only file system" -- so it belongs in the state's
            // reason, not only in the log line.
            val reason = "start failed: ${t.javaClass.simpleName}: ${t.message}"
            Log.e(TAG, reason)
            stateMachine.onFailure(token, reason)
        }
    }

    private fun requestStop(reason: StopReason) {
        val token = stateMachine.activeSession
        ioScope.launch {
            if (token != null && stateMachine.stop() == VpnCommandResult.Accepted) {
                Log.i(TAG, "state -> Stopping (reason=$reason)")
                stopEngine(reason)
                closeTunOnce()
                if (stateMachine.onStopped(token)) Log.i(TAG, "state -> Stopped")
            }
        }
        stopSelf()
    }

    /**
     * Stops the engine, logging — rather than swallowing — a teardown failure.
     *
     * These paths (`ACTION_STOP`, `onRevoke`, `onDestroy`) all run after the
     * state machine has already committed to a terminal state, and
     * `Stopping -> Error` is *illegal* in the normative graph, so a teardown
     * failure cannot be reported as `Error` without coercing an impossible
     * transition. It must therefore be observable somewhere, and logcat is that
     * somewhere: the ROADMAP's "do not silently swallow any libbox error" rule
     * applies to `runCatching { … }` just as much as to a bare try/catch.
     */
    private suspend fun stopEngine(reason: StopReason) {
        runCatching { engine.stop() }
            .onFailure {
                Log.w(
                    TAG,
                    "engine stop failed (reason=$reason): " +
                        "${it.javaClass.simpleName}: ${it.message}",
                )
            }
    }

    /** Idempotent, off-main-thread, safe to call from any teardown path. */
    private suspend fun closeTunOnce() {
        // Atomic claim: exactly one caller wins the descriptor, so a double
        // teardown cannot double-close, and — critically — a descriptor
        // published by a racing start *after* an earlier close is still
        // released rather than stranded (see the [tunPfd] KDoc).
        val pfd = tunPfd.getAndSet(null) ?: return
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
     *    cannot hijack the device's actual traffic. That matters even with the
     *    real libbox engine: the Gate A config's only outbound is `block`, so
     *    anything routed here would be silently discarded rather than proxied.
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
