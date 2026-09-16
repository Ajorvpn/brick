# CODING_STANDARDS.md — Brick VPN Code Style & Structure Rules

> Concrete, mechanical rules for how code is written in this repository. 
> Where `ARCHITECTURE.md` explains *why* a structure exists, this file 
> explains *exactly how* to write code that conforms to it. When in 
> doubt, consistency with existing code in this repo wins over personal 
> preference.

---

## 1. Language & Formatting

- **Dart** is the only language for application code (native bridge code 
  in `native/` follows its own platform conventions — Kotlin style guide 
  for Android, Swift style guide for iOS, standard Go formatting for 
  desktop FFI libraries).
- Format all Dart code with `dart format` before considering any task 
  complete. No exceptions, no manual formatting overrides.
- Linting is enforced via `very_good_analysis`. Zero lint warnings are 
  allowed in committed code. If a lint rule seems wrong for a specific, 
  justified case, use a scoped `// ignore: rule_name` with a comment 
  explaining why — never disable rules repo-wide without discussing it 
  first.
- Maximum line length: 80 characters (default with `dart format`). Do 
  not fight the formatter.

---

## 2. Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Packages / directories | `snake_case` | `core_vpn_engine`, `config_parser` |
| Dart files | `snake_case.dart` | `vpn_connection_state.dart` |
| Classes, enums, extension types | `PascalCase` | `VpnConnectionState`, `TrafficStatsRepository` |
| Variables, functions, parameters | `camelCase` | `connectionState`, `parseSubscriptionUrl()` |
| Constants | `camelCase` (Dart convention — NOT `SCREAMING_CASE`) | `defaultTimeoutDuration` |
| Private members | prefixed with `_` | `_activeConnection` |
| Riverpod providers | suffixed with `Provider` | `vpnConnectionStateProvider` |
| Test files | mirror source file name with `_test.dart` suffix | `vpn_connection_state_test.dart` |

**Naming must be descriptive of intent, not implementation.** 
E.g., prefer `activeServerConfig` over `currentData`. Avoid abbreviations 
unless they are universally understood in this domain (e.g., `Vpn`, 
`Dns`, `Tun` are acceptable; `cfg` for `config` is not).

---

## 3. Package & Feature Structure (Mandatory Template)

### 3.1 Pure Dart Packages (`packages/core_domain`, `packages/config_parser`, etc.)
packages/<package_name>/
├── lib/
│ ├── <package_name>.dart # Barrel file: public exports only
│ └── src/
│ └── ... # Implementation details, NOT exported
│ # directly — only via the barrel file
├── test/
│ └── ... # Mirrors lib/src/ structure exactly
└── pubspec.yaml # Must include resolution: workspace

text


Anything under `lib/src/` is considered a private implementation detail 
of the package. Only what is explicitly re-exported in the top-level 
barrel file (`lib/<package_name>.dart`) is public API for other packages 
to consume.

### 3.2 Feature Structure Inside the App (`apps/mobile/lib/features/<feature>/`)
features/<feature_name>/
├── data/
│ ├── repositories/ # Concrete Repository implementations
│ └── datasources/ # Wraps core_vpn_engine, local storage, etc.
├── domain/
│ ├── entities/ # Feature-specific entities (only if NOT
│ │ # shared — shared entities live in
│ │ # packages/core_domain)
│ └── usecases/ # Single-responsibility use case classes
└── presentation/
├── screens/ # Top-level page widgets
├── widgets/ # Feature-specific reusable widgets
└── providers/ # Riverpod Notifiers/AsyncNotifiers

text


**Strict layering rule**: 
- `presentation/` may depend on `domain/` and `data/`.
- `domain/` must NEVER import anything from `presentation/` or Flutter 
  (`package:flutter/...`). Domain logic must be framework-agnostic and 
  unit-testable without a widget tree.
- `data/` may depend on `domain/` (to implement its interfaces) but not 
  on `presentation/`.

---

## 4. State Management Rules (Riverpod)

- Use **code generation** (`@riverpod` annotation via `riverpod_generator`) 
  for all providers — do not hand-write legacy `StateNotifierProvider` 
  boilerplate.
