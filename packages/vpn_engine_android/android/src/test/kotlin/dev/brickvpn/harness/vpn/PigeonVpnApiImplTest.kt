package dev.brickvpn.harness.vpn

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PigeonVpnApiImplTest {

    private val testDispatcher = StandardTestDispatcher()
    private val dummyContext: Context = ContextWrapper(null)
    private var hubListener: ((CommandKind, VpnCommandResult) -> Unit)? = null
    private lateinit var coordinator: CommandCoordinator

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        hubListener = null
        PendingConfigHolder.clear()
        coordinator = CommandCoordinator(
            setListener = { hubListener = it },
            mainDispatcher = testDispatcher,
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        hubListener = null
        PendingConfigHolder.clear()
    }

    // ------------------------------------------------------------- start()

    @Test
    fun `start with empty profileJson returns REJECTED_INVALID_CONFIG immediately`() = runTest(testDispatcher) {
        var prepareCheckerCalled = false
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { prepareCheckerCalled = true; null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val outcome = impl.start(emptyMap())

        assertEquals(VpnCommandOutcome.REJECTED_INVALID_CONFIG, outcome)
        assertFalse("prepareChecker must not be called", prepareCheckerCalled)
        assertFalse("startServiceLauncher must not be called", startLauncherCalled)
    }

    @Test
    fun `start with permission denied returns REJECTED_PERMISSION_DENIED without starting service`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val outcome = impl.start(mapOf("outbound" to mapOf("type" to "block")))

        assertEquals(VpnCommandOutcome.REJECTED_PERMISSION_DENIED, outcome)
        assertFalse("startServiceLauncher must not be called", startLauncherCalled)
    }

    @Test
    fun `start with valid config and permission dispatches through coordinator and returns outcome`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val profile = mapOf("outbound" to mapOf("type" to "block"))

        val deferredOutcome = async {
            impl.start(profile)
        }
        runCurrent()

        assertTrue("startServiceLauncher must be dispatched", startLauncherCalled)
        hubListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()

        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
    }

    @Test
    fun `start with missing outbound returns REJECTED_INVALID_CONFIG`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val outcome = impl.start(mapOf("profile" to "test-data"))

        assertEquals(VpnCommandOutcome.REJECTED_INVALID_CONFIG, outcome)
        assertFalse("startServiceLauncher must not be called", startLauncherCalled)
    }

    @Test
    fun `start with empty outbound returns REJECTED_INVALID_CONFIG`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val outcome = impl.start(mapOf("outbound" to emptyMap<String, Any?>()))

        assertEquals(VpnCommandOutcome.REJECTED_INVALID_CONFIG, outcome)
        assertFalse("startServiceLauncher must not be called", startLauncherCalled)
    }

    @Test
    fun `start with valid config places generated JSON into PendingConfigHolder`() = runTest(testDispatcher) {
        var startLauncherCalled = false

        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = { startLauncherCalled = true },
        )

        val profile = mapOf("outbound" to mapOf("type" to "direct", "tag" to "proxy"))

        val deferredOutcome = async {
            impl.start(profile)
        }
        runCurrent()

        val pending = PendingConfigHolder.take()
        assertNotNull(pending)
        val json = org.json.JSONObject(pending!!)
        assertTrue("pending config must contain dns block for non-block outbound", json.has("dns"))
        val outbounds = json.getJSONArray("outbounds")
        val firstOutbound = outbounds.getJSONObject(0)
        assertEquals("proxy", firstOutbound.getString("tag"))
        val secondOutbound = outbounds.getJSONObject(1)
        assertEquals("direct", secondOutbound.getString("type"))
        assertEquals("direct-out", secondOutbound.getString("tag"))
        assertEquals("proxy", json.getJSONObject("route").getString("final"))
        val dnsServer = json.getJSONObject("dns").getJSONArray("servers").getJSONObject(0)
        assertEquals("udp", dnsServer.getString("type"))
        assertEquals("1.1.1.1", dnsServer.getString("server"))
        assertFalse(dnsServer.has("detour"))

        hubListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()

        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
    }

    @Test
    fun `start with outbound lacking tag injects tag proxy and matching route final`() = runTest(testDispatcher) {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = {},
        )

        val profile = mapOf(
            "outbound" to mapOf(
                "type" to "vless",
                "server" to "example.com",
                "server_port" to 443,
                "uuid" to "00000000-0000-0000-0000-000000000000",
            ),
        )

        val deferredOutcome = async { impl.start(profile) }
        runCurrent()

        val pending = PendingConfigHolder.take()
        assertNotNull(pending)
        val json = org.json.JSONObject(pending!!)
        val outbounds = json.getJSONArray("outbounds")
        val firstOutbound = outbounds.getJSONObject(0)
        assertEquals("proxy", firstOutbound.getString("tag"))
        val secondOutbound = outbounds.getJSONObject(1)
        assertEquals("direct", secondOutbound.getString("type"))
        assertEquals("direct-out", secondOutbound.getString("tag"))
        assertEquals("proxy", json.getJSONObject("route").getString("final"))
        val dnsServer = json.getJSONObject("dns").getJSONArray("servers").getJSONObject(0)
        assertEquals("udp", dnsServer.getString("type"))
        assertEquals("1.1.1.1", dnsServer.getString("server"))
        assertFalse(dnsServer.has("detour"))

        hubListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
    }

    @Test
    fun `start with block outbound places valid block config into PendingConfigHolder`() = runTest(testDispatcher) {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
            startServiceLauncher = {},
        )

        val profile = mapOf("outbound" to mapOf("type" to "block"))

        val deferredOutcome = async { impl.start(profile) }
        runCurrent()

        val pending = PendingConfigHolder.take()
        assertNotNull(pending)
        val json = org.json.JSONObject(pending!!)
        val outbounds = json.getJSONArray("outbounds")
        val firstOutbound = outbounds.getJSONObject(0)
        assertEquals("block", firstOutbound.getString("type"))
        assertEquals("block-out", firstOutbound.getString("tag"))
        assertFalse(json.has("dns"))

        hubListener?.invoke(CommandKind.START, VpnCommandResult.Accepted)
        runCurrent()
        assertEquals(VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
    }

    // -------------------------------------------------------------- stop() (Decision D1)

    @Test
    fun `stop in Idle, Stopped, Stopping, or Revoked returns REJECTED_BUSY without sending intent`() = runTest(testDispatcher) {
        val busyStates = listOf(
            VpnState.Idle,
            VpnState.Stopped,
            VpnState.Stopping,
            VpnState.Revoked,
        )

        for (state in busyStates) {
            var stopLauncherCount = 0
            val impl = PigeonVpnApiImpl(
                appContext = dummyContext,
                coordinator = coordinator,
                stateProvider = { state },
                stopServiceLauncher = { stopLauncherCount++ },
            )

            val outcome = impl.stop()

            assertEquals("State $state should return REJECTED_BUSY", VpnCommandOutcome.REJECTED_BUSY, outcome)
            assertEquals("stopServiceLauncher must never be called for $state", 0, stopLauncherCount)
        }
    }

    @Test
    fun `stop in Preparing, Starting, Running, or Error dispatches STOP and returns outcome`() = runTest(testDispatcher) {
        val activeStates = listOf(
            VpnState.Preparing,
            VpnState.Starting,
            VpnState.Running,
            VpnState.Error("test error"),
        )

        for (state in activeStates) {
            var stopLauncherCount = 0
            val impl = PigeonVpnApiImpl(
                appContext = dummyContext,
                coordinator = coordinator,
                stateProvider = { state },
                stopServiceLauncher = { stopLauncherCount++ },
            )

            val deferredOutcome = async {
                impl.stop()
            }
            runCurrent()

            assertEquals("stopServiceLauncher should be called once for $state", 1, stopLauncherCount)
            hubListener?.invoke(CommandKind.STOP, VpnCommandResult.Accepted)
            runCurrent()

            assertEquals("State $state should complete with ACCEPTED", VpnCommandOutcome.ACCEPTED, deferredOutcome.await())
        }
    }

    // --------------------------------------------------------- getStatus()

    @Test
    fun `getStatus maps all 8 VpnState variants to VpnNativeState correctly`() {
        val mappings = listOf(
            VpnState.Idle to (VpnNativeState.IDLE to null),
            VpnState.Preparing to (VpnNativeState.PREPARING to null),
            VpnState.Starting to (VpnNativeState.STARTING to null),
            VpnState.Running to (VpnNativeState.RUNNING to null),
            VpnState.Stopping to (VpnNativeState.STOPPING to null),
            VpnState.Stopped to (VpnNativeState.STOPPED to null),
            VpnState.Revoked to (VpnNativeState.REVOKED to null),
            VpnState.Error("boom") to (VpnNativeState.ERROR to "boom"),
        )

        for ((state, expected) in mappings) {
            val (expectedNative, expectedReason) = expected
            val impl = PigeonVpnApiImpl(
                appContext = dummyContext,
                coordinator = coordinator,
                stateProvider = { state },
            )

            val status = impl.getStatus()
            assertEquals("Native state for $state", expectedNative, status.state)
            assertEquals("Error reason for $state", expectedReason, status.errorReason)
        }
    }

    // ----------------------------------------------------------- prepare() (R2)

    @Test
    fun `prepare when already granted returns ALREADY_GRANTED`() = runTest(testDispatcher) {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { null },
        )

        val status = impl.prepare()
        assertEquals(VpnConsentStatus.ALREADY_GRANTED, status)
    }

    @Test
    fun `prepare when consent required but activity is null returns NO_ACTIVITY`() = runTest(testDispatcher) {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { null },
        )

        val status = impl.prepare()
        assertEquals(VpnConsentStatus.NO_ACTIVITY, status)
    }

    @Test
    fun `prepare when detached from activity while pending returns DENIED`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, _ -> },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        impl.onDetachedFromActivity()
        runCurrent()

        assertEquals(VpnConsentStatus.DENIED, deferred.await())
    }

    @Test
    fun `prepare completes with GRANTED on RESULT_OK via handleActivityResult`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode, Activity.RESULT_OK)
        runCurrent()

        assertTrue(handled)
        assertEquals(VpnConsentStatus.GRANTED, deferred.await())
    }

    @Test
    fun `prepare completes with DENIED on RESULT_CANCELED via handleActivityResult`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode, Activity.RESULT_CANCELED)
        runCurrent()

        assertTrue(handled)
        assertEquals(VpnConsentStatus.DENIED, deferred.await())
    }

    @Test
    fun `concurrent prepare calls reuse existing deferred`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred1 = async { impl.prepare() }
        val deferred2 = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode, Activity.RESULT_OK)
        runCurrent()

        assertTrue(handled)
        assertEquals(VpnConsentStatus.GRANTED, deferred1.await())
        assertEquals(VpnConsentStatus.GRANTED, deferred2.await())
    }

    @Test
    fun `handleActivityResult with mismatched request code returns false and leaves pending`() = runTest(testDispatcher) {
        val dummyActivity = object : Activity() {}
        var capturedRequestCode = -1
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
            prepareChecker = { Intent() },
            activityProvider = { dummyActivity },
            activityStarter = { _, _, code -> capturedRequestCode = code },
        )

        val deferred = async { impl.prepare() }
        runCurrent()

        val handled = impl.handleActivityResult(capturedRequestCode + 999, Activity.RESULT_OK)
        runCurrent()

        assertFalse(handled)
        assertFalse(deferred.isCompleted)

        // Complete cleanly with correct code
        impl.handleActivityResult(capturedRequestCode, Activity.RESULT_OK)
        runCurrent()
        assertEquals(VpnConsentStatus.GRANTED, deferred.await())
    }

    // ------------------------------------------------------------- P7-T3 DNS & Hardening

    @Test
    fun `buildConfigJson enforces DNS bootstrap, TUN hijack, strict_route and zero remote rule sets`() {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
        )
        val outbound = mapOf(
            "type" to "vless",
            "tag" to "tokyo-proxy",
            "server" to "node.example.com",
            "server_port" to 443,
        )
        val jsonStr = impl.buildConfigJson(outbound, isBlock = false)
        val root = org.json.JSONObject(jsonStr)

        // 1. Zero remote rule_set URLs
        assertFalse("Configuration must not contain remote rule_set", root.has("rule_set"))

        // 2. Strict route on TUN inbound, no legacy sniff on inbound
        val inbounds = root.getJSONArray("inbounds")
        val tun = inbounds.getJSONObject(0)
        assertEquals("tun", tun.getString("type"))
        assertTrue("TUN inbound must set strict_route = true", tun.getBoolean("strict_route"))
        assertTrue("TUN inbound must set auto_route = true", tun.getBoolean("auto_route"))
        assertFalse("tun-in must not contain legacy sniff field", tun.has("sniff"))

        // 3. Typed v1.14.4 DNS configuration: bootstrap resolver & remote tunnel resolver
        val dns = root.getJSONObject("dns")
        val dnsServers = dns.getJSONArray("servers")
        var hasDnsRemote = false
        var hasDnsDirect = false
        for (i in 0 until dnsServers.length()) {
            val server = dnsServers.getJSONObject(i)
            assertFalse("v1.14.4 DNS server must not use legacy address key", server.has("address"))
            val tag = server.getString("tag")
            if (tag == "dns-remote") {
                hasDnsRemote = true
                assertEquals("https", server.getString("type"))
                assertEquals("1.1.1.1", server.getString("server"))
                assertEquals("/dns-query", server.getString("path"))
                assertEquals("tokyo-proxy", server.getString("detour"))
                assertEquals("close", server.getJSONObject("headers").getString("Connection"))
                val tls = server.getJSONObject("tls")
                assertTrue(tls.getBoolean("enabled"))
                val alpn = tls.getJSONArray("alpn")
                assertEquals(1, alpn.length())
                assertEquals("http/1.1", alpn.getString(0))
            } else if (tag == "dns-direct") {
                hasDnsDirect = true
                assertEquals("udp", server.getString("type"))
                assertEquals("1.1.1.1", server.getString("server"))
                assertFalse(
                    "dns-direct must omit detour to avoid empty direct outbound error",
                    server.has("detour"),
                )
            }
        }
        assertTrue("Must include dns-remote server", hasDnsRemote)
        assertTrue("Must include direct bootstrap dns-direct server", hasDnsDirect)
        assertEquals("dns-remote", dns.getString("final"))
        assertEquals("4s", dns.getString("timeout"))
        assertFalse("Deprecated dns.rules outbound:any must be omitted", dns.has("rules"))

        // 4. Route: v1.14.4 rule actions (sniff + hijack-dns) & default_domain_resolver
        val route = root.getJSONObject("route")
        assertEquals("tokyo-proxy", route.getString("final"))
        assertEquals("dns-direct", route.getString("default_domain_resolver"))
        val routeRules = route.getJSONArray("rules")
        assertEquals(2, routeRules.length())
        assertEquals("sniff", routeRules.getJSONObject(0).getString("action"))
        val dnsHijack = routeRules.getJSONObject(1)
        assertEquals("dns", dnsHijack.getString("protocol"))
        assertEquals("hijack-dns", dnsHijack.getString("action"))
    }

    // ------------------------------------------------ v1.14.4 schema regression guards

    @Test
    fun `buildConfigJson emits strict v1_14_4 route, typed DNS, and no removed dns outbound`() {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
        )
        val outbound = mapOf(
            "type" to "shadowsocks",
            "tag" to "ss-proxy",
            "server" to "node.example.com",
            "server_port" to 8388,
        )
        val root = org.json.JSONObject(impl.buildConfigJson(outbound, isBlock = false))

        // 1. Removed dns special outbound must NOT appear.
        val outbounds = root.getJSONArray("outbounds")
        for (i in 0 until outbounds.length()) {
            val candidate = outbounds.getJSONObject(i)
            assertFalse(
                "Removed v1.10.7 dns outbound must not be emitted",
                candidate.optString("type") == "dns",
            )
        }

        // 2. Route rules must use v1.14.4 actions: [sniff, protocol:dns -> hijack-dns].
        val route = root.getJSONObject("route")
        assertEquals("dns-direct", route.getString("default_domain_resolver"))
        val rules = route.getJSONArray("rules")
        assertEquals("sniff", rules.getJSONObject(0).getString("action"))
        val hijack = rules.getJSONObject(1)
        assertEquals("dns", hijack.getString("protocol"))
        assertEquals("hijack-dns", hijack.getString("action"))
        assertFalse(hijack.has("outbound"))

        // 3. TUN must NOT set legacy sniff field.
        val tun = root.getJSONArray("inbounds").getJSONObject(0)
        assertFalse("tun-in must not contain removed sniff field", tun.has("sniff"))

        // 4. Typed DNS servers: udp + HTTP/1.1 DoH (Connection: close) with 4s timeout and NO legacy address key.
        val dnsObj = root.getJSONObject("dns")
        assertEquals("4s", dnsObj.getString("timeout"))
        val dnsServers = dnsObj.getJSONArray("servers")
        var remoteServerObj: org.json.JSONObject? = null
        for (i in 0 until dnsServers.length()) {
            val server = dnsServers.getJSONObject(i)
            assertFalse(server.has("address"))
            if (server.getString("tag") == "dns-remote") {
                remoteServerObj = server
            }
        }
        val remote = remoteServerObj!!
        assertEquals("ss-proxy", remote.getString("detour"))
        assertEquals("https", remote.getString("type"))
        assertEquals("1.1.1.1", remote.getString("server"))
        assertEquals("/dns-query", remote.getString("path"))
        assertEquals("close", remote.getJSONObject("headers").getString("Connection"))
        val remoteTls = remote.getJSONObject("tls")
        assertTrue(remoteTls.getBoolean("enabled"))
        assertEquals(1, remoteTls.getJSONArray("alpn").length())
        assertEquals("http/1.1", remoteTls.getJSONArray("alpn").getString(0))

        // 5. Block (Gate A) config stays lean: no dns, no route rules, no sniff.
        val blockRoot = org.json.JSONObject(impl.buildConfigJson(mapOf("type" to "block"), isBlock = true))
        assertFalse(blockRoot.getJSONObject("route").has("rules"))
        assertFalse(blockRoot.getJSONArray("inbounds").getJSONObject(0).has("sniff"))
    }

    @Test
    fun `buildConfigJson translates legacy wireguard outbound into v1_14_4 endpoints`() {
        val impl = PigeonVpnApiImpl(
            appContext = dummyContext,
            coordinator = coordinator,
        )
        val outbound = mapOf(
            "type" to "wireguard",
            "tag" to "wg-proxy",
            "server" to "198.51.100.10",
            "server_port" to 51820,
            "system_interface" to false,
            "local_address" to listOf("10.0.0.2/32"),
            "private_key" to "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "peer_public_key" to "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",
            "pre_shared_key" to "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=",
            "reserved" to listOf(1, 2, 3),
            "mtu" to 1420,
        )
        val root = org.json.JSONObject(impl.buildConfigJson(outbound, isBlock = false))

        // Outbounds must not contain removed wireguard outbound type
        val outbounds = root.getJSONArray("outbounds")
        for (i in 0 until outbounds.length()) {
            assertFalse(
                "wireguard must not appear in outbounds",
                outbounds.getJSONObject(i).optString("type") == "wireguard",
            )
        }

        // Top-level endpoints[0] must carry translated WireGuardEndpointOptions + peers[0]
        val endpoints = root.getJSONArray("endpoints")
        assertEquals(1, endpoints.length())
        val ep = endpoints.getJSONObject(0)
        assertEquals("wireguard", ep.getString("type"))
        assertEquals("wg-proxy", ep.getString("tag"))
        assertEquals(false, ep.getBoolean("system"))
        assertEquals(1420, ep.getInt("mtu"))
        assertEquals("10.0.0.2/32", ep.getJSONArray("address").getString(0))
        val peers = ep.getJSONArray("peers")
        assertEquals(1, peers.length())
        val peer = peers.getJSONObject(0)
        assertEquals("198.51.100.10", peer.getString("address"))
        assertEquals(51820, peer.getInt("port"))
        assertEquals("BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=", peer.getString("public_key"))
        assertEquals("CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=", peer.getString("pre_shared_key"))
        assertEquals("0.0.0.0/0", peer.getJSONArray("allowed_ips").getString(0))
        assertEquals("::/0", peer.getJSONArray("allowed_ips").getString(1))
        assertEquals("wg-proxy", root.getJSONObject("route").getString("final"))
    }

    @Test
    fun `BrickVpnService lockdown transitions maintain state across lifecycle`() {
        assertFalse(BrickVpnService.isLockdownEnabled)
        BrickVpnService.setLockdown(true)
        assertTrue(BrickVpnService.isLockdownEnabled)
        BrickVpnService.setLockdown(false)
        assertFalse(BrickVpnService.isLockdownEnabled)
    }

    @Test
    fun `SecureStorageHelper round-trip encrypts and decrypts with enc v1 envelope`() {
        val secret = "super-sensitive-uuid-12345-secret"
        val encrypted = dev.brickvpn.harness.SecureStorageHelper.encrypt(secret)
        assertTrue(encrypted.startsWith("enc:v1:"))
        assertFalse(encrypted.contains(secret))

        val decrypted = dev.brickvpn.harness.SecureStorageHelper.decrypt(encrypted)
        assertEquals(secret, decrypted)
    }

    @Test(expected = Exception::class)
    fun `SecureStorageHelper rejects tampered ciphertext`() {
        val secret = "another-secret"
        val encrypted = dev.brickvpn.harness.SecureStorageHelper.encrypt(secret)
        val prefix = "enc:v1:"
        val payload = encrypted.substring(prefix.length)
        // Flip one character in base64 payload
        val tamperedChar = if (payload.last() == 'A') 'B' else 'A'
        val tampered = prefix + payload.dropLast(1) + tamperedChar
        dev.brickvpn.harness.SecureStorageHelper.decrypt(tampered)
    }
}
