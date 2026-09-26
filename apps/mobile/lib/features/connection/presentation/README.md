# `connection` feature — `presentation/` layer

Everything the user actually sees and touches. This layer renders state and
dispatches intents; it does not decide anything and it does not know where
the data came from.

## Sub-folders

- `screens/` — top-level page widgets (a full screen or route body).
- `widgets/` — feature-specific reusable widgets (the connect button, the
  state badge, the throughput readout).
- `providers/` — the Riverpod `Notifier`/`AsyncNotifier`s. This is the
  **single** place in the feature where a `VpnEngine` stream (or a use case
  returning a stream) is subscribed to and mapped into UI-facing state. Using
  `AsyncNotifier` here gives loading/error/data handling for free
  (`CODING_STANDARDS.md` Section 4).

## Rules

- Depends **only** on `domain/`. A screen, widget, or provider must never
  `import` anything under `data/`, and must never name a concrete repository
  or data-source class. It references the interface/use case it already
  depends on.
- No business logic. "Can we connect right now?" is a `domain/` use case's
  question; a provider's job is to call it and expose the answer as state.
- MUST NOT infer connection status from a command's return value. A
  `VpnCommandResult` says a command was *accepted*, not that the tunnel is
  up; the authoritative signal is the `connectionState` stream
  (`VpnEngine` Invariant 1, `ARCHITECTURE.md` Section 3). Render from the
  state stream, never optimistically from a button press.
- MUST NOT log raw config/credential objects (see `SECURITY.md` Section 4).

## Reference example

A connect/disconnect toggle screen whose provider exposes the current
`ConnectionState` and dispatches "connect"/"disconnect" intents through a
`domain/` use case. When the engine is swapped from `MockVpnEngine` to the
real native engine in Phase 3, this folder does not change at all — which is
precisely the test that the layering is correct.
