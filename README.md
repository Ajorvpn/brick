# Brick VPN

Brick VPN is an early-stage Flutter and Dart monorepo for an Android-first,
privacy-focused VPN client. The repository currently contains scaffolding,
governance documentation, a six-package Dart workspace, and dependency wiring.
It does not provide working VPN functionality yet.

## Current Status

The project is in Phase 0: Project Governance & Repo Scaffolding. The Android
application is still based on the default Flutter template. VPN lifecycle,
configuration parsing, native integration, and user-facing VPN features are
planned work and are not implemented in this repository state.

Planned protocol support includes VLESS, VMess, Trojan, Shadowsocks, Hysteria2,
and TUIC. These protocols are planned, not currently implemented.

## Development Setup

Required versions are recorded in
[AI_ROLES/TOOLCHAIN_VERSIONS.md](AI_ROLES/TOOLCHAIN_VERSIONS.md). The currently
verified Flutter version is 3.47.4.

From the repository root:

```bash
melos bootstrap
melos run format --no-select
melos run analyze --no-select
melos run test --no-select
```

To run the mobile application locally:

```bash
cd apps/mobile
flutter run
```

This command was verified against a connected Android device (build succeeded,
APK installed, and app launched). It requires a connected Android device or
running emulator; iOS and desktop targets are not verified yet.

The repository also contains a baseline workflow at
[.github/workflows/ci.yml](.github/workflows/ci.yml). It is configured for
pushes to `main` and pull requests; the repository's current GitHub default
branch is `master`.

## Troubleshooting

If the Android build fails with an error like

```text
Build was configured to prefer settings repositories over project repositories
but repository 'maven' was added by settings file 'settings.gradle.kts'
```

the cause is a machine-wide Gradle init script under `~/.gradle/init.d/` that
injects extra Maven repositories into every Gradle build on the machine. This
is a local environment issue, not a defect in this repository. Disable or
remove that init script (for example, rename it so it no longer ends in
`.gradle`) and rebuild. Do not "fix" this by deleting the `allprojects`
repositories block from `apps/mobile/android/build.gradle.kts`; that block is
part of the standard Flutter template and should stay.

## Project Documentation

- Brick VPN is licensed under the GNU GPL v3. See the full text in
	[LICENSE](LICENSE).
- [AI-assisted development governance](AI_ROLES/AGENTS.md)
- [Architecture](AI_ROLES/ARCHITECTURE.md)
- [Roadmap](AI_ROLES/ROADMAP.md)
- [Current project state](AI_ROLES/PROJECT_STATE.md)

## Privacy

Brick VPN is designed with no telemetry or analytics by default. No remote
telemetry service is currently included in the project.

## Issues

Report bugs, documentation problems, and development questions through the
[GitHub issue tracker](https://github.com/Ajorvpn/brick/issues). Please do not
include server credentials, subscription URLs, tokens, or other sensitive
connection data in an issue.
