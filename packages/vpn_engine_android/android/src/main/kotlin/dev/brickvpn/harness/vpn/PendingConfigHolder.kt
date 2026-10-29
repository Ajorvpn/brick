package dev.brickvpn.harness.vpn

import java.util.concurrent.atomic.AtomicReference

object PendingConfigHolder {
    private val pending = AtomicReference<String?>(null)
    fun put(configJson: String) { pending.set(configJson) }
    fun take(): String? = pending.getAndSet(null)
    fun clear() { pending.set(null) }
}
