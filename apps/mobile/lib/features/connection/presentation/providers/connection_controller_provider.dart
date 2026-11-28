// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart'
    show
        AmneziaWgOutbound,
        Connected,
        Connecting,
        ConnectionState,
        Disconnected,
        Disconnecting,
        Error,
        ServerProfile;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:mobile/core/providers/server_profile_repository_provider.dart';
import 'package:mobile/core/providers/vpn_engine_provider.dart';
import 'package:mobile/features/connection/domain/entities/connection_location_target.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart'
    show SavedServer, SavedServerProfile;
import 'package:mobile/features/connection/domain/services/connection_candidate_pool_builder.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/connection/presentation/providers/kill_switch_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection_controller_provider.g.dart';

/// Dispatches connect/disconnect intents to the engine.
///
/// This notifier holds **no** connection state of its own. It exists purely
/// to turn a button press into an engine command, and it deliberately does
/// not publish a "connecting"/"connected" value: the UI reads that from
/// `connectionStateProvider`, which is the authoritative stream
/// (`VpnEngine` Invariant 1). If this class also tracked state, the two
/// sources could disagree and the UI would have to pick a winner — the exact
/// design failure that produced the legacy prototype's false "Connected".
///
/// The in-flight guard is the one piece of state kept here, and it guards
/// against a *duplicate command*, not against describing the tunnel: it stops
/// a second tap while the first command is still being dispatched. It is not
/// rendered as connection state.
@riverpod
class ConnectionController extends _$ConnectionController {
  /// Guards against re-dispatching while a command is in flight.
  bool _busy = false;

  /// Tracks the ID of the server currently connecting or connected.
  String? _activeConnectingServerId;

  /// Tracks the storage key of the location target (`auto` or `country:<ISO2>`)
  /// currently connecting or connected.
  String? _activeConnectingTargetKey;

  /// No initial state: this notifier exists only to dispatch commands.
  ///
  /// The exposed state is a never-awaited `AsyncValue<void>` placeholder. It
  /// carries no connection information, which is the point — if this
  /// notifier held a real value, the UI could read it *instead of* the
  /// authoritative stream and recreate the legacy false-"Connected" bug.
  @override
  FutureOr<void> build() {
    ref.keepAlive();
    ref.listen<AsyncValue<ConnectionState>>(connectionStateProvider, (
      previous,
      next,
    ) {
      final state = next.value;
      if (state is Disconnected || state is Error) {
        _activeConnectingServerId = null;
        _activeConnectingTargetKey = null;
      } else if (state is Connected || state is Connecting) {
        _activeConnectingServerId ??= ref.read(activeServerProvider)?.id;
        _activeConnectingTargetKey ??= ref
            .read(resolvedLocationTargetProvider)
            .storageKey;
      }
    });

    ref.listen<SavedServerProfile?>(activeServerProvider, (previous, next) {
      final conn =
          ref.read(connectionStateProvider).value ??
          ref.read(initialConnectionStateProvider);
      if (conn is Connected || conn is Connecting) {
        _activeConnectingServerId ??= next?.id;
      }
    });

    final initialConn =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    if (initialConn is Connected || initialConn is Connecting) {
      _activeConnectingServerId ??= ref.read(activeServerProvider)?.id;
      _activeConnectingTargetKey ??= ref
          .read(resolvedLocationTargetProvider)
          .storageKey;
    }
  }

  /// Whether a command is currently being dispatched.
  bool get isBusy => _busy;

  /// The ID of the server currently connecting or connected, if any.
  String? get activeConnectingServerId => _activeConnectingServerId;

  /// The storage key of the location target currently connecting or connected.
  String? get activeConnectingTargetKey => _activeConnectingTargetKey;

