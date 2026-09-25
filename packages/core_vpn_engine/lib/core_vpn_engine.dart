// SPDX-License-Identifier: GPL-3.0-or-later

/// Brick VPN core VPN engine abstractions.
///
/// This package is pure Dart by design: it must not depend on Flutter so
/// the same `VpnEngine` contract can be implemented by the Android native
/// bridge, the future iOS extension, the desktop daemon client, and the
/// P1-T5 mock — all testable without a real device. Implementation details
/// live under `lib/src/` and are exported only through this barrel file.
library core_vpn_engine;

export 'src/mock_vpn_engine.dart';
export 'src/vpn_command_result.dart';
export 'src/vpn_engine.dart';
