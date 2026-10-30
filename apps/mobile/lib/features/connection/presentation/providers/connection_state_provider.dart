// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_state_provider.g.dart';

/// Exposes the engine's authoritative connection state stream, reconciled with
/// app lifecycle events.
///
/// **This is the only source the UI is allowed to render connection state
/// from.**
///
/// In Phase 4 (P4-T1), this stream is hardened against OS suspension and
/// background state-desync:
/// 1. Cold start: queries [VpnEngine.getStatus] on initial subscription so the
///    UI immediately displays true native state without waiting for a
///    transition event.
/// 2. Live transitions: forwards [VpnEngine.connectionState] emissions.
/// 3. Resume from background: an [AppLifecycleListener] triggers an explicit
///    [VpnEngine.getStatus] probe on `onResume`, pushing the true native state
///    if the native layer transitioned while the Dart VM was suspended.
///
/// Distinct emissions ensure no redundant UI rebuilds.
@Riverpod(keepAlive: true)
Stream<ConnectionState> connectionState(Ref ref) {
  final engine = ref.watch(vpnEngineProvider);
  final controller = StreamController<ConnectionState>();
  var hasEmitted = false;

  // 1. Initial snapshot from native truth on startup
  unawaited(
    engine
        .getStatus()
        .then((initial) {
          if (!controller.isClosed && !hasEmitted) {
            hasEmitted = true;
            controller.add(initial);
          }
        })
        .catchError((Object error, StackTrace stack) {
          if (!controller.isClosed && !hasEmitted) {
            controller.addError(error, stack);
          }
        }),
  );

  // 2. Stream subsequent engine events
  final sub = engine.connectionState.listen(
    (event) {
      hasEmitted = true;
      if (!controller.isClosed) {
        controller.add(event);
      }
    },
    onError: (Object error, StackTrace stack) {
      if (!controller.isClosed) {
        controller.addError(error, stack);
      }
    },
  );

  // 3. Reconcile with native truth whenever app returns to foreground
  final listener = AppLifecycleListener(
    onResume: () async {
      try {
        final current = await engine.getStatus();
        if (!controller.isClosed) {
          controller.add(current);
        }
      } on Object catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    },
  );

  ref.onDispose(() {
    listener.dispose();
    unawaited(sub.cancel());
    unawaited(controller.close());
  });

  return controller.stream.distinct();
}

/// Exposes the engine's [VpnEngine.trafficStats] stream.
///
/// Separate from [connectionState] on purpose: `VpnEngine` Invariant 2
/// declares them independent failure domains, and funnelling both through a
/// single provider would reintroduce the coupling the invariant exists to
/// prevent. A stats-pipeline failure therefore cannot disturb the connection
/// badge.
@riverpod
Stream<TrafficStats> trafficStats(Ref ref) {
  return ref.watch(vpnEngineProvider).trafficStats;
}
