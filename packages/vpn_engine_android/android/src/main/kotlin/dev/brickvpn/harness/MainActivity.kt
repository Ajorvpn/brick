// SPDX-License-Identifier: GPL-3.0-or-later

package dev.brickvpn.harness

import android.os.Bundle
import android.util.Log
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import io.nekohasekai.libbox.libbox.Libbox

/**
 * Gate A placeholder activity.
 *
 * As of P3-T3 this additionally proves that the libbox AAR built by
 * `scripts/build_libbox_aar.sh` links: [Libbox.version] is a `native` method,
 * so calling it loads `libgojni.so` through the JNI bridge. If the AAR were
 * missing, mismatched, or not 16 KB aligned, this would fail loudly.
 *
 * It deliberately does nothing else: no VPN service, no TUN, no network calls,
 * no credential handling. The real `VpnService` is a later Gate A task (P3-T6).
 */
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Calling a native method is the actual JNI-linkage proof. Guarded so
        // the harness can still render if libbox ever fails to load, but the
        // failure is logged loudly rather than swallowed.
        val versionText = try {
            val v = Libbox.version()
            Log.i(TAG, "libbox version: $v")
            getString(R.string.harness_libbox, v)
        } catch (e: UnsatisfiedLinkError) {
            // Deliberately rethrown as a visible error string: a silent
            // fallback would let a broken AAR look like a passing build.
            Log.e(TAG, "libbox native library failed to load", e)
            getString(R.string.harness_libbox_failed, e.message ?: "UnsatisfiedLinkError")
        }

        val headline = TextView(this).apply {
            text = getString(R.string.harness_headline)
            textSize = 22f
            setPadding(48, 96, 48, 24)
        }
        val body = TextView(this).apply {
            text = getString(R.string.harness_body)
            textSize = 14f
            setPadding(48, 0, 48, 24)
        }
        val version = TextView(this).apply {
            text = versionText
            textSize = 14f
            setPadding(48, 0, 48, 0)
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(headline)
            addView(body)
            addView(version)
        }
        setContentView(container)
    }

    private companion object {
        const val TAG = "BrickVpnHarness"
    }
}
