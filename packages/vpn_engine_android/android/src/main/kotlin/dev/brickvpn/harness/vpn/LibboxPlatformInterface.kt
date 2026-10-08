package dev.brickvpn.harness.vpn

import android.util.Log
import io.nekohasekai.libbox.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.libbox.NetworkInterface
import io.nekohasekai.libbox.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.libbox.Notification
import io.nekohasekai.libbox.libbox.PlatformInterface
import io.nekohasekai.libbox.libbox.TunOptions
import io.nekohasekai.libbox.libbox.WIFIState

/**
 * The host-app side of libbox's JNI boundary: all 18 methods of
 * `io.nekohasekai.libbox.libbox.PlatformInterface`, as verified by a fresh
 * `javap` against the pinned sing-box **v1.10.7** AAR for P3-T7.
 *
 * ## Why most of this is deliberately inert
 *
 * libbox calls into this interface to ask the *host platform* for things Go
 * cannot do itself. Most of those questions only have meaning for features
 * Brick VPN does not have in Gate A, so answering them is not an oversight --
 * it is the scoping decision. Every stub below carries its reason inline.
 *
 * The three that are real for this task:
 *
 *  - [openTun] -- **real**: hands libbox the descriptor `VpnService` established.
 *  - [writeLog] -- **real**: routes Go-side logging to logcat.
 *  - [readWIFIState] -- **real but minimal**: an empty state, because
 *    `BoxService.needWIFIState()` is what decides whether it is consulted.
 *
 * Since P3-T7 Part 2 a fourth is real and load-bearing:
 *
 *  - [autoDetectInterfaceControl] -- **real**: excludes libbox's outbound sockets
 *    from this app's TUN, and is mandatory for any broad (`0.0.0.0/0`) route.
 *
 * ## FD ownership (Domain 2)
 *
 * [openTun] returns a **borrowed** `Int`. It does not `dup()`, does not take
 * ownership, and never calls `detachFd()`. The `ParcelFileDescriptor` stays
 * owned by [BrickVpnService], which closes it exactly once in `closeTunOnce()`.
 * libbox uses the descriptor only for the lifetime of the `BoxService`.
 *
 * ## Secrets
 *
 * `SECURITY.md`: nothing here may log a credential. The only strings reaching
 * logcat are libbox's own diagnostics plus TUN metadata. This task's config is
 * a `block` outbound and therefore holds no server, UUID, or password at all.
 */
