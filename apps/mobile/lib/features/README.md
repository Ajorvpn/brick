# Feature-First Clean Architecture

This folder is the concrete reference for how **every** feature in
`apps/mobile` is organised. It is the app-side implementation of
`ARCHITECTURE.md` Section 4 ("Clean Architecture — Feature Structure") and
the mandatory template in `CODING_STANDARDS.md` Section 3.2.

When you add a new feature, mirror this structure exactly. Do not invent a
fourth layer, and do not let a layer reach "sideways" or "outward" into a
layer that is not allowed below.

---

## 1. Why feature-first (rather than layer-first)

A layer-first layout (`lib/data/`, `lib/domain/`, `lib/presentation/` at the
app root) makes it easy to add a new *file* to the app and hard to see what a
single feature actually needs. Every feature-first folder answers "what does
this feature consist of, and what does it depend on?" in one glance, and it
keeps a feature's code physically co-located so it can be reviewed, tested,
or deleted as a unit.

## 2. The three layers (and what belongs in each)

### `presentation/` — UI only
Screens, widgets, and the Riverpod `Notifier`/`AsyncNotifier` providers that
expose state to the UI. Knows how to *render* a state and how to *dispatch an
intent*; it does not decide business rules, and it does not know where data
comes from.

- `screens/` — top-level page widgets
- `widgets/` — feature-specific reusable widgets
- `providers/` — Riverpod `Notifier`/`AsyncNotifier`s (the single place where
  a `VpnEngine` stream is subscribed to and mapped into UI state)

### `domain/` — the rules (framework-agnostic)
Feature-specific entities and value objects that are **not** shared across the
app, plus single-responsibility use cases. Shared entities and value types
(`ConnectionState`, `TrafficStats`, `ServerProfile`, `OutboundConfig`, ...)
already live in `packages/core_domain` and are **re-used**, not re-declared
here.

- `entities/` — feature-specific entities (only if NOT shared)
- `usecases/` — single-responsibility use case classes

### `data/` — the plumbing (swappable implementations)
Concrete `Repository` implementations and the data sources they wrap
(`VpnEngine` streams, `flutter_secure_storage`, local DB, subscription
fetching). This is the only layer that knows a technology exists.

- `repositories/` — concrete `Repository` implementations
- `datasources/` — wraps `core_vpn_engine`, local storage, etc.

---

## 3. The strict layering rule

```
presentation/  ──depends-on──>  domain/  <──implemented-by──  data/
     │                              ▲                              │
     └────── MUST NOT import ───────┘<───── may depend on ───────┘
                  data/  directly
```

- `presentation/` depends **only** on `domain/`. A widget or provider must
  never `import` anything under `data/` directly.
- `domain/` must **never** import `presentation/`, nor any
  `package:flutter/...` import at all. Domain logic is framework-agnostic and
  unit-testable with no widget tree.
- `data/` may depend on `domain/` (to implement its contracts) but **never**
  on `presentation/`.

If a screen needs a repository, the repository **interface** is declared in
`domain/` (or, for cross-feature sharing, in `packages/core_domain`) and only
its **implementation** lives in `data/`. `presentation/` is handed the
implementation through Riverpod dependency injection, so it references the
interface it already depends on and never names the concrete data class.

---

## 4. Why this rule exists

1. **Testability.** A `domain/` use case can be unit-tested with a fake
   repository and no Flutter binding; a screen is only tested for rendering.
2. **Decoupling the UI from storage/network drivers.** Swapping a
   `flutter_secure_storage` backend for an encrypted-file backend, or swapping
   the mock `VpnEngine` for the real native one, must not touch a single
   widget. The `VpnEngine` abstraction (see `ARCHITECTURE.md` Section 3) is the
   seam that makes this possible.
3. **Surfaces architecture drift at review time.** A forbidden
   `data -> presentation` or `presentation -> data` import is visible in a
   single diff and is a clear, mechanical thing to reject in code review.

## 5. Rules for AI Agents / contributors

- Mirror this structure for every new feature; do not add a fourth layer.
- Do not put business logic in `presentation/`.
- Do not put Flutter/widget imports in `domain/`.
- Do not import `data/` from `presentation/`.
- Re-use entities from `packages/core_domain`; only add to a feature's
  `domain/` what is genuinely feature-specific.
- Read the per-layer `README.md` in the reference feature
  (`features/connection/`) before adding files to it.
