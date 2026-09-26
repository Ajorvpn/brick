# `connection` feature — `domain/` layer

The **rules** of the connection feature, written so that they can be tested
with no Flutter, no storage, and no network. This layer is deliberately the
most boring and the most important: it is where "what is allowed to happen"
is decided.

## Sub-folders

- `entities/` — feature-specific entities and value objects that are **not**
  shared across the app. Anything genuinely shared belongs in
  `packages/core_domain` and should be imported from there, never
  re-declared here. The following are ALREADY shared and must be re-used as-is:
  `ConnectionState` (sealed, 5 variants), `ConnectionErrorReason` (sealed, 4
  variants), `TrafficStats`, `ServerProfile`, the `OutboundConfig` hierarchy,
  and `Result<T, E>` from `packages/shared_utils`.
- `usecases/` — single-responsibility use case classes, one decision each
  (e.g. "request connect", "request stop", "observe current connection
  state"). A use case depends on a repository *interface*, never on a concrete
  implementation.

## Rules

- MUST NOT import `presentation/`.
- MUST NOT import anything from `data/`. Dependencies point inward only.
- MUST NOT contain any `package:flutter/...` import. If compiling this layer
  would require a widget binding, the logic is in the wrong layer.
- Repository **interfaces** (the contracts) belong here (or in
  `packages/core_domain` if shared), so that `data/` implements them and
  `presentation/` consumes them without ever naming a concrete data class.
- MUST NOT hold or log raw credentials. Use the `core_domain` value types,
  which intentionally have no `toString()` (`SECURITY.md` Section 4).

## Reference example

The state machine that governs the connection feature — the legal transition
graph documented normatively in `ARCHITECTURE.md` Section 3.1.1 — is domain
logic. It belongs here (or in the shared `core_domain`), not in a provider or
a widget, and it is unit-testable without a single `pumpWidget`.
