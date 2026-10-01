// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Exposes the engine's authoritative [VpnEngine.connectionState] stream.
///
/// This is the **only** source the UI is allowed to render connection state
/// from. `VpnEngine` Invariant 1 (`vpn_engine.dart`) states that `start()`
/// and `stop()` report only whether a command was *accepted*, and that the
/// real lifecycle transition arrives exclusively on this stream; the
/// legacy prototype coupled the two and displayed "Connected" over a dead
/// tunnel, which is the exact bug `connection/presentation/README.md`
/// forbids repeating.
///
/// Reading `vpnEngineProvider` here (rather than accepting the engine as a
/// parameter) keeps this provider working under a plain
/// `overrideWithValue` in tests while still resolving the real keepAlive
/// engine in the app.

@ProviderFor(connectionState)
final connectionStateProvider = ConnectionStateProvider._();

/// Exposes the engine's authoritative [VpnEngine.connectionState] stream.
///
/// This is the **only** source the UI is allowed to render connection state
/// from. `VpnEngine` Invariant 1 (`vpn_engine.dart`) states that `start()`
/// and `stop()` report only whether a command was *accepted*, and that the
/// real lifecycle transition arrives exclusively on this stream; the
/// legacy prototype coupled the two and displayed "Connected" over a dead
/// tunnel, which is the exact bug `connection/presentation/README.md`
/// forbids repeating.
///
/// Reading `vpnEngineProvider` here (rather than accepting the engine as a
/// parameter) keeps this provider working under a plain
/// `overrideWithValue` in tests while still resolving the real keepAlive
/// engine in the app.

final class ConnectionStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionState>,
          ConnectionState,
          Stream<ConnectionState>
        >
    with $FutureModifier<ConnectionState>, $StreamProvider<ConnectionState> {
  /// Exposes the engine's authoritative [VpnEngine.connectionState] stream.
  ///
  /// This is the **only** source the UI is allowed to render connection state
  /// from. `VpnEngine` Invariant 1 (`vpn_engine.dart`) states that `start()`
  /// and `stop()` report only whether a command was *accepted*, and that the
  /// real lifecycle transition arrives exclusively on this stream; the
  /// legacy prototype coupled the two and displayed "Connected" over a dead
  /// tunnel, which is the exact bug `connection/presentation/README.md`
  /// forbids repeating.
  ///
  /// Reading `vpnEngineProvider` here (rather than accepting the engine as a
  /// parameter) keeps this provider working under a plain
  /// `overrideWithValue` in tests while still resolving the real keepAlive
  /// engine in the app.
  ConnectionStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionStateHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionState> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionState> create(Ref ref) {
    return connectionState(ref);
  }
}

String _$connectionStateHash() => r'8dc8798836389d951a9e92cd3bada3a83649ef81';

/// Exposes the engine's [VpnEngine.trafficStats] stream.
///
/// Separate from [connectionState] on purpose: `VpnEngine` Invariant 2
/// declares them independent failure domains, and funnelling both through a
/// single provider would reintroduce the coupling the invariant exists to
/// prevent. A stats-pipeline failure therefore cannot disturb the connection
/// badge.

@ProviderFor(trafficStats)
final trafficStatsProvider = TrafficStatsProvider._();

/// Exposes the engine's [VpnEngine.trafficStats] stream.
///
/// Separate from [connectionState] on purpose: `VpnEngine` Invariant 2
/// declares them independent failure domains, and funnelling both through a
/// single provider would reintroduce the coupling the invariant exists to
/// prevent. A stats-pipeline failure therefore cannot disturb the connection
/// badge.

final class TrafficStatsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TrafficStats>,
          TrafficStats,
          Stream<TrafficStats>
        >
    with $FutureModifier<TrafficStats>, $StreamProvider<TrafficStats> {
  /// Exposes the engine's [VpnEngine.trafficStats] stream.
  ///
  /// Separate from [connectionState] on purpose: `VpnEngine` Invariant 2
  /// declares them independent failure domains, and funnelling both through a
  /// single provider would reintroduce the coupling the invariant exists to
  /// prevent. A stats-pipeline failure therefore cannot disturb the connection
  /// badge.
  TrafficStatsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trafficStatsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trafficStatsHash();

  @$internal
  @override
  $StreamProviderElement<TrafficStats> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TrafficStats> create(Ref ref) {
    return trafficStats(ref);
  }
}

String _$trafficStatsHash() => r'7a99fd8b98367dd0aef42b1b330bfe754734296d';
