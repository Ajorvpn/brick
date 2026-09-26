# `connection` feature — `data/` layer

The **plumbing** of the connection feature. This is the only layer in this
feature that is allowed to know a technology exists (secure storage, a
database, an HTTP client, the `VpnEngine` stream).

## Sub-folders

- `datasources/` — thin wrappers around a *technology*. E.g. a wrapper that
  exposes the `trafficStats` / `connectionState` streams from a `VpnEngine`
  instance, or a wrapper over `flutter_secure_storage` for persisting the
  last-selected server profile. A data source does no business logic; it just
  translates between a technology's API and plain domain types.
- `repositories/` — concrete implementations of the repository **contracts**
  declared in `domain/` (or, for contracts shared across features, in
  `packages/core_domain`). A repository coordinates one or more data sources
  and returns domain types, never technology-specific objects.

## Rules

- MAY import `domain/` (that is how it implements the domain's interfaces).
- MUST NOT import `presentation/`.
- MUST NOT contain business rules. If a decision needs making ("can we
  connect right now?"), that decision belongs in a `domain/` use case; the
  data layer only performs I/O and mapping.
- MUST NOT leak credentials into logs or `toString()` (see `SECURITY.md`
  Section 4). Prefer `core_domain` value types, which are already designed
  to avoid incidental printing.
- Server configuration is **High**-sensitivity data (`SECURITY.md` Section 2):
  it must be persisted only through the platform-native secure storage, never
  in plain `SharedPreferences` or a plain file.

## Reference example

The canonical case for this layer is a repository that wraps the
`MockVpnEngine` today and the real native `AndroidVpnEngine` in Phase 3,
with **no change** to `domain/` or `presentation/`. That is the whole point
of the `VpnEngine` abstraction (`ARCHITECTURE.md` Section 3).
