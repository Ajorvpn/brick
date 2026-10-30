# Temporary Artifacts & Test Modifications Inventory

This file tracks all temporary test skips, ignores, or preview implementations currently present in the working tree, including file paths, line numbers, purpose, and required remediation in future tasks.

---

## 1. `packages/vpn_engine_android/android/src/main/kotlin/dev/brickvpn/harness/VpnEngineAndroidPlugin.kt`
- **Location:** Line 96 (`PluginTrafficStatsEventsStreamHandler`)
- **Marker:** `// TEMP-ARTIFACT(P3-T16): Minimal real stats publisher. To be robustly upgraded in P3-T8.`
- **Purpose:** Provides a real-data (non-simulated) traffic statistics publisher reading real rx/tx bytes via `android.net.TrafficStats` and `/sys/class/net/tun0/statistics/` while VPN is `Running`. This preview implementation was added under a scoped human exception to unblock P3-T16 Gate B chaos testing before P3-T8 is formally executed.
- **Future Remediation:** To be upgraded and replaced by the full-featured, failure-domain-independent `TrafficStatsPublisher` and bounded redacted log ring buffer during **P3-T8**.
