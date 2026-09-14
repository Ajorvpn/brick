# DEFINITION_OF_DONE.md — Brick VPN Task Completion Standard

> A task is not complete because code was written. A task is complete only
> when its implementation has been verified, reviewed, documented, and is
> safe to merge without creating hidden technical debt.
>
> Every AI coding agent MUST apply this checklist before claiming that any
> task is complete.

---

## 0. Core Rule

A task may be reported as one of the following states only:

| Status | Meaning |
|---|---|
| `Not Started` | No implementation work has begun. |
| `In Progress` | Implementation, investigation, testing, or review is incomplete. |
| `Blocked` | Work cannot proceed safely without a human decision, missing access, verified documentation, credentials, hardware, or another dependency. |
| `Ready for Human Review` | All applicable checks passed. The task is technically complete but awaits human review/approval. |
| `Completed` | The human maintainer explicitly accepted the task after review. |

An AI agent MUST NOT mark a task as `Completed` by itself. Its highest
self-assigned completion state is `Ready for Human Review`.

---

## 1. Mandatory Preconditions

Before implementation begins, the agent must confirm all of the following:

- [ ] The current task was identified in `AI_ROLES/ROADMAP.md`.
- [ ] `AI_ROLES/PROJECT_STATE.md` was read.
- [ ] `AI_ROLES/ARCHITECTURE.md` was read.
- [ ] `AI_ROLES/CODING_STANDARDS.md` was read.
- [ ] `AI_ROLES/SECURITY.md` was read when the task handles networking,
      storage, configuration parsing, native code, logging, build systems,
      dependencies, authentication, or user data.
- [ ] The agent understands the previous and next roadmap tasks that affect
      the current task.
- [ ] The task requirements are sufficiently defined.
- [ ] If an important requirement is unclear, the agent stopped and asked
      the human maintainer instead of guessing.
- [ ] Relevant Memory MCP facts were queried when Memory MCP is available.

If any item above is false, implementation must not begin.

---

## 2. Implementation Quality Checklist

Before reporting completion, verify:

- [ ] The implementation matches the task scope and acceptance criteria.
- [ ] No unrelated files were modified.
- [ ] No speculative abstractions, unused code, placeholder production code,
      or unnecessary dependencies were introduced.
- [ ] Naming follows `CODING_STANDARDS.md`.
- [ ] Public Dart APIs have meaningful `///` documentation comments where
      required.
- [ ] Business logic is not placed inside UI widgets.
- [ ] Domain logic remains independent of Flutter UI imports.
- [ ] No `dynamic`, unchecked casts, unsafe null assertions (`!`), or
      ignored errors were introduced without a documented, justified reason.
- [ ] No empty `catch` blocks or silently swallowed errors exist.
- [ ] Recoverable errors have explicit, user-safe handling.
- [ ] The implementation does not introduce unnecessary rebuilds,
      allocations, polling loops, or work on the UI thread.
- [ ] All async work has an explicit lifecycle: cancellation, disposal,
      timeout, error handling, and resource cleanup where applicable.

---

## 3. Required Dart and Flutter Validation

Run the relevant commands from the repository root.

### 3.1 Formatting

