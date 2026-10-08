// SPDX-License-Identifier: GPL-3.0-or-later

package dev.brickvpn.harness

import android.app.Application
import android.util.Log
import io.nekohasekai.libbox.libbox.Libbox
import io.nekohasekai.libbox.libbox.SetupOptions

/**
 * Process-wide libbox initialisation.
 *
 * ## Why this class has to exist
 *
 * `Libbox.setup(SetupOptions)` is **not optional**, and this is the one piece of
 * the libbox contract that cannot live in [dev.brickvpn.harness.vpn.BrickVpnService]:
 * it is a global (`native` static) that must complete before any service starts.
 *
 * Until it is called, sing-box's internal `sWorkingPath`/`sTempPath` are the
 * empty string. `libbox.NewService` then does:
 *
 * ```go
 * ctx = filemanager.WithDefault(ctx, sWorkingPath, sTempPath, sUserID, sGroupID)
 * ```
 *
 * and with an empty working path sing-box resolves its cache file relative to
 * the **process working directory** — which on Android is `/`, a read-only
 * filesystem. Every `BoxService.start()` then fails with:
 *
 * ```
 * proxyerror: pre-start cache file: open cache.db: read-only file system
 * ```
 *
 * That failure was observed on the real device (SM-A205F, API 29) during P3-T7
 * *before* this class existed — the 18-method `PlatformInterface` and the TUN
 * handoff were already correct, and this missing initialisation was the sole
 * cause. Primary source: `SagerNet/sing-box` @ `253b419` (v1.10.7),
 * `experimental/libbox/setup.go` and `experimental/libbox/service.go:NewService`.
 *
 * ## Threading
 *
 * Called synchronously from [onCreate]. The Go side performs two `os.MkdirAll`
 * calls and a handful of field assignments — no network, no descriptor wait.
 * It is deliberately **not** deferred to a background dispatcher: if setup had
 * not completed before a service ran, `NewService` would race it and fail
 * nondeterministically. `ARCHITECTURE.md` §3.5 N2's "never block the main
 * thread" rule targets long-running engine work, not one-shot local init.
 *
 * ## Failure handling
 *
 * Logged at ERROR with a stack trace, never swallowed. It is not rethrown:
 * crashing the whole app from `Application.onCreate` is a worse failure mode
 * than letting the subsequent `NewService` fail loudly through the state
 * machine, which is where a VPN failure is actually observable.
 */
class BrickVpnApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        initialiseLibbox()
    }

    private fun initialiseLibbox() {
        // Internal storage only. The reference implementation points the working
        // directory at `getExternalFilesDir(null)`, which can be null when
        // external storage is unmounted -- and its caller then skips setup
        // entirely, silently reinstating the exact empty-path bug above.
        // `filesDir` is always writable, so this harness does not inherit that.
        val basePath = filesDir.absolutePath
        val workingPath = filesDir.absolutePath
        val tempPath = cacheDir.absolutePath

        try {
            Libbox.setup(
                SetupOptions().also {
                    it.basePath = basePath
                    it.workingPath = workingPath
                    it.tempPath = tempPath
                    // BoxService.Start() runs `instance.Start()` on a *fresh*
                    // goroutine when this is set (service.go). It is the
                    // documented workaround for golang/go#68760, reachable here
                    // because start() is invoked from a JNI-attached thread
                    // with a small stack. It does NOT weaken the
                    // no-main-thread-blocking rule: Start() still blocks on
                    // `<-done`, and we call it from Dispatchers.IO regardless.
                    it.fixAndroidStack = true
                },
            )
            Log.i(TAG, "Libbox.setup ok (base=$basePath, working=$workingPath, temp=$tempPath)")
        } catch (t: Throwable) {
            Log.e(TAG, "Libbox.setup FAILED; libbox start will fail loudly later", t)
        }
    }

    private companion object {
        const val TAG = "BrickVpnApplication"
    }
}