  /// Requests a tunnel start for a high-level [target] (`Smart Auto` or
  /// a specific country's scoped `urltest` pool).
  Future<VpnCommandResult> connectForTarget(
    ConnectionLocationTarget target,
  ) async {
    final savedList =
        ref.read(savedServersProvider).asData?.value ??
        await ref
            .read(savedServersProvider.future)
            .catchError((Object _) => const <SavedServer>[]);
    final eligibleProfiles = savedList
        .whereType<SavedServerProfile>()
        .map((entry) => entry.profile)
        .where((profile) => profile.config is! AmneziaWgOutbound)
        .toList(growable: false);
    switch (target) {
      case SmartAutoTarget():
        final fallbackActive = ref.read(activeServerProvider)?.profile;
        final primary =
            (fallbackActive != null &&
                fallbackActive.config is! AmneziaWgOutbound)
            ? fallbackActive
            : (eligibleProfiles.isNotEmpty
                  ? eligibleProfiles.first
                  : fallbackActive);
        return await connect(
          primary,
          candidateProfiles: eligibleProfiles.isNotEmpty
              ? eligibleProfiles
              : null,
          targetStorageKey: target.storageKey,
        );
      case CountryTarget(:final countryCode):
        final normalizedCode = countryCode.trim().toUpperCase();
        final countryProfiles = eligibleProfiles
            .where(
              (profile) =>
                  ServerLocationParser.parse(profile.name).countryCode ==
                  normalizedCode,
            )
            .toList(growable: false);
        if (countryProfiles.isEmpty) {
          return const VpnCommandFailed();
        }
        return await connect(
          countryProfiles.first,
          candidateProfiles: countryProfiles,
          targetStorageKey: target.storageKey,
          restrictToCountryCode: normalizedCode,
        );
    }
  }

  /// Requests a tunnel start for [profile].
  ///
  /// The returned `Future` completes with the [VpnCommandResult] from the
  /// engine (or a rejection if busy / no profile). Callers must not treat its
  /// completion as a connection; watch `connectionStateProvider` instead.
  ///
  /// When the active engine implements [PoolVpnEngine] and at least two valid
  /// profiles are available (from [candidateProfiles] or loaded saved servers),
  /// starts a native `urltest` failover pool with [profile] prioritized first.
  ///
  /// If another server or location target is currently connected or connecting,
  /// cleanly stops it first before preparing and starting [profile].
  Future<VpnCommandResult> connect(
    ServerProfile? profile, {
    List<ServerProfile>? candidateProfiles,
    String? targetStorageKey,
    String? restrictToCountryCode,
  }) async {
    if (profile == null) {
      return const VpnCommandFailed();
    }
    if (_busy) {
      return const VpnCommandRejectedBusy();
    }
    _busy = true;
    try {
      final engine = ref.read(vpnEngineProvider);
      final repoFuture = ref.read(serverProfileRepositoryProvider.future);
      final currentState =
          ref.read(connectionStateProvider).value ??
          ref.read(initialConnectionStateProvider);
      // A live reconnect loop is a session too: without this the coordinator
      // keeps restarting the OLD profile underneath the new start.
      final autoReconnectState = ref.read(autoReconnectProvider);
      final hasActiveOrReconnectingSession =
          currentState is Connected ||
          currentState is Connecting ||
          autoReconnectState.isReconnecting;
      if (hasActiveOrReconnectingSession) {
        final currentActiveId =
            _activeConnectingServerId ?? ref.read(activeServerProvider)?.id;
        final currentTargetKey =
            _activeConnectingTargetKey ??
            ref.read(resolvedLocationTargetProvider).storageKey;
        final isDifferentServer =
            currentActiveId != null && currentActiveId != profile.id;
        final isDifferentTarget =
            targetStorageKey != null && currentTargetKey != targetStorageKey;
        if (isDifferentServer ||
            isDifferentTarget ||
            autoReconnectState.isReconnecting) {
          ref.read(autoReconnectProvider.notifier).onUserInitiatedDisconnect();
          ref.read(killSwitchProvider.notifier).onUserInitiatedDisconnect();
          await engine.stop();
          // Native accepts Stopping immediately; wait for the terminal state so
          // the new start cannot race the old session's teardown.
          await _waitUntilStopped(engine);
        } else {
          return const VpnCommandRejectedBusy();
        }
      }

      final prepareResult = await engine.prepare();
      if (prepareResult is! VpnCommandAccepted) {
        _activeConnectingServerId = null;
        _activeConnectingTargetKey = null;
        ref.read(autoReconnectProvider.notifier).onUserInitiatedDisconnect();
        ref.read(killSwitchProvider.notifier).onUserInitiatedDisconnect();
        return prepareResult;
      }

      final pool = _resolveCandidatePool(
        primary: profile,
        candidateProfiles: candidateProfiles,
        engine: engine,
        restrictToCountryCode: restrictToCountryCode,
      );
      final VpnCommandResult startResult;
      if (engine is PoolVpnEngine && pool.length >= 2) {
        startResult = await engine.startPool(profile, pool);
      } else {
        startResult = await engine.start(profile);
      }
      if (startResult is! VpnCommandAccepted) {
        _activeConnectingServerId = null;
        _activeConnectingTargetKey = null;
        ref.read(autoReconnectProvider.notifier).onUserInitiatedDisconnect();
        ref.read(killSwitchProvider.notifier).onUserInitiatedDisconnect();
        return startResult;
      }

      _activeConnectingServerId = profile.id;
      _activeConnectingTargetKey =
          targetStorageKey ??
          ref.read(resolvedLocationTargetProvider).storageKey;
      ref
          .read(autoReconnectProvider.notifier)
          .onUserInitiatedConnect(
            profile,
            candidates: pool.length >= 2 ? pool : null,
          );
      ref.read(killSwitchProvider.notifier).onUserInitiatedConnect(profile);

      try {
        final repo = await repoFuture;
        await repo.save(profile.copyWith(lastUsedAt: DateTime.now().toUtc()));
        if (ref.mounted) {
          ref.invalidate(savedServersProvider);
        }
      } on Object {
        // Graceful fallback: storage failure must not disrupt active tunnel.
      }

      return startResult;
    } on Object {
      _activeConnectingServerId = null;
      _activeConnectingTargetKey = null;
      ref.read(autoReconnectProvider.notifier).onUserInitiatedDisconnect();
      ref.read(killSwitchProvider.notifier).onUserInitiatedDisconnect();
      return const VpnCommandFailed();
    } finally {
      _busy = false;
    }
  }