```bash
melos run format
Requirements:

 The command passes.
 No formatting changes remain after it runs.
If the task intentionally modifies only non-Dart files, run formatting only
when Dart files exist in the workspace or when the task explicitly requires it.

3.2 Static Analysis and Type Safety
Bash

melos run analyze
Requirements:

 The command passes with zero analyzer errors.
 The command passes with zero lint warnings.
 No analyzer ignore directives were introduced without a narrow scope
and an explanatory comment.
3.3 Unit Tests
Run the applicable workspace tests:

Bash

melos run test
For a specific package when appropriate:

Bash

cd packages/<package_name>
flutter test
or, for a pure Dart package:

Bash

cd packages/<package_name>
dart test
Requirements:

 Existing relevant tests pass.
 New behavior has meaningful tests.
 Edge cases and failure paths are tested where applicable.
 Tests verify public behavior rather than private implementation details.
 The agent does not weaken, delete, skip, or make tests meaningless just
to obtain a passing result.
4. Native Android / VPN Engine Validation
This section is mandatory for every task that modifies any of the following:

Android project files
Kotlin code
VpnService
Platform Channel code
libbox integration
Android manifests or permissions
Gradle configuration
VPN lifecycle behavior
TUN file descriptor handling
Native traffic statistics or native event streams
4.1 Build Validation
At minimum, run the relevant Android build command:

Bash

cd apps/mobile
flutter build apk --debug
If the task affects release build configuration, signing, shrinking,
obfuscation, or release-only code, also run the applicable release build
command when signing requirements are available.

Requirements:

 The Android build passes.
 No Gradle warning related to configuration, SDK compatibility, missing
native dependencies, or manifest validity is ignored without explicit
documentation.
 The generated application can be installed on a physical Android device
when device access is available.
4.2 VPN Lifecycle Validation
For changes involving connection start, stop, reconnect, state events, TUN,
or service lifecycle, validate on a physical Android device whenever possible.

Minimum manual scenarios:

 VPN permission is requested correctly when needed.
 Connecting transitions through expected states without skipping or
duplicating invalid states.
 A successful connection creates exactly one active VPN/TUN session.
 Disconnecting closes the VPN/TUN session and removes the Android VPN
indicator within a reasonable bounded time.
 Reconnecting after a normal disconnect works.
 Reconnecting after a failed connection attempt works.
 App backgrounding does not unexpectedly corrupt the VPN state.
 Force-stopping or revoking VPN permission does not leave a stale
“Connected” state in the Flutter UI.
 No blocking operation runs on Android's main thread.
 No file descriptor, coroutine, thread, service, receiver, or stream
subscription is leaked.
For every unavailable physical-device test, the agent must explicitly report:

What could not be tested.
Why it could not be tested.
The exact command or scenario the human maintainer must run later.
4.3 Native Debug Evidence
When diagnosing or changing native VPN behavior, gather relevant evidence
rather than relying on assumptions.

Recommended commands:

Bash

adb devices
adb logcat -c
adb logcat | grep -iE "Brick|Vpn|VpnService|libbox|sing-box|tun|dns|protect"
If application package access and debug configuration permit it:

Bash

adb shell run-as dev.brickvpn.mobile ls files
Requirements:

 Important claims about runtime behavior are supported by build output,
test output, device logs, or documented platform behavior.
 The agent clearly labels any remaining assumption as UNVERIFIED.
 Sensitive values such as complete server URLs, credentials, tokens, and
private IP addresses are redacted from reports and logs.
5. Security Review Checklist
This section is mandatory for all tasks involving server configurations,
subscriptions, QR imports, networking, DNS, logging, storage, platform
channels, dependencies, CI/CD, release artifacts, or native code.

 No server configuration, credential, URL containing credentials,
private key, token, or user identifier is written to plaintext storage.
 No sensitive value is printed in logs, exceptions, analytics, test
snapshots, screenshots, CI output, or documentation.
 Any logging of potentially sensitive structured objects uses a redaction
utility rather than relying on developers to remember manual redaction.
 Untrusted inputs are validated before use.
 Parsing logic has bounded resource usage and cannot easily cause
unbounded memory growth, recursion, file access, command execution, or
uncontrolled network requests.
 New dependency licenses are compatible with GPL v3.
 New dependencies have been checked for maintenance status and
unnecessary transitive weight.
 No secret, signing key, certificate, keystore, .env file, API token,
server endpoint containing private credentials, or local user data is
staged for Git.
 The task does not introduce telemetry, analytics, remote crash
reporting, tracking SDKs, or external data collection without an
explicit architecture decision and human approval.
6. Self-Review as an Independent Debugger
After tests pass, the agent must perform a deliberate second review from the
perspective of a skeptical senior debugger.

Ask at minimum:

Correctness
 What happens if this method is called twice?
 What happens if it is called before initialization or after disposal?
 What happens if a network operation times out, fails, or returns invalid
data?
 What happens if an event arrives late after the user has disconnected?
 What happens if the app process is recreated while a VPN session exists?
Concurrency and Lifecycle
 Are there race conditions between connect, disconnect, reconnect,
stream events, app lifecycle events, and native callbacks?
 Can an outdated async response overwrite newer state?
 Are streams, timers, controllers, coroutines, file descriptors, and
native resources always disposed?
 Can a task become permanently stuck in Connecting or Disconnecting?
 Is every state transition valid according to the VPN state machine?
Performance
 Does this create avoidable widget rebuilds?
 Does it poll when event-driven updates are available?
 Does it allocate or serialize large data repeatedly?
 Does it perform blocking work on the UI thread or Android main thread?
 Is work bounded for malicious or unusually large configuration input?
Security and Privacy
 Could a malicious config, subscription, QR payload, deep link, or
native event exploit this code path?
 Could an exception leak sensitive information?
 Could this change create a DNS leak, traffic leak, stale TUN interface,
or incorrect VPN status that misleads the user?
Any issue discovered during self-review must be fixed before the task is
reported as ready for human review, unless it requires a human architectural
decision. In that case, the task must be reported as Blocked.

7. Documentation and Project State Updates
Before reporting Ready for Human Review:

 Update AI_ROLES/PROJECT_STATE.md with the current phase, task status,
verified facts, and known blockers.
 Update AI_ROLES/ARCHITECTURE.md only if the task introduced an
approved architectural decision. Do not silently rewrite old decisions.
 Update AI_ROLES/ROADMAP.md only if the human maintainer approved a
roadmap change or the task status needs to be recorded.
 Store durable architecture decisions, inter-module contracts, and
important verified facts in Memory MCP when available.
 Do not store secrets, user configurations, private URLs, tokens, or
sensitive runtime data in Memory MCP.
8. Required Final Report Format
Every AI agent must end its task response with this exact structure:

text

Task Status:
- Ready for Human Review | Blocked | In Progress

Summary:
- What was implemented or investigated.
- Why this approach was chosen.

Files Changed:
- path/to/file — short explanation
- path/to/another_file — short explanation

Verification Performed:
- Command: <command>
  Result: PASS | FAIL | NOT RUN
- Test/Manual Scenario: <scenario>
  Result: PASS | FAIL | NOT RUN

Self-Review:
- Race conditions checked:
- Error paths checked:
- Resource cleanup checked:
- Security/privacy review checked:
- Performance considerations checked:

Known Limitations / Unverified Items:
- List every item that remains unverified.
- Write “None” only if there are genuinely none.

Human Action Required:
- Exact action needed from the maintainer.
- Write “None” only if no human action is required.
Reports must be concise, factual, and honest. Never claim that a command,
test, physical-device scenario, or security review was completed if it was
not actually performed.

9. Completion Gate
A task is eligible for Ready for Human Review only when:

 All applicable sections of this document passed.
 All failed or unavailable checks are explicitly disclosed.
 No critical known bug, security issue, lint issue, test failure, build
failure, or unexplained runtime behavior remains hidden.
 The agent has provided the required final report.
 The human maintainer has enough information to reproduce validation and
make an informed approval decision.
