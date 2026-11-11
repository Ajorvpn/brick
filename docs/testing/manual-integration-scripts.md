# Manual Integration Test Scripts: Android OS System Boundary Verification

**Document Purpose:**
This document defines precise, repeatable manual and semi-automated integration verification procedures for edge cases that cross the Android system boundary. In accordance with `AI_ROLES/ROADMAP.md` (`P9-T2` Acceptance Criteria 1 and 3), behaviors that involve OS modal dialogs, platform security prompts, Doze power states, or external OS Settings are documented here as human-executable procedures with exact commands, verification steps, and clear justification for why automated in-process widget/unit tests cannot replace real OS-level verification.

---

## Script 1: Android OS VPN Consent Dialog (`VpnService.prepare`)

### 1. Context & Non-Automation Justification
When an application invokes `VpnService.prepare(context)`, Android's security subsystem determines whether an intent must be resolved by the system dialog (`com.android.vpndialogs`).
- **Why Non-Automatable via Standard Flutter Tests:** The VPN consent dialog is rendered by an external system process (`com.android.vpndialogs`) outside the Flutter window and view hierarchy. In-process Flutter widget testers and unit runners cannot click or inspect this OS-owned dialog without UIAutomator or root access.
- **Relevant Tasks:** `P3-T1`, `P5-T8`, `P9-T2`.

### 2. Pre-Conditions
1. Real physical device or emulator connected via ADB.
2. App data cleared to ensure no previous consent is remembered:
   ```bash
   adb shell pm clear dev.brickvpn.mobile
   ```

### 3. Step-by-Step Procedure
1. Launch the application:
   ```bash
   adb shell monkey -p dev.brickvpn.mobile -c android.intent.category.LAUNCHER 1
   ```
2. Navigate past any introductory view and tap **Add Server**.
3. Import a valid server profile (e.g., via URI paste or sample profile).
4. Tap the central **Connect** button on `HomeScreen`.
5. Observe the system modal dialog:
   - **Dialog Title:** "Connection request" / "Brick VPN wants to set up a VPN connection that allows it to monitor network traffic."
   - **Key Icon:** Key symbol in status bar preview.
6. **Negative Path (User Denies):**
   - Tap **Cancel**.
   - **Expected Outcome:** Tunnel does NOT connect; UI cleanly transitions back to `Disconnected` without infinite loading spinners or crashing. No key icon appears in the status bar.
7. **Positive Path (User Accepts):**
   - Tap **Connect** again.
   - Tap **OK** on the system consent dialog.
   - **Expected Outcome:** Status transitions to `Connected`. Android status bar displays the VPN Key icon. `SessionInfoPanel` duration timer begins incrementing from `00:00:01`.

---

## Script 2: Android 14+ Foreground Service Notification, Doze Mode & Battery Optimization

### 1. Context & Non-Automation Justification
Android 14+ (API 34+) enforces strict runtime foreground service types (`specialUse` / `connectedDevice`) and background battery restrictions. During deep sleep (Doze mode), the system shuts down network access for unexempted apps and restricts maintenance windows.
- **Why Non-Automatable via Standard Flutter Tests:** Simulated FakeAsync clocks in unit tests do not trigger kernel-level deep Doze states (`deviceidle`), nor can they verify Android System UI notification shade rendering or OEM power manager kills.
- **Relevant Tasks:** `P7-T4`, `P8-T5`, `P9-T2`.

### 2. Pre-Conditions
1. Device running Android 10+ (tested on Samsung SM-A205F / Android 14 emulator).
2. Device disconnected from USB charging or simulated battery un-plugged:
   ```bash
   adb shell dumpsys battery unplug
   ```

### 3. Step-by-Step Procedure
1. **Foreground Service Notification Check:**
   - Connect to an active server in Brick VPN.
   - Swipe down the Android notification shade.
   - **Expected Outcome:** Persistent foreground service notification is present with title "Brick VPN Connected" (or localized equivalent), displaying current active server name and live session duration. Tapping the notification brings `HomeScreen` to the foreground.
2. **Battery Optimization Exemption Flow:**
   - In Brick VPN Settings, observe the "Ignore Battery Optimizations" prompt or status tile.
   - If prompted, tap "Request Exemption" -> system dialog opens. Tap "Allow".
   - Verify exemption via ADB:
     ```bash
     adb shell dumpsys deviceidle whitelist | grep dev.brickvpn.mobile
     ```
   - **Expected Outcome:** Package `dev.brickvpn.mobile` is listed in the user whitelist.
