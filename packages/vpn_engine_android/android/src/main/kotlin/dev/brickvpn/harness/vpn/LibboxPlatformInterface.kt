package dev.brickvpn.harness.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.util.Log
import io.nekohasekai.libbox.libbox.BridgeOptions
import io.nekohasekai.libbox.libbox.BridgeSession
import io.nekohasekai.libbox.libbox.ConnectionOwner
import io.nekohasekai.libbox.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.LocalDNSTransport
import io.nekohasekai.libbox.libbox.NeighborUpdateListener
import io.nekohasekai.libbox.libbox.NetworkInterface
import io.nekohasekai.libbox.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.libbox.Notification
import io.nekohasekai.libbox.libbox.PlatformInterface
import io.nekohasekai.libbox.libbox.PlatformUser
import io.nekohasekai.libbox.libbox.ShellSession
import io.nekohasekai.libbox.libbox.StringIterator
import io.nekohasekai.libbox.libbox.TunOptions
import io.nekohasekai.libbox.libbox.WIFIState

/**
 * Host-app implementation of `io.nekohasekai.libbox.libbox.PlatformInterface`
 * for sing-box **v1.14.4** (all 26 JNI methods).
 *
 * In v1.14.4, `experimental/libbox/service.go` hardcodes
 * `UsePlatformDefaultInterfaceMonitor() == true` and
 * `UsePlatformNetworkInterfaces() == true`, so [startDefaultInterfaceMonitor]
 * and [getInterfaces] are backed by real Android [ConnectivityManager] calls
 * (with `java.net.NetworkInterface` fallbacks when `context == null` or if an
 * isolated test APK lacks `ACCESS_NETWORK_STATE`).
 */
