// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:config_parser/config_parser.dart';
import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/services.dart' show EventChannel;

import 'vpn_engine_api.g.dart';

/// Implementation of [VpnEngine] and [PoolVpnEngine] for Android using the
/// Gate A native engine via Pigeon platform channels.
final class AndroidVpnEngine implements PoolVpnEngine {
  /// Maximum number of candidate outbounds forwarded to native `urltest`.
  static const int kMaxUrlTestCandidates = 10;

  /// Creates an [AndroidVpnEngine] instance.
  ///
  /// Optional parameters allow injecting fake/mock implementations for
  /// unit testing without touching platform channels.
  AndroidVpnEngine({
    VpnEngineHostApi? hostApi,
    Stream<VpnStateEvent>? stateEventsStream,
    Stream<TrafficStatsEvent>? trafficStatsEventsStream,
    Stream<String>? logEventsStream,
    Map<String, dynamic> Function(OutboundConfig config)? outboundSerializer,
  })  : _hostApi = hostApi ?? VpnEngineHostApi(),
        _stateEvents = stateEventsStream ?? stateEvents(),
        _trafficStatsEvents = trafficStatsEventsStream ?? trafficStatsEvents(),
        _logEvents = logEventsStream ??
            const EventChannel('dev.brickvpn.harness/log_events')
                .receiveBroadcastStream()
                .map((dynamic event) => event.toString()),
        _outboundSerializer = outboundSerializer ?? buildSingBoxOutbound;

  final VpnEngineHostApi _hostApi;
  final Stream<VpnStateEvent> _stateEvents;
  final Stream<TrafficStatsEvent> _trafficStatsEvents;
  final Stream<String> _logEvents;
  final Map<String, dynamic> Function(OutboundConfig config)
      _outboundSerializer;

  @override
  Stream<String> get logEvents => _logEvents;

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
    if (!_isValidRuntimeOutbound(profile.config)) {
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
  Future<VpnCommandResult> startPool(
    ServerProfile primary,
    List<ServerProfile> candidates,
  ) async {
    // sing-box has no AmneziaWG schema; runtime AmneziaWG is unsupported
    // by libbox on Android (see PROJECT_STATE.md Item 5 & TOOLCHAIN_VERSIONS.md).
    if (primary.config is AmneziaWgOutbound) {
      return const VpnCommandRejectedInvalidConfig();
    }

    final serializedCandidates = <Map<String, Object?>>[];
    final seenIds = <String>{primary.id};
    ServerProfile effectivePrimary = primary;
    Map<String, Object?>? primaryOutbound =
        _trySerializeRuntimeOutbound(primary);
    if (primaryOutbound != null) {
      serializedCandidates.add(primaryOutbound);
    } else if (candidates.isEmpty) {
      return const VpnCommandRejectedInvalidConfig();
    }

    for (final candidate in candidates) {
      if (serializedCandidates.length >= kMaxUrlTestCandidates) {
        break;
      }
      if (!seenIds.add(candidate.id)) {
        continue;
      }
      final serialized = _trySerializeRuntimeOutbound(candidate);
      if (serialized == null) {
        continue;
      }
      if (primaryOutbound == null) {
        effectivePrimary = candidate;
        primaryOutbound = serialized;
      }
      serializedCandidates.add(serialized);
    }

    if (primaryOutbound == null) {
      return const VpnCommandRejectedInvalidConfig();
    }

    final profileJson = <String, Object?>{
      'id': effectivePrimary.id,
      'name': effectivePrimary.name,
      'outbound': primaryOutbound,
      if (serializedCandidates.length >= 2) 'candidates': serializedCandidates,
    };

    try {
      final outcome = await _hostApi.start(profileJson);
      return _mapCommandOutcome(outcome);
    } on Object catch (_) {
      return const VpnCommandFailed();
    }
  }

  Map<String, Object?>? _trySerializeRuntimeOutbound(ServerProfile profile) {
    if (!_isValidRuntimeOutbound(profile.config)) {
      return null;
    }
    try {
      return _outboundSerializer(profile.config);
    } on Object catch (_) {
      return null;
    }
  }

  static bool _isValidRuntimeOutbound(OutboundConfig config) {
    // sing-box has no AmneziaWG schema; runtime AmneziaWG is unsupported
    // by libbox on Android (see PROJECT_STATE.md Item 5 & TOOLCHAIN_VERSIONS.md).
    if (config is AmneziaWgOutbound) {
      return false;
    }
    if (config is ShadowsocksOutbound) {
      return _isValidShadowsocksRuntimeKey(config.method, config.password);
    }
    return true;
  }

  static bool _isValidShadowsocksRuntimeKey(String method, String password) {
    final normalizedMethod = method.trim().toLowerCase();
    if (!normalizedMethod.startsWith('2022-blake3-')) {
      return true;
    }
    final int requiredBytes;
    final bool allowMultiKey;
    switch (normalizedMethod) {
      case '2022-blake3-aes-128-gcm':
        requiredBytes = 16;
        allowMultiKey = true;
      case '2022-blake3-aes-256-gcm':
        requiredBytes = 32;
        allowMultiKey = true;
      case '2022-blake3-chacha20-poly1305':
        requiredBytes = 32;
        allowMultiKey = false;
      default:
        return false;
    }
    if (password.isEmpty) {
      return false;
    }
    final parts = password.split(':');
    if (!allowMultiKey && parts.length > 1) {
      return false;
    }
    for (final part in parts) {
      if (part.isEmpty || part.length % 4 != 0) {
        return false;
      }
      try {
        final decoded = base64Decode(part);
        if (decoded.length != requiredBytes) {
          return false;
        }
      } on FormatException {
        return false;
      }
    }
    return true;
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
