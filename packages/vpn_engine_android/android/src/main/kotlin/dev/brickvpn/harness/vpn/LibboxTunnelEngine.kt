package dev.brickvpn.harness.vpn

import android.content.Context
import android.util.Log
import io.nekohasekai.libbox.libbox.CommandClient
import io.nekohasekai.libbox.libbox.CommandClientHandler
import io.nekohasekai.libbox.libbox.CommandClientOptions
import io.nekohasekai.libbox.libbox.CommandServer
import io.nekohasekai.libbox.libbox.CommandServerHandler
import io.nekohasekai.libbox.libbox.ConnectionEvents
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.LogIterator
import io.nekohasekai.libbox.libbox.OutboundGroupItemIterator
import io.nekohasekai.libbox.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.libbox.OverrideOptions
import io.nekohasekai.libbox.libbox.StatusMessage
import io.nekohasekai.libbox.libbox.StringIterator
import io.nekohasekai.libbox.libbox.SystemProxyStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Real [TunnelEngine] backed by sing-box **v1.14.4** (`CommandServer` + `CommandClient`).
 */
class LibboxTunnelEngine(
    private val configJsonProvider: () -> String = { GATE_A_CONFIG_JSON },
    private val socketProtector: (Int) -> Unit = {},
    private val onLogReceived: (String) -> Unit = {},
    private val appContext: Context? = null,
) : TunnelEngine {

    constructor(configJsonProvider: () -> String) : this(
        configJsonProvider = configJsonProvider,
        socketProtector = {},
    )

    constructor(
        configJsonProvider: () -> String,
        socketProtector: (Int) -> Unit,
    ) : this(
        configJsonProvider = configJsonProvider,
        socketProtector = socketProtector,
        onLogReceived = {},
        appContext = null,
    )

    private val tag = "LibboxTunnelEngine"

    @Volatile
    private var commandServer: CommandServer? = null

    @Volatile
    private var logClient: CommandClient? = null

    @Volatile
    private var lentFd: Int? = null

    @Volatile
    private var platformInterface: LibboxPlatformInterface? = null

    private val running = AtomicBoolean(false)

    private val serverHandler = object : CommandServerHandler {
        override fun serviceStop() {
            Log.i(tag, "CommandServerHandler.serviceStop")
        }

        override fun serviceReload() {
            Log.i(tag, "CommandServerHandler.serviceReload")
        }

        override fun getSystemProxyStatus(): SystemProxyStatus =
            SystemProxyStatus().apply {
                available = false
                enabled = false
            }

        override fun setSystemProxyEnabled(isEnabled: Boolean) {}

        override fun triggerNativeCrash() {}

        override fun writeDebugMessage(message: String?) {
            if (!message.isNullOrBlank()) {
                forwardLogLine(LEVEL_INFO, message)
            }
        }

        override fun connectSSHAgent(): Int = -1
    }

    override suspend fun start(tunFd: Int, configJson: String?) {
        check(commandServer == null) { "start() called while a libbox service is already running" }
        lentFd = tunFd
        val pi = LibboxPlatformInterface(
            context = appContext,
            tunFdProvider = { currentLentFd() },
            socketProtector = socketProtector,
        )
        platformInterface = pi
        val config = configJson?.takeIf { it.isNotBlank() } ?: configJsonProvider()
        try {
            val server = withContext(Dispatchers.IO) { Libbox.newCommandServer(serverHandler, pi) }
            commandServer = server
            withContext(Dispatchers.IO) { server.start() }
            withContext(Dispatchers.IO) { server.startOrReloadService(config, OverrideOptions()) }
            running.set(true)
            Log.i(tag, "libbox service started; needWIFIState=${server.needWIFIState()}")

            val client = Libbox.newCommandClient(
                createLogClientHandler(),
                CommandClientOptions().apply { addCommand(Libbox.CommandLog) },
            )
            logClient = client
            withContext(Dispatchers.IO) {
                runCatching { client.connect() }
                    .onFailure { Log.w(tag, "log CommandClient connect skipped: ${it.message}") }
            }
        } catch (t: Throwable) {
            runCatching { logClient?.disconnect() }
                .onFailure { Log.w(tag, "cleanup logClient disconnect failed: ${it.message}") }
            runCatching { commandServer?.closeService() }
                .onFailure { Log.w(tag, "cleanup closeService failed: ${it.message}") }
            runCatching { commandServer?.close() }
                .onFailure { Log.w(tag, "cleanup CommandServer close failed: ${it.message}") }
            logClient = null
            commandServer = null
            platformInterface = null
            lentFd = null
            val errLine = "ERROR libbox start failed: ${t.javaClass.simpleName}: ${t.message}"
            Log.e(tag, errLine)
            runCatching { onLogReceived(errLine) }
            runCatching { globalLogConsumer?.invoke(errLine) }
            throw t
        }
    }

    override suspend fun stop() {
        val toDisconnect = logClient
        val toClose = commandServer
        logClient = null
        commandServer = null
        platformInterface = null
        lentFd = null
        if (toClose == null && toDisconnect == null) {
            Log.i(tag, "stop(): no libbox service to close (already stopped)")
            return
        }
        withContext(Dispatchers.IO) {
            runCatching { toDisconnect?.disconnect() }
                .onFailure { Log.w(tag, "logClient disconnect failed: ${it.message}") }
            runCatching { toClose?.closeService() }
                .onFailure { Log.w(tag, "CommandServer closeService failed: ${it.message}") }
            toClose?.close()
        }
        running.set(false)
        Log.i(tag, "libbox CommandServer closed")
    }

    private fun createLogClientHandler(): CommandClientHandler = object : CommandClientHandler {
        override fun clearLogs() {}

        override fun connected() {
            Log.i(tag, "CommandClient log stream connected")
        }

        override fun disconnected(message: String?) {
            Log.i(tag, "CommandClient log stream disconnected: ${message ?: "closed"}")
        }

        override fun initializeClashMode(modeList: StringIterator?, currentMode: String?) {}

        override fun setDefaultLogLevel(level: Int) {}

        override fun updateClashMode(newMode: String?) {}

        override fun writeConnectionEvents(events: ConnectionEvents?) {}

        override fun writeGroups(groups: OutboundGroupIterator?) {}

        override fun writeLogs(messageList: LogIterator?) {
            if (messageList == null) return
            while (messageList.hasNext()) {
                val entry = messageList.next() ?: continue
                val msg = entry.message ?: continue
                forwardLogLine(entry.level, msg)
            }
        }

        override fun writeOutbounds(outbounds: OutboundGroupItemIterator?) {}

        override fun writeStatus(message: StatusMessage?) {}
    }

    private fun forwardLogLine(level: Int, rawMessage: String) {
        val cleaned = ANSI_ESCAPE_REGEX.replace(rawMessage, "").trim()
        if (cleaned.isEmpty()) return
        val formatted = formatLogLine(level, cleaned)
        Log.i(tag, "libbox: $formatted")
        runCatching { onLogReceived(formatted) }
        runCatching { globalLogConsumer?.invoke(formatted) }
    }

    private fun currentLentFd(): Int = lentFd
        ?: error("libbox asked for a TUN descriptor but none is currently lent")

    fun isRunning(): Boolean = running.get()

    companion object {
        @Volatile
        var globalLogConsumer: ((String) -> Unit)? = null

        private const val LEVEL_PANIC = 0
        private const val LEVEL_FATAL = 1
        private const val LEVEL_ERROR = 2
        private const val LEVEL_WARN = 3
        private const val LEVEL_INFO = 4
        private const val LEVEL_DEBUG = 5
        private const val LEVEL_TRACE = 6

        private val ANSI_ESCAPE_REGEX = Regex("\u001B\\[[0-9;]*[mK]")
        private val LEADING_LEVEL_REGEX =
            Regex("""^(?:[+-]\d{4}\s+\d{4}[-/]\d{2}[-/]\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d+)?\s+)?(?:\[?(?:PANIC|FATAL|ERROR|WARN|WARNING|INFO|DEBUG|TRACE)\]?\b)""")

        internal fun formatLogLine(level: Int, cleanMessage: String): String {
            if (LEADING_LEVEL_REGEX.containsMatchIn(cleanMessage)) {
                return cleanMessage
            }
            val label = when (level) {
                LEVEL_PANIC -> "FATAL"
                LEVEL_FATAL -> "FATAL"
                LEVEL_ERROR -> "ERROR"
                LEVEL_WARN -> "WARN"
                LEVEL_INFO -> "INFO"
                LEVEL_DEBUG -> "DEBUG"
                LEVEL_TRACE -> "TRACE"
                else -> "INFO"
            }
            return "$label $cleanMessage"
        }

        /**
         * Gate A lifecycle-test config updated for sing-box **v1.14.4**:
         * uses a `direct` outbound with a catch-all `reject` route action
         * (zero remote servers, zero DNS, zero external downloads).
         */
        const val GATE_A_CONFIG_JSON: String = """
        {
          "log": { "level": "info", "timestamp": false },
          "inbounds": [
            {
              "type": "tun",
              "tag": "tun-in",
              "address": [ "10.111.222.1/24" ],
              "mtu": 9000
            }
          ],
          "outbounds": [
            { "type": "direct", "tag": "direct-out" }
          ],
          "route": {
            "auto_detect_interface": true,
            "rules": [
              { "action": "reject" }
            ]
          }
        }
        """
    }
}