  /// Resolves the failover candidate pool for [PoolVpnEngine] instances.
  ///
  /// Returns an empty list for plain [VpnEngine] implementations or when fewer
  /// than two valid candidates are available (so callers use single `start()`).
  List<ServerProfile> _resolveCandidatePool({
    required ServerProfile primary,
    required List<ServerProfile>? candidateProfiles,
    required VpnEngine engine,
    String? restrictToCountryCode,
  }) {
    if (engine is! PoolVpnEngine) {
      return const <ServerProfile>[];
    }
    final List<ServerProfile> sourceServers;
    if (candidateProfiles != null) {
      sourceServers = candidateProfiles;
    } else {
      final saved = ref.read(savedServersProvider).asData?.value;
      sourceServers = saved == null
          ? const <ServerProfile>[]
          : saved
                .whereType<SavedServerProfile>()
                .map((entry) => entry.profile)
                .toList(growable: false);
    }
    return ConnectionCandidatePoolBuilder.buildCandidatePool(
      primary: primary,
      allServers: sourceServers,
      restrictToCountryCode: restrictToCountryCode,
    );
  }

  /// Awaits the engine's terminal stopped state, bounded.
  ///
  /// `VpnEngine.stop()` is accepted as soon as the native service enters
  /// `Stopping` (it logs `state -> Stopping` and returns). Calling
  /// `prepare()` / `start()` in that window races `Stopped` + `onDestroy`, and
  /// a `BrickVpnService` teardown finishing after the new `ACTION_START` used
  /// to destroy the service out from under it.
  ///
  /// Returns immediately when the engine is already [Disconnected] / [Error]
  /// (the common synchronous path, including fake engines that emit nothing),
  /// and also when no teardown is in flight ([Disconnecting] not observed) -
  /// there is nothing observable to await, and blocking there would wedge the
  /// command path.
  Future<void> _waitUntilStopped(VpnEngine engine) async {
    final current =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    if (current is Disconnected || current is Error) return;
    // Only a published teardown ([Disconnecting]) is awaitable. When the
    // engine has not reported one yet there is no observable stop to wait for,
    // and the native layer serializes the start behind an in-flight teardown
    // itself (`BrickVpnService.requestStart`), so blocking here would only
    // wedge the command path (including hand-driven test engines).
    if (current is! Disconnecting) return;
    try {
      await engine.connectionState
          .firstWhere((state) => state is Disconnected || state is Error)
          .timeout(const Duration(seconds: 3));
    } on Object {
      // Bounded: a slow or silent teardown must never wedge the switch.
    }
  }

  /// Requests a tunnel stop.
  ///
  /// Same acceptance semantics as [connect]: completion means the stop was
  /// accepted, not that the tunnel is down. See `connectionStateProvider`.
  Future<VpnCommandResult> disconnect() async {
    if (_busy) {
      return const VpnCommandRejectedBusy();
    }
    _busy = true;
    try {
      ref.read(autoReconnectProvider.notifier).onUserInitiatedDisconnect();
      ref.read(killSwitchProvider.notifier).onUserInitiatedDisconnect();
      final engine = ref.read(vpnEngineProvider);
      final result = await engine.stop();
      _activeConnectingServerId = null;
      _activeConnectingTargetKey = null;
      return result;
    } on Object {
      _activeConnectingServerId = null;
      _activeConnectingTargetKey = null;
      return const VpnCommandFailed();
    } finally {
      _busy = false;
    }
  }
}