class LibboxPlatformInterface(
    private val context: Context? = null,
    private val tunFdProvider: () -> Int,
    private val socketProtector: (Int) -> Unit,
) : PlatformInterface {

    @Volatile
    private var myTunName: String = ""

    private val monitorLock = Any()
    private var interfaceListener: InterfaceUpdateListener? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // ------------------------------------------------------------- 1. routing

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        socketProtector(fd)
        Log.i(TAG, "autoDetectInterfaceControl: excluded outbound fd=$fd from TUN")
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner = ConnectionOwner().apply {
        // Go dereferences result.UserId without a nil guard; never return null.
        userId = NO_OWNER
    }

    // ---------------------------------------------------------- 2. the TUN fd

    override fun openTun(options: TunOptions): Int {
        val fd = tunFdProvider()
        Log.i(
            TAG,
            "openTun: lending fd=$fd (mtu=${options.getMTU()}, " +
                "autoRoute=${options.getAutoRoute()}, " +
                "strictRoute=${options.getStrictRoute()})",
        )
        return fd
    }

    override fun registerMyInterface(name: String) {
        myTunName = name
        Log.i(TAG, "registerMyInterface: $name")
    }

    // ------------------------------------------------------------- 3. network & handover

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        synchronized(monitorLock) {
            interfaceListener = listener
            val cm = connectivityManagerOrNull()
            if (cm == null) {
                emitFallbackDefaultInterface(listener)
                return
            }

            // Deliver current physical default interface immediately without waiting for callback.
            runCatching { emitCurrentDefaultInterface(cm, listener) }
                .onFailure {
                    Log.w(TAG, "initial ConnectivityManager inspection failed: ${it.message}")
                    emitFallbackDefaultInterface(listener)
                }

            val existing = networkCallback
            if (existing != null) {
                runCatching { cm.unregisterNetworkCallback(existing) }
            }

            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    notifyNetworkUpdate(cm, listener)
                }

                override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                    notifyNetworkUpdate(cm, listener)
                }

                override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                    notifyNetworkUpdate(cm, listener)
                }

                override fun onLost(network: Network) {
                    notifyNetworkUpdate(cm, listener, allowClear = true)
                }
            }

            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                .build()

            runCatching {
                cm.registerNetworkCallback(request, callback)
                networkCallback = callback
            }.onFailure {
                Log.w(TAG, "registerNetworkCallback failed: ${it.message}")
                networkCallback = null
                emitFallbackDefaultInterface(listener)
            }
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        synchronized(monitorLock) {
            val cm = connectivityManagerOrNull()
            val cb = networkCallback
            if (cm != null && cb != null) {
                runCatching { cm.unregisterNetworkCallback(cb) }
                    .onFailure { Log.w(TAG, "unregisterNetworkCallback failed: ${it.message}") }
            }
            networkCallback = null
            interfaceListener = null
        }
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val list = mutableListOf<NetworkInterface>()
        val seenNames = HashSet<String>()
        val cm = connectivityManagerOrNull()

        if (cm != null) {
            runCatching {
                @Suppress("DEPRECATION")
                val networks = cm.allNetworks
                for (network in networks) {
                    val caps = cm.getNetworkCapabilities(network) ?: continue
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                    val lp = cm.getLinkProperties(network) ?: continue
                    val name = lp.interfaceName ?: continue
                    if (isTunInterfaceName(name) || !seenNames.add(name)) continue
                    val javaNi = runCatching { java.net.NetworkInterface.getByName(name) }.getOrNull() ?: continue
                    list.add(buildLibboxInterface(javaNi, caps, lp))
                }
            }.onFailure {
                Log.w(TAG, "ConnectivityManager.allNetworks failed: ${it.message}")
            }
        }

        if (list.isEmpty()) {
            runCatching {
                val enumeration = java.net.NetworkInterface.getNetworkInterfaces()
                while (enumeration != null && enumeration.hasMoreElements()) {
                    val javaNi = enumeration.nextElement()
                    val name = javaNi.name ?: continue
                    if (isTunInterfaceName(name) || !seenNames.add(name)) continue
                    val isUp = runCatching { javaNi.isUp }.getOrDefault(false)
                    if (!isUp) continue
                    list.add(buildLibboxInterface(javaNi, caps = null, lp = null))
                }
            }.onFailure {
                Log.w(TAG, "NetworkInterface enumeration failed: ${it.message}")
            }
        }

        return NetworkInterfaceListIterator(list)
    }

    // ------------------------------------------------------------- 4. DNS & platform

    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState = WIFIState(EMPTY_SSID, EMPTY_BSSID)

    override fun clearDNSCache() {
        Log.i(TAG, "clearDNSCache called")
    }

    // ------------------------------------------------------------- 5. notifications & neighbor

    override fun sendNotification(notification: Notification) {
        Log.i(TAG, "sendNotification: id=${notification.identifier} ignored by design")
    }

    override fun cancelNotification(identifier: String, typeID: Int) {
        Log.i(TAG, "cancelNotification: id=$identifier typeID=$typeID ignored by design")
    }

    override fun startNeighborMonitor(listener: NeighborUpdateListener) {
        // Not used on Android client.
    }

    override fun closeNeighborMonitor(listener: NeighborUpdateListener) {
        // Not used on Android client.
    }

    // ------------------------------------------------------------- 6. shell & bridge (unused)

    override fun usePlatformShell(): Boolean = false

    override fun checkPlatformShell() {
        throw UnsupportedOperationException("Not supported on Android client")
    }

    override fun openShellSession(
        user: PlatformUser,
        command: String,
        environ: StringIterator,
        term: String,
        rows: Int,
        cols: Int,
    ): ShellSession {
        throw UnsupportedOperationException("Not supported on Android client")
    }

    override fun lookupUser(username: String): PlatformUser {
        throw UnsupportedOperationException("Not supported on Android client")
    }

    override fun lookupSFTPServer(): String {
        throw UnsupportedOperationException("Not supported on Android client")
    }

    override fun readSystemSSHHostKey(): String {
        throw UnsupportedOperationException("Not supported on Android client")
    }

    override fun tailscaleHostname(): String = ""

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions): BridgeSession {
        throw UnsupportedOperationException("Not supported on Android client")
    }

    // ------------------------------------------------------------- helpers

    private fun connectivityManagerOrNull(): ConnectivityManager? =
        context?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    private fun isTunInterfaceName(name: String): Boolean =
        name.isBlank() || name == myTunName || name.startsWith("tun")

    private fun notifyNetworkUpdate(
        cm: ConnectivityManager,
        listener: InterfaceUpdateListener,
        allowClear: Boolean = false,
    ) {
        runCatching {
            val found = emitCurrentDefaultInterface(cm, listener)
            if (!found && allowClear) {
                listener.updateDefaultInterface("", -1, false, false)
            }
        }.onFailure {
            Log.w(TAG, "notifyNetworkUpdate failed: ${it.message}")
        }
    }

    private fun emitCurrentDefaultInterface(
        cm: ConnectivityManager,
        listener: InterfaceUpdateListener,
    ): Boolean {
        val candidates = ArrayList<Network>()
        cm.activeNetwork?.let { candidates.add(it) }
        @Suppress("DEPRECATION")
        for (n in cm.allNetworks) {
            if (!candidates.contains(n)) candidates.add(n)
        }
        for (network in candidates) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
            val lp = cm.getLinkProperties(network) ?: continue
            val name = lp.interfaceName ?: continue
            if (isTunInterfaceName(name)) continue
            val index = runCatching { java.net.NetworkInterface.getByName(name)?.index }.getOrNull() ?: continue
            val isExpensive = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            listener.updateDefaultInterface(name, index, isExpensive, false)
            return true
        }
        return false
    }

    private fun emitFallbackDefaultInterface(listener: InterfaceUpdateListener) {
        runCatching {
            val enumeration = java.net.NetworkInterface.getNetworkInterfaces()
            while (enumeration != null && enumeration.hasMoreElements()) {
                val javaNi = enumeration.nextElement()
                val name = javaNi.name ?: continue
                if (isTunInterfaceName(name)) continue
                val isUp = runCatching { javaNi.isUp }.getOrDefault(false)
                val isLoopback = runCatching { javaNi.isLoopback }.getOrDefault(false)
                if (!isUp || isLoopback) continue
                listener.updateDefaultInterface(name, javaNi.index, false, false)
                return
            }
        }.onFailure {
            Log.w(TAG, "emitFallbackDefaultInterface failed: ${it.message}")
        }
    }

    private fun buildLibboxInterface(
        javaNi: java.net.NetworkInterface,
        caps: NetworkCapabilities?,
        lp: LinkProperties?,
    ): NetworkInterface {
        val addresses = ArrayList<String>()
        for (ia in javaNi.interfaceAddresses) {
            val host = stripIpZone(ia.address?.hostAddress) ?: continue
            addresses.add("$host/${ia.networkPrefixLength}")
        }

        val dnsServers = ArrayList<String>()
        val gateways = ArrayList<String>()
        if (lp != null) {
            for (dns in lp.dnsServers) {
                stripIpZone(dns.hostAddress)?.let { dnsServers.add(it) }
            }
            for (route in lp.routes) {
                if (route.isDefaultRoute) {
                    stripIpZone(route.gateway?.hostAddress)?.let { gateways.add(it) }
                }
            }
        }

        var flags = 0
        if (runCatching { javaNi.isUp }.getOrDefault(false)) flags = flags or IFF_UP or IFF_RUNNING
        if (runCatching { javaNi.isLoopback }.getOrDefault(false)) flags = flags or IFF_LOOPBACK
        if (runCatching { javaNi.isPointToPoint }.getOrDefault(false)) flags = flags or IFF_POINTOPOINT
        if (runCatching { javaNi.supportsMulticast() }.getOrDefault(false)) flags = flags or IFF_MULTICAST
        if ((flags and IFF_LOOPBACK) == 0 && (flags and IFF_POINTOPOINT) == 0) {
            flags = flags or IFF_BROADCAST
        }

        val ifaceType = when {
            caps == null -> Libbox.InterfaceTypeOther
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
            else -> Libbox.InterfaceTypeOther
        }

        val mtu = runCatching { javaNi.mtu }.getOrDefault(1500).let { if (it > 0) it else 1500 }
        val metered = caps != null && !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)

        return NetworkInterface().apply {
            index = javaNi.index
            this.mtu = mtu
            name = javaNi.name
            this.addresses = StringArrayIterator(addresses)
            this.flags = flags
            type = ifaceType
            dnsServer = StringArrayIterator(dnsServers)
            gateway = StringArrayIterator(gateways)
            this.metered = metered
        }
    }

    private class StringArrayIterator(private val items: List<String>) : StringIterator {
        private var cursor = 0

        override fun hasNext(): Boolean = cursor < items.size

        override fun len(): Int = items.size

        override fun next(): String {
            if (!hasNext()) throw NoSuchElementException("iterator exhausted")
            return items[cursor++]
        }
    }

    private class NetworkInterfaceListIterator(
        private val items: List<NetworkInterface>,
    ) : NetworkInterfaceIterator {
        private var cursor = 0

        override fun hasNext(): Boolean = cursor < items.size

        override fun next(): NetworkInterface {
            if (!hasNext()) throw NoSuchElementException("iterator exhausted")
            return items[cursor++]
        }
    }

    companion object {
        private const val TAG = "LibboxPlatformInterface"
        private const val NO_OWNER = -1
        private const val EMPTY_SSID = ""
        private const val EMPTY_BSSID = ""

        // Linux/Android <linux/if.h> flags consumed by libbox/link_flags_unix.go.
        private const val IFF_UP = 0x1
        private const val IFF_BROADCAST = 0x2
        private const val IFF_LOOPBACK = 0x8
        private const val IFF_POINTOPOINT = 0x10
        private const val IFF_RUNNING = 0x40
        private const val IFF_MULTICAST = 0x1000

        /**
         * Strips IPv6 zone suffixes (`%wlan0`) so Go's `netip.MustParsePrefix`
         * and `netip.ParseAddr` never panic on link-local addresses.
         */
        internal fun stripIpZone(raw: String?): String? {
            if (raw.isNullOrBlank()) return null
            val pct = raw.indexOf('%')
            return if (pct >= 0) raw.substring(0, pct) else raw
        }
    }
}