- Prefer `AsyncNotifier`/`Notifier` over plain `Provider` + manual state 
  classes, to get built-in loading/error/data state handling.
- **One Notifier = one clear responsibility.** Do not create "god 
  notifiers" that manage unrelated pieces of state (this directly 
  prevents the kind of tangled, hard-to-debug state coupling that 
  affected the predecessor project's traffic stats and connection state).
- UI widgets must be `ConsumerWidget` / `ConsumerStatefulWidget` and must 
  only read the specific providers they need (`ref.watch(x)`), never 
  broad "everything" providers, to avoid unnecessary rebuilds.

---

## 5. Error Handling

- Do not use exceptions for expected, recoverable failure states (e.g., 
  "invalid subscription URL", "server unreachable"). Use a `Result`-style 
  sealed class (`Success<T>` / `Failure<E>`) defined in 
  `packages/shared_utils`, returned explicitly from repository/use-case 
  methods.
- Reserve thrown exceptions for truly unexpected, programmer-error 
  conditions (e.g., invariant violations, null where guaranteed non-null).
- Every `Future`/`Stream` that can fail must have its failure path 
  explicitly handled at the point it's consumed in the UI layer — no 
  unhandled `Future` errors, no swallowed exceptions with an empty catch 
  block. This directly addresses the predecessor project's pattern of 
  silently swallowing native bridge failures.

---

## 6. Native Bridge Code (Android/Kotlin — applies to `native/android/`)

- Kotlin code follows the [official Kotlin style guide](https://kotlinlang.org/docs/coding-conventions.html).
- Every function that crosses the Platform Channel boundary (Dart ↔ 
  Kotlin) must have explicit, typed error propagation back to Dart — 
  never a silent `catch (e: Exception) { /* ignored */ }`.
- All blocking/long-running native calls (libbox `start`, `stop`, 
  `disconnect`) must run on a dedicated Kotlin Coroutine dispatcher, 
  never on the main thread — see `ARCHITECTURE.md` Section 3.5 for the 
  full list of mandatory native engineering rules.

---

## 7. Testing Conventions

- Every package in `packages/` must have meaningful unit test coverage 
  for its public API before a task touching it is considered done (see 
  `DEFINITION_OF_DONE.md`).
- Test file structure mirrors source structure exactly (see Section 3.1).
- Use descriptive test names in the form: 
  `test('should <expected behavior> when <condition>', () { ... })`.
- Prefer testing behavior through the public API of a package/class, not 
  its private internals.
- For the VPN engine abstraction (`core_vpn_engine`), platform-specific 
  implementations must be tested via a fake/mock implementation of the 
  `VpnEngine` interface — the domain and presentation layers must be 
  fully testable without a real device or real native code.

---

## 8. Comments & Documentation

- Public classes/functions require a `///` doc comment explaining 
  purpose and any non-obvious reasoning (per `AGENTS.md` Rule 7).
- Inline comments (`//`) are reserved for explaining *why* a non-obvious 
  piece of logic exists (e.g., a workaround for a platform quirk), never 
  for restating *what* the next line does.
- TODOs must include context: `// TODO(phase-6): implement retry logic 
  once CommandClient reconnection strategy is finalized` — a bare `// 
  TODO` with no context is not acceptable.

---

## 9. Dependency Hygiene

- Before adding any new third-party package dependency, verify:
  1. It is actively maintained (recent commits/releases)
  2. It has a compatible license (must not conflict with GPL v3)
  3. It does not introduce unnecessary transitive bloat for a 
     performance-sensitive mobile app
- Prefer official/first-party packages (`go_router`, packages published 
  by `flutter.dev`, `riverpod`) over lesser-known alternatives when 
  functionality is equivalent.
- Never add a dependency "just in case" for future use — see `AGENTS.md` 
  Rule 8 (No Speculative Abstraction).

## 10. License Headers

- Every new source file added from Phase 1 onward must include a concise SPDX
  header comment declaring `SPDX-License-Identifier: GPL-3.0-or-later`.
- Existing source files are not retroactively modified as part of this policy
  decision; header coverage will be applied when those files are next changed
  or through a separately approved mechanical task.