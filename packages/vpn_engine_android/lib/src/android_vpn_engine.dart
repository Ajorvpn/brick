// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';

import 'vpn_engine_api.g.dart';

/// Implementation of [VpnEngine] for Android using the Gate A native engine
/// via Pigeon platform channels.
final class AndroidVpnEngine implements VpnEngine {
  /// Creates an [AndroidVpnEngine] instance.
  ///
  /// Optional parameters allow injecting fake/mock implementations for
  /// unit testing without touching platform channels.
  AndroidVpnEngine({
    VpnEngineHostApi? hostApi,
    Stream<VpnStateEvent>? stateEventsStream,
    Stream<TrafficStatsEvent>? trafficStatsEventsStream,
    Map<String, dynamic> Function(OutboundConfig config)? outboundSerializer,
  })  : _hostApi = hostApi ?? VpnEngineHostApi(),
        _stateEvents = stateEventsStream ?? stateEvents(),
        _trafficStatsEvents = trafficStatsEventsStream ?? trafficStatsEvents(),
        _outboundSerializer = outboundSerializer ?? buildSingBoxOutbound;

  final VpnEngineHostApi _hostApi;
  final Stream<VpnStateEvent> _stateEvents;
  final Stream<TrafficStatsEvent> _trafficStatsEvents;
  final Map<String, dynamic> Function(OutboundConfig config)
      _outboundSerializer;

  @override
  late final Stream<ConnectionState> connectionState = _stateEvents
      .transform(
        StreamTransformer<VpnStateEvent, ConnectionState>.fromHandlers(
          handleData: (event, sink) {
            sink.add(_mapNativeState(event));
          },
          handleError: (error, stackTrace, sink) {
            sink.add(Error(PlatformError(error.toString())));
          },
        ),
      )
      .distinct()
      .asBroadcastStream();

  @override
  late final Stream<TrafficStats> trafficStats = _trafficStatsEvents
      .transform(
        StreamTransformer<TrafficStatsEvent, TrafficStats>.fromHandlers(
          handleData: (event, sink) {
            if (event.txBytes >= 0 && event.rxBytes >= 0) {
              sink.add(
                TrafficStats(
                  txBytes: event.txBytes,
                  rxBytes: event.rxBytes,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    event.epochMillis,
                  ),
                ),
              );
            }
          },
          handleError: (error, stackTrace, sink) {
            // Invariant 2: stats pipeline errors are absorbed cleanly and
            // never bubble up or corrupt the connection pipeline.
          },
        ),
      )
      .asBroadcastStream();

  @override
  Future<VpnCommandResult> prepare() async {
    try {
      final status = await _hostApi.prepare();
      return _mapConsentStatus(status);
    } on Object catch (_) {
      return const VpnCommandFailed();
    }
  }

  @override
  Future<VpnCommandResult> start(ServerProfile profile) async {
    // sing-box has no AmneziaWG schema; runtime AmneziaWG is unsupported
    // by libbox on Android (see PROJECT_STATE.md Item 5 & TOOLCHAIN_VERSIONS.md).
    if (profile.config is AmneziaWgOutbound) {
      return const VpnCommandRejectedInvalidConfig();
    }

    final Map<String, Object?> outbound;
    try {
      outbound = _outboundSerializer(profile.config);
    } on Object catch (_) {
      return const VpnCommandRejectedInvalidConfig();
    }

    final profileJson = <String, Object?>{
      'id': profile.id,
      'name': profile.name,
      'outbound': outbound,
    };

    try {
      final outcome = await _hostApi.start(profileJson);
      return _mapCommandOutcome(outcome);
    } on Object catch (_) {
      return const VpnCommandFailed();
    }
  }

  @override
  Future<VpnCommandResult> stop() async {
    try {
      final outcome = await _hostApi.stop();
      return _mapCommandOutcome(outcome);
    } on Object catch (_) {
      return const VpnCommandFailed();
    }
  }

  @override
  Future<ConnectionState> getStatus() async {
    try {
      final event = await _hostApi.getStatus();
      return _mapNativeState(event);
    } on Object catch (e) {
      return Error(PlatformError('$e'));
    }
  }

  static ConnectionState _mapNativeState(VpnStateEvent event) {
    switch (event.state) {
      case VpnNativeState.idle:
        return const Disconnected();
      case VpnNativeState.preparing:
      case VpnNativeState.starting:
        return const Connecting();
      case VpnNativeState.running:
        return const Connected();
      case VpnNativeState.stopping:
        return const Disconnecting();
      case VpnNativeState.stopped:
        return const Disconnected();
      case VpnNativeState.error:
        final reason = event.errorReason;
        final detail = reason != null && reason.isNotEmpty
            ? reason
            : 'Unknown native error';
        return Error(PlatformError(detail));
      case VpnNativeState.revoked:
        return const Error(PermissionDenied());
    }
  }

  static VpnCommandResult _mapConsentStatus(VpnConsentStatus status) {
    switch (status) {
      case VpnConsentStatus.alreadyGranted:
      case VpnConsentStatus.granted:
        return const VpnCommandAccepted();
      case VpnConsentStatus.denied:
        return const VpnCommandRejectedPermissionDenied();
      case VpnConsentStatus.noActivity:
        return const VpnCommandFailed();
    }
  }

  static VpnCommandResult _mapCommandOutcome(VpnCommandOutcome outcome) {
    switch (outcome) {
      case VpnCommandOutcome.accepted:
        return const VpnCommandAccepted();
      case VpnCommandOutcome.rejectedBusy:
        return const VpnCommandRejectedBusy();
      case VpnCommandOutcome.rejectedInvalidConfig:
        return const VpnCommandRejectedInvalidConfig();
      case VpnCommandOutcome.rejectedPermissionDenied:
        return const VpnCommandRejectedPermissionDenied();
      case VpnCommandOutcome.failed:
        return const VpnCommandFailed();
    }
  }
}
