// SPDX-License-Identifier: GPL-3.0-or-later

package dev.brickvpn.harness

import android.content.Context
import android.util.Log
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.SetupOptions
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Idempotent libbox initialisation for any process that runs the VPN service.
 *
 * `Libbox.setup(SetupOptions)` is a global (native static) that must complete
 * before any `Libbox.newService` call. In the standalone harness this was done
 * in [BrickVpnApplication.onCreate], but the Flutter app uses a different
 * Application class, so setup was never called and libbox failed with
 * "cache.db: read-only file system".
 *
 * This object ensures setup runs exactly once per process, using app-private
 * directories that are always writable.
 */
object LibboxBootstrap {

    private val initialized = AtomicBoolean(false)

    fun ensureSetup(context: Context) {
        if (initialized.get()) return
        synchronized(this) {
            if (initialized.get()) return
            val basePath = context.filesDir.absolutePath
            val workingPath = context.filesDir.absolutePath
            val tempPath = context.cacheDir?.absolutePath ?: context.filesDir.absolutePath

            try {
                Libbox.setup(
                    SetupOptions().also {
                        it.basePath = basePath
                        it.workingPath = workingPath
                        it.tempPath = tempPath
                        it.fixAndroidStack = true
                    },
                )
                Log.i(TAG, "Libbox.setup ok (base=$basePath, working=$workingPath, temp=$tempPath)")
            } catch (t: Throwable) {
                Log.e(TAG, "Libbox.setup FAILED; libbox start will fail loudly later", t)
            }
            initialized.set(true)
        }
    }

    private const val TAG = "LibboxBootstrap"
}
