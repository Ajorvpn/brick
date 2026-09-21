// SPDX-License-Identifier: GPL-3.0-or-later

/// Brick VPN core domain entities.
///
/// This package is pure Dart by design: it must not depend on Flutter so the
/// domain vocabulary can be shared by the engine, storage, and UI layers.
/// Implementation details live under `lib/src/` and are exported only
/// through this barrel file.
library core_domain;

export 'src/connection_state.dart';
export 'src/traffic_stats.dart';
export 'src/protocol_type.dart';
export 'src/composition_types.dart';
export 'src/outbound_config.dart';
export 'src/server_profile.dart';
