// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(connectionState)
final connectionStateProvider = ConnectionStateProvider._();

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

final class ConnectionStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionState>,
          ConnectionState,
          Stream<ConnectionState>
        >
    with $FutureModifier<ConnectionState>, $StreamProvider<ConnectionState> {
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
  ConnectionStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionStateProvider',
        isAutoDispose: false,
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

String _$connectionStateHash() => r'1ffcabd5bcfebbc79ab74009e759be33168d96ea';

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