class LibboxPlatformInterface(
    /**
     * Supplies the borrowed TUN descriptor on demand.
     *
     * A provider rather than a captured `Int` so the engine can invalidate it
     * on teardown: after `BoxService.close()` a late [openTun] must fail
     * loudly instead of resurrecting a closed descriptor.
     */
    private val tunFdProvider: () -> Int,

    /**
     * Excludes one of libbox's outbound sockets from the TUN this app owns.
     *
     * Supplied by [BrickVpnService] as `{ fd -> protect(fd) }`. This is the
     * mechanism that makes a `0.0.0.0/0` route survivable: without it, the
     * connection libbox opens *to the proxy server* is itself routed back into
     * the TUN that libbox created, and the tunnel deadlocks on its own first
     * packet.
     *
     * A provider, not a captured service reference, so a test can inject a
     * recording double and assert the callback actually fires.
     */
    private val socketProtector: (Int) -> Unit,
) : PlatformInterface {

    // ------------------------------------------------------------- 1. routing

    /**
     * (2) The platform has no auto interface-control path at Gate A.
     *
     * Returning `false` tells libbox to do its own interface detection. That is
     * both correct and required: [autoDetectInterfaceControl] is inert, so
     * *claiming* support while not implementing it would silently break
     * routing. Same reasoning as [useProcFS].
     */
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    /**
     * (1) REAL, and load-bearing.
     *
     * Returning `true` opts into libbox's per-socket protection path. In pinned
     * sing-box v1.10.7, `Router.AutoDetectInterfaceFunc()` (`route/router.go`)
     * then installs a `control.Func` on every outbound dialer that hands the raw
     * socket fd to this method; the reference Android client
     * (`sing-box-for-android`) implements this exact method as `protect(fd)`.
     *
     * Previously this returned `false` and the method was an inert log line. That
     * was correct only because the Gate A route is restricted to the test
     * subnet, so no real outbound ever needed exempting. It is **not** correct for
     * a full `0.0.0.0/0` route.
     *
     * Note the gate has two halves: this method must be `true` **and** the config
     * must set `route.auto_detect_interface = true` (`option/route.go`). If either
     * is missing libbox silently falls back to interface-based binding and this
     * method is never called.
     */
    override fun autoDetectInterfaceControl(networkIndex: Int) {
        socketProtector(networkIndex)
        Log.i(TAG, "autoDetectInterfaceControl: excluded outbound fd=$networkIndex from TUN")
    }

    /**
     * (5) Per-UID route resolution is not implemented.
     *
     * `false` means libbox will not ask the platform which UID owns a
     * connection, so the three per-app methods below are never reached. Gate A
     * has no per-app split tunnelling.
     */
    override fun useProcFS(): Boolean = false

    /**
     * (6) Not called, because [useProcFS] is `false`. Returns [NO_OWNER]
     * rather than throwing: a throw here would abort libbox startup from
     * inside a JNI callback, which is unrecoverable on the Go side.
     */
    override fun findConnectionOwner(
        protocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): Int = NO_OWNER

    /**
     * (7) Not called, because [useProcFS] is `false`. An empty string is the
     * benign "unknown" answer; the raw `uid` is deliberately not logged.
     */
    override fun packageNameByUid(uid: Int): String = ""

    /**
     * (8) Not called, because [useProcFS] is `false`. Returns [UID_NOT_FOUND]
     * for the same non-throwing reason as [findConnectionOwner].
     */
    override fun uidByPackageName(packageName: String): Int = UID_NOT_FOUND

    // ---------------------------------------------------------- 2. the TUN fd

    /**
     * (3) THE real method: hands libbox the descriptor that
     * `VpnService.Builder.establish()` produced.
     *
     * [options] is the TUN configuration libbox would like applied. `VpnService`
     * has already established and configured the interface, and Gate A's TUN is
     * deliberately restricted to one test subnet, so the settings are logged
     * for diagnosis and **not** re-applied -- doing so could widen the route
     * past the intended test range.
     *
     * Throws when no descriptor is currently lent: after teardown this must
     * fail rather than hand out a stale `Int`.
     */
    override fun openTun(options: TunOptions): Int {
        val fd = tunFdProvider()
        // Explicit getter calls, not property syntax: Kotlin only synthesizes
        // properties for Java *classes*, not for methods declared on a Java
        // interface, and `TunOptions` is an interface. `options.getMTU()` is
        // therefore the only spelling that compiles here.
        Log.i(
            TAG,
            "openTun: lending fd=$fd (mtu=${options.getMTU()}, " +
                "autoRoute=${options.getAutoRoute()}, " +
                "strictRoute=${options.getStrictRoute()})",
        )
        return fd
    }

    // --------------------------------------------------------- 3. diagnostics

    /**
     * (4) Real: a libbox log line, forwarded to logcat.
     *
     * The text is libbox's own. This task's config is a `block` outbound and so
     * carries no credential, leaving nothing to redact here. A future config
     * with a real server must be redacted upstream per `SECURITY.md` -- tracked
     * in `PROJECT_STATE.md` Section 6.
     */
    override fun writeLog(log: String) {
        Log.i(TAG, "libbox: $log")
    }

    // ------------------------------------------------------------ 4. handover

    /**
     * (9) The platform does not drive libbox's default-interface monitor at
     * Gate A; libbox runs its own, so the callback pair below stays inert.
     */
    override fun usePlatformDefaultInterfaceMonitor(): Boolean = false

    /** (10) Not called: [usePlatformDefaultInterfaceMonitor] is `false`. */
    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        Log.w(TAG, "startDefaultInterfaceMonitor called despite capability=false")
    }

    /** (11) Not called: [usePlatformDefaultInterfaceMonitor] is `false`. */
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        Log.w(TAG, "closeDefaultInterfaceMonitor called despite capability=false")
    }

    /** (12) libbox enumerates interfaces itself, so [getInterfaces] is unused. */
    override fun usePlatformInterfaceGetter(): Boolean = false

    /**
     * (13) Not called, because [usePlatformInterfaceGetter] is `false`.
     *
     * An empty iterator rather than a throw: if libbox ever does call it, an
     * empty list degrades to "libbox found nothing" rather than killing the
     * process from inside a JNI callback.
     */
    override fun getInterfaces(): NetworkInterfaceIterator = EMPTY_INTERFACES

    // ------------------------------------------------------------- 5. platform

    /**
     * (14) A true value, not a stub: this is an Android app and never an iOS
     * Network Extension. `false` is the truthful answer on every platform this
     * harness runs on.
     */
    override fun underNetworkExtension(): Boolean = false

    /**
     * (15) iOS-only concept (whether an NE provider may include all networks).
     * `false` is the correct Android answer and makes libbox ignore the field.
     */
    override fun includeAllNetworks(): Boolean = false

    /**
     * (16) An empty WIFI state rather than a throw.
     *
     * `BoxService.needWIFIState()` is the gate libbox uses before consulting
     * this, and a `block`-only config has no SSID-dependent routing, so an
     * empty value is both sufficient and safe. Throwing here would be the
     * legacy "abort at the JNI boundary" failure mode in reverse.
     */
    override fun readWIFIState(): WIFIState = WIFIState(EMPTY_SSID, EMPTY_BSSID)

    /**
     * (17) Inert. The Gate A config defines no DNS rules, so there is no cache
     * to clear. Logged rather than silently ignored so an unexpected call is
     * visible in review.
     */
    override fun clearDNSCache() {
        Log.i(TAG, "clearDNSCache called; no DNS rules in the Gate A config")
    }

    // ------------------------------------------------------------------ 6. UI

    /**
     * (18) Inert by design.
     *
     * libbox asks the host to raise user-facing notifications. At Gate A the
     * only user-facing surface is `BrickVpnService`'s own foreground
     * notification, which the service manages directly; honouring this too
     * would produce two competing notifications. The identifier is logged for
     * diagnosis but nothing is rendered.
     */
    override fun sendNotification(notification: Notification) {
        Log.i(TAG, "sendNotification: id=${notification.identifier} ignored by design")
    }

    companion object {
        private const val TAG = "LibboxPlatformInterface"

        /** "No owning UID" sentinel for [findConnectionOwner]. */
        private const val NO_OWNER = -1

        /** "UID not found" sentinel for [uidByPackageName]. */
        private const val UID_NOT_FOUND = -1

        private const val EMPTY_SSID = ""
        private const val EMPTY_BSSID = ""

        /** An always-exhausted [NetworkInterfaceIterator] for [getInterfaces]. */
        private val EMPTY_INTERFACES = object : NetworkInterfaceIterator {
            override fun hasNext(): Boolean = false
            override fun next(): NetworkInterface = throw NoSuchElementException("empty")
        }
    }
}
