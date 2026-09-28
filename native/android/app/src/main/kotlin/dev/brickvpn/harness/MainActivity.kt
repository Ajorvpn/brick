// SPDX-License-Identifier: GPL-3.0-or-later

package dev.brickvpn.harness

import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Gate A placeholder activity.
 *
 * This exists only to prove the native module builds and runs from the CLI,
 * with no Flutter, no libbox and no VPN service involved. The real
 * `VpnService` implementation is a later Gate A task (P3-T6).
 *
 * It deliberately does nothing but render a label: no permissions, no
 * network calls, no file or credential handling of any kind.
 */
class MainActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val headline = TextView(this).apply {
            text = getString(R.string.harness_headline)
            textSize = 22f
            setPadding(48, 96, 48, 24)
        }
        val body = TextView(this).apply {
            text = getString(R.string.harness_body)
            textSize = 14f
            setPadding(48, 0, 48, 0)
        }

        val container = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            addView(headline)
            addView(body)
        }
        setContentView(container)
    }
}