3. **Doze State Induction:**
   - Turn screen off:
     ```bash
     adb shell input keyevent KEYCODE_POWER
     ```
   - Force step through Doze states until `IDLE`:
     ```bash
     adb shell dumpsys deviceidle force-idle
     adb shell dumpsys deviceidle step
     ```
   - Verify state is `IDLE`:
     ```bash
     adb shell dumpsys deviceidle get
     ```
   - Let device sit in forced Doze for 60 seconds.
   - Wake the device:
     ```bash
     adb shell input keyevent KEYCODE_WAKEUP
     adb shell input keyevent KEYCODE_MENU
     ```
   - Check VPN process and tunnel continuity:
     ```bash
     adb shell pidof dev.brickvpn.mobile
     ```
   - **Expected Outcome:** Process PID remains unchanged. Tunnel did not drop, or auto-reconnect cleanly resumed upon wake.
4. **Cleanup:**
   ```bash
   adb shell dumpsys deviceidle unforce
   adb shell dumpsys battery reset
   ```

---

## Script 3: System "Always-On VPN" and "Block Connections Without VPN"

### 1. Context & Non-Automation Justification
Android provides system-level "Always-on VPN" and "Block connections without VPN" in OS Settings (`Settings > Network & internet > VPN`). When "Block connections without VPN" is active, the Android OS firewall drops all non-VPN traffic.
- **Why Non-Automatable via Standard Flutter Tests:** OS system settings are maintained by `VpnConfig` and `LockdownVpnTracker` inside `system_server`. An app cannot configure its own system lockdown toggle directly without user interaction in Android OS Settings.
- **Relevant Tasks:** `P7-T2`, `P7-T5`, `P9-T2`.

### 2. Pre-Conditions
1. Brick VPN installed and initialized with at least one working profile.

### 3. Step-by-Step Procedure
1. Open Android OS Settings -> **Network & Internet** -> **VPN**.
2. Tap the gear/cog icon next to **Brick VPN**.
3. Toggle ON **Always-on VPN**.
4. Toggle ON **Block connections without VPN** (Lockdown mode).
5. **Cold Boot Test:**
   - Force reboot or restart the phone (`adb reboot`).
   - Observe boot completion:
   - **Expected Outcome:** Android OS automatically launches `BrickVpnService` upon boot without requiring user interaction. Status bar shows VPN Key icon.
6. **Fail-Closed Verification:**
   - Disconnect the VPN manually or induce a native crash.
   - Attempt to access an external website (e.g., in Chrome browser).
   - **Expected Outcome:** All internet access is immediately blocked by the OS (`ERR_INTERNET_DISCONNECTED`). Zero packet leak occurs outside the VPN tunnel.

---

## Script 4: Native Service Process Death & UI Process Relaunch Re-Attachment

### 1. Context & Non-Automation Justification
In Android's dual-component architecture, the UI (`MainActivity`) runs in the main application process while `BrickVpnService` may persist or be restarted independently by the system under low-memory killer (LMK) pressure.
- **Why Non-Automatable via In-Process Tests:** In-process unit tests share the same Dart VM. Killing the native Linux process terminates the test runner itself.
- **Relevant Tasks:** `P7-T6`, `P9-T2`.

### 2. Pre-Conditions
1. Device connected with USB debugging.
2. Brick VPN connected to an active tunnel.

### 3. Step-by-Step Procedure
1. Confirm the VPN is connected and note the PID:
   ```bash
   PID=$(adb shell pidof dev.brickvpn.mobile)
   echo "Active PID: $PID"
   ```
2. Press the device Home button so the app moves to the background:
   ```bash
   adb shell input keyevent KEYCODE_HOME
   ```
3. Simulate low-memory process reclamation by killing the UI package:
   ```bash
   adb shell am kill dev.brickvpn.mobile
   ```
4. Verify whether the process was killed:
   ```bash
   adb shell pidof dev.brickvpn.mobile || echo "Process terminated as expected"
   ```
5. Relaunch the app from the Android Launcher:
   ```bash
   adb shell monkey -p dev.brickvpn.mobile -c android.intent.category.LAUNCHER 1
   ```
6. **Expected Outcome:**
   - The app launches and immediately transitions to `Connected` state within < 200ms.
   - Zero transient `"Disconnected"` flash appears on the UI.
   - The active server name, session duration (resuming from the persisted start time), and throughput metrics continue tracking without starting from 0.
   - Disconnecting from the UI cleanly terminates the active session.

