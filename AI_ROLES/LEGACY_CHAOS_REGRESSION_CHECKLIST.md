# Legacy Prototype Chaos Regression Checklist (`P7-T5`)

> **Durable Reference Document:** This checklist enumerates the twelve discrete
> failure modes documented during the legacy prototype's collapse, detailing the
> root cause of each failure, the architectural invariant introduced in the
> current Brick VPN architecture to eliminate it, the exact automated regression
> test enforcing that invariant, and the verified test status.

---

## 1. Overview & Architectural Reckoning

The legacy prototype failed in production primarily due to architectural coupling,
untested concurrency races, optimistic UI assumptions, blocking calls on the main
thread, and swallowed errors across process boundaries. 

Phase 7 Task 5 (`P7-T5`) establishes a permanent, automated regression safety net
in `apps/mobile/test/legacy_chaos_regression_suite_test.dart` and native JVM test
suites, guaranteeing that none of these twelve documented collapse modes can
silently regress into the codebase.

---

## 2. Legacy Failure Mode Regression Matrix

| # | Legacy Failure Mode | Root Cause in Legacy Code | Current Architecture Solution | Regression Test Location | Status |
|---|---------------------|---------------------------|-------------------------------|--------------------------|:------:|
| **1** | Traffic stats always reporting 0 B/s | Telemetry and connection failure domains were coupled; a socket error on stats stream silently collapsed telemetry without alerting UI. | **Invariant 2:** Independent failure domains. `trafficStats` and `connectionState` streams are strictly decoupled. A stats error never tears down the tunnel, surfaces `Traffic data unavailable`, and resumes cleanly when ticks recover. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 1) | **PASS ✅** |
| **2** | False "Connected" State / Optimistic UI | UI inferred connection from button tap or command acceptance Future instead of waiting for kernel TUN event. | **Invariant 1:** Stream-driven truth. Command acceptance indicates intent receipt only. UI remains in `Connecting` until native `ConnectionState.connected` event is emitted. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 2) | **PASS ✅** |
| **3** | DNS / Rule-Set bootstrap deadlock hang | Serialized sing-box configuration fetched remote `rule_set` URLs or routed bootstrap DNS through the unestablished tunnel. | Serializer emits 0 remote `rule_set` URLs; native config routes `dns-direct` via `direct-out` and user DNS via `dns-remote`; `withTimeout(15_000L)` ensures failed startup aborts cleanly. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 3), `PigeonVpnApiImplTest.kt` | **PASS ✅** |
| **4** | Blocking disconnect call freezing UI thread | Disconnect called synchronous native cleanup on the main thread, locking the UI until native thread joined. | Disconnect dispatches asynchronous non-blocking command; native `BrickVpnService` enforces 5000ms stop watchdog with `stopSelf()` fallback. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 4) | **PASS ✅** |
| **5** | Fire-and-forget startup failure swallowed | Background threads launched core without returning outcome; errors dropped into thread uncaught-exception handlers. | Commands return explicit `VpnCommandResult`; engine state emits structured `Error(PlatformError(detail))`; UI surfaces floating SnackBar error feedback. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 5) | **PASS ✅** |
| **6** | `close()`-then-`initializedOnce` guard bug | Internal initialization flags were never reset upon tunnel closure, permanently breaking subsequent connection attempts in the same process. | Session-scoped lifecycle; all state machines and singletons support repeatable teardown and re-initialization across unlimited back-to-back cycles. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 6) | **PASS ✅** |
| **7** | Service `onBind` returning null causing crash | Bound service returned null IBinder on certain Android API levels, triggering uncaught `NullPointerException` or unhandled IPC drops. | Pigeon HostApi communication with null-safe platform bindings; all IPC calls wrapped in `try-catch` with automatic controller unblocking in `finally`. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 7) | **PASS ✅** |
| **8** | Using `stopService()` instead of `ACTION_STOP` | Direct OS service termination bypassed clean TUN descriptor release and lockdown cleanup, leaving leaks or blocking user network. | Service teardown coordinated via `ACTION_STOP` intent and `stopSelf()`; `KillSwitchNotifier` differentiates deliberate user disconnect (`KillSwitchInactive`) from unexpected drops (`KillSwitchBlocking`). | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 8) | **PASS ✅** |
| **9** | UI race conditions overwriting Stopping state | Late-arriving traffic packets or rapid button taps caused UI to revert from "Disconnecting" back to "Connected". | Monotonic state transitions; late stats are ignored during `Disconnecting`; UI connect toggle button is disabled (`onPressed: null`) during teardown. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 9) | **PASS ✅** |
| **10** | Orphaned coroutines/timers across sessions | Duration timers and stats pollers survived across disconnects, double-ticking or emitting stale metrics in subsequent sessions. | Riverpod auto-dispose and explicit session cancellation; `sessionDurationProvider` and `autoReconnectProvider` cleanly reset to zero upon disconnect. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 10) | **PASS ✅** |
| **11** | Re-entrant stop-call deadlock risk | Rapid concurrent stop calls acquired locks out of order or deadlocked native semaphores. | In-flight command guard (`_busy`) in `ConnectionController`; native `CommandCoordinator` serializes concurrent invocations or rejects with `rejectedBusy`. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 11), `CommandCoordinatorTest.kt` | **PASS ✅** |
| **12** | `detachFd()` / TUN descriptor leak on rapid races | Rapid connect-then-stop during startup leaked open file descriptors when cancelled before TUN attachment. | Safe descriptor management; `cleanupScope` ensures file descriptor is closed; cancellation during `Connecting` settles deterministically in `Disconnected` without orphaned sessions. | `apps/mobile/test/legacy_chaos_regression_suite_test.dart` (Test 12) | **PASS ✅** |

---

## 3. Automated Test Suite Execution

The automated suite can be executed at any time with system resource throttling:

```bash
cd apps/mobile
flutter test --concurrency=2 test/legacy_chaos_regression_suite_test.dart
```

Expected output:
```text
All tests passed! (12 tests)
```

