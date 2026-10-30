// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_engine_android/vpn_engine_android.dart';

class FakeVpnEngineHostApi implements VpnEngineHostApi {
  VpnConsentStatus? prepareResult;
  Object? prepareError;

  VpnCommandOutcome? startResult;
  Object? startError;
  Map<String, Object?>? lastStartPayload;

  VpnCommandOutcome? stopResult;
  Object? stopError;

  VpnStateEvent? getStatusResult;
  Object? getStatusError;

  @override
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  String get pigeonVar_messageChannelSuffix => '';

  @override
  Future<VpnConsentStatus> prepare() async {
    if (prepareError != null) throw prepareError!;
    return prepareResult ?? VpnConsentStatus.granted;
  }

  @override
  Future<VpnCommandOutcome> start(Map<String, Object?> profileJson) async {
    lastStartPayload = profileJson;
    if (startError != null) throw startError!;
    return startResult ?? VpnCommandOutcome.accepted;
  }

  @override
  Future<VpnCommandOutcome> stop() async {
    if (stopError != null) throw stopError!;
    return stopResult ?? VpnCommandOutcome.accepted;
  }

  @override
  Future<VpnStateEvent> getStatus() async {
    if (getStatusError != null) throw getStatusError!;
    return getStatusResult ?? VpnStateEvent(state: VpnNativeState.idle);
  }
}

void main() {
  late FakeVpnEngineHostApi fakeHostApi;
  late StreamController<VpnStateEvent> stateController;
  late StreamController<TrafficStatsEvent> statsController;
  late AndroidVpnEngine engine;

  final testProfile = ServerProfile(
    id: 'test-profile-uuid',
    name: 'Test Server',
    addedAt: DateTime.utc(2026, 1, 1),
    config: const VlessOutbound(
      server: 'vpn.example.com',
      serverPort: 443,
      uuid: 'a6f9c46d-318a-40a2-9bc8-592fdb28882a',
    ),
  );

  setUp(() {
    fakeHostApi = FakeVpnEngineHostApi();
    stateController = StreamController<VpnStateEvent>.broadcast();
    statsController = StreamController<TrafficStatsEvent>.broadcast();
    engine = AndroidVpnEngine(
      hostApi: fakeHostApi,
      stateEventsStream: stateController.stream,
      trafficStatsEventsStream: statsController.stream,
    );
  });

  tearDown(() async {
    await stateController.close();
    await statsController.close();
  });

  group('prepare()', () {
    test('alreadyGranted maps to VpnCommandAccepted', () async {
      fakeHostApi.prepareResult = VpnConsentStatus.alreadyGranted;
      final result = await engine.prepare();
      expect(result, const VpnCommandAccepted());
    });

    test('granted maps to VpnCommandAccepted', () async {
      fakeHostApi.prepareResult = VpnConsentStatus.granted;
      final result = await engine.prepare();
      expect(result, const VpnCommandAccepted());
    });

    test('denied maps to VpnCommandRejectedPermissionDenied', () async {
      fakeHostApi.prepareResult = VpnConsentStatus.denied;
      final result = await engine.prepare();
      expect(result, const VpnCommandRejectedPermissionDenied());
    });

    test('noActivity maps to VpnCommandFailed', () async {
      fakeHostApi.prepareResult = VpnConsentStatus.noActivity;
      final result = await engine.prepare();
      expect(result, const VpnCommandFailed());
    });

    test('recovers from PlatformException without throwing', () async {
      fakeHostApi.prepareError = PlatformException(
        code: 'FAILED',
        message: 'Platform failure',
      );
      final result = await engine.prepare();
      expect(result, const VpnCommandFailed());
    });
  });

  group('start(ServerProfile)', () {
    test('serializes ServerProfile and passes payload to hostApi', () async {
      fakeHostApi.startResult = VpnCommandOutcome.accepted;
      final result = await engine.start(testProfile);
      expect(result, const VpnCommandAccepted());
      expect(fakeHostApi.lastStartPayload, isNotNull);
      final payload = fakeHostApi.lastStartPayload!;
      expect(payload['id'], 'test-profile-uuid');
      expect(payload['name'], 'Test Server');
      final outbound = payload['outbound'] as Map<String, dynamic>?;
      expect(outbound, isNotNull);
      expect(outbound!['type'], 'vless');
      expect(outbound['server'], 'vpn.example.com');
      expect(outbound['server_port'], 443);
      expect(outbound['uuid'], 'a6f9c46d-318a-40a2-9bc8-592fdb28882a');
    });

    test('maps all 5 VpnCommandOutcome values 1:1', () async {
      final expectations = <VpnCommandOutcome, VpnCommandResult>{
        VpnCommandOutcome.accepted: const VpnCommandAccepted(),
        VpnCommandOutcome.rejectedBusy: const VpnCommandRejectedBusy(),
        VpnCommandOutcome.rejectedInvalidConfig:
            const VpnCommandRejectedInvalidConfig(),
        VpnCommandOutcome.rejectedPermissionDenied:
            const VpnCommandRejectedPermissionDenied(),
        VpnCommandOutcome.failed: const VpnCommandFailed(),
      };

      for (final entry in expectations.entries) {
        fakeHostApi.startResult = entry.key;
        final result = await engine.start(testProfile);
        expect(result, entry.value);
      }
    });

    test('returns VpnCommandRejectedInvalidConfig on serializer error',
        () async {
      final failingEngine = AndroidVpnEngine(
        hostApi: fakeHostApi,
        stateEventsStream: stateController.stream,
        trafficStatsEventsStream: statsController.stream,
        outboundSerializer: (config) =>
            throw UnsupportedError('Unsupported outbound protocol'),
      );

      final result = await failingEngine.start(testProfile);
      expect(result, const VpnCommandRejectedInvalidConfig());
      expect(fakeHostApi.lastStartPayload, isNull);
    });

    test('returns VpnCommandFailed when hostApi throws', () async {
      fakeHostApi.startError = PlatformException(
        code: 'CHANNEL_ERR',
        message: 'Host crashed',
      );
      final result = await engine.start(testProfile);
      expect(result, const VpnCommandFailed());
    });

    test('rejects runtime-unsupported AmneziaWgOutbound using real serializer',
        () async {
      final awgProfile = ServerProfile(
        id: 'awg-profile-uuid',
        name: 'AWG Server',
        addedAt: DateTime.utc(2026, 1, 1),
        config: AmneziaWgOutbound(
          server: 'vpn.example.com',
          serverPort: 51820,
          privateKey: 'PLACEHOLDER-PRIVATE-KEY',
          peerPublicKey: 'PLACEHOLDER-PUBLIC-KEY',
          localAddresses: const ['10.0.0.2/32'],
          jc: 4,
          h1: 100,
        ),
      );

      final result = await engine.start(awgProfile);
      expect(result, const VpnCommandRejectedInvalidConfig());
      expect(fakeHostApi.lastStartPayload, isNull);
    });
  });

  group('stop()', () {
    test('maps all 5 VpnCommandOutcome values 1:1', () async {
      final expectations = <VpnCommandOutcome, VpnCommandResult>{
        VpnCommandOutcome.accepted: const VpnCommandAccepted(),
        VpnCommandOutcome.rejectedBusy: const VpnCommandRejectedBusy(),
        VpnCommandOutcome.rejectedInvalidConfig:
            const VpnCommandRejectedInvalidConfig(),
        VpnCommandOutcome.rejectedPermissionDenied:
            const VpnCommandRejectedPermissionDenied(),
        VpnCommandOutcome.failed: const VpnCommandFailed(),
      };

      for (final entry in expectations.entries) {
        fakeHostApi.stopResult = entry.key;
        final result = await engine.stop();
        expect(result, entry.value);
      }
    });

    test('returns VpnCommandFailed when hostApi throws', () async {
      fakeHostApi.stopError = PlatformException(
        code: 'STOP_ERR',
        message: 'Stop failed',
      );
      final result = await engine.stop();
      expect(result, const VpnCommandFailed());
    });
  });

  group('getStatus()', () {
    test('maps all 8 VpnNativeState values to ConnectionState', () async {
      final expectations = <VpnNativeState, ConnectionState>{
        VpnNativeState.idle: const Disconnected(),
        VpnNativeState.preparing: const Connecting(),
        VpnNativeState.starting: const Connecting(),
        VpnNativeState.running: const Connected(),
        VpnNativeState.stopping: const Disconnecting(),
        VpnNativeState.stopped: const Disconnected(),
        VpnNativeState.error: const Error(PlatformError('Native crash')),
        VpnNativeState.revoked: const Error(PermissionDenied()),
      };

      for (final entry in expectations.entries) {
        fakeHostApi.getStatusResult = VpnStateEvent(
          state: entry.key,
          errorReason:
              entry.key == VpnNativeState.error ? 'Native crash' : null,
        );
        final state = await engine.getStatus();
        expect(state, entry.value);
      }
    });

    test('null or empty errorReason produces non-null fallback detail',
        () async {
      fakeHostApi.getStatusResult = VpnStateEvent(
        state: VpnNativeState.error,
        errorReason: null,
      );
      final nullReasonState = await engine.getStatus();
      expect(
        nullReasonState,
        const Error(PlatformError('Unknown native error')),
      );

      fakeHostApi.getStatusResult = VpnStateEvent(
        state: VpnNativeState.error,
        errorReason: '',
      );
      final emptyReasonState = await engine.getStatus();
      expect(
        emptyReasonState,
        const Error(PlatformError('Unknown native error')),
      );
    });

    test('returns Error(PlatformError) when hostApi throws', () async {
      fakeHostApi.getStatusError = PlatformException(
        code: 'STATUS_ERR',
        message: 'IPC dead',
      );
      final state = await engine.getStatus();
      expect(
        state,
        isA<Error>().having(
          (e) => (e.reason as PlatformError).detail,
          'detail',
          contains('STATUS_ERR'),
        ),
      );
    });
  });

  group('connectionState stream', () {
    test('forwards transitions and deduplicates consecutive duplicate states',
        () async {
      final emitted = <ConnectionState>[];
      final sub = engine.connectionState.listen(emitted.add);

      stateController
        ..add(VpnStateEvent(state: VpnNativeState.idle))
        ..add(VpnStateEvent(state: VpnNativeState.preparing))
        ..add(VpnStateEvent(state: VpnNativeState.starting))
        ..add(VpnStateEvent(state: VpnNativeState.running))
        ..add(VpnStateEvent(state: VpnNativeState.stopping))
        ..add(VpnStateEvent(state: VpnNativeState.stopped))
        ..add(VpnStateEvent(state: VpnNativeState.idle))
        ..add(
          VpnStateEvent(
            state: VpnNativeState.error,
            errorReason: 'Handshake timeout',
          ),
        )
        ..add(VpnStateEvent(state: VpnNativeState.revoked));

      await pumpEventQueue();

      expect(emitted, const <ConnectionState>[
        Disconnected(),
        Connecting(),
        Connected(),
        Disconnecting(),
        Disconnected(),
        Error(PlatformError('Handshake timeout')),
        Error(PermissionDenied()),
      ]);

      await sub.cancel();
    });

    test('converts stream error to Error(PlatformError) without uncaught error',
        () async {
      final emitted = <ConnectionState>[];
      final sub = engine.connectionState.listen(emitted.add);

      stateController.addError(
        PlatformException(code: 'STREAM_ERR', message: 'Channel terminated'),
      );

      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(
        emitted.first,
        isA<Error>().having(
          (e) => (e.reason as PlatformError).detail,
          'detail',
          contains('STREAM_ERR'),
        ),
      );

      await sub.cancel();
    });
  });

  group('trafficStats stream & Invariant 2', () {
    test('maps valid TrafficStatsEvent to TrafficStats', () async {
      final emitted = <TrafficStats>[];
      final sub = engine.trafficStats.listen(emitted.add);

      statsController.add(
        TrafficStatsEvent(
          txBytes: 1024,
          rxBytes: 2048,
          epochMillis: 1700000000000,
        ),
      );

      await pumpEventQueue();

      expect(emitted, <TrafficStats>[
        TrafficStats(
          txBytes: 1024,
          rxBytes: 2048,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
      ]);

      await sub.cancel();
    });

    test('filters out negative values and absorbs stream errors cleanly',
        () async {
      final emittedStats = <TrafficStats>[];
      final emittedState = <ConnectionState>[];

      final subStats = engine.trafficStats.listen(emittedStats.add);
      final subState = engine.connectionState.listen(emittedState.add);

      statsController.add(
        TrafficStatsEvent(
          txBytes: -1,
          rxBytes: 100,
          epochMillis: 1700000000000,
        ),
      );
      statsController.addError(Exception('Corrupt stats stream'));
      statsController.add(
        TrafficStatsEvent(
          txBytes: 500,
          rxBytes: 1000,
          epochMillis: 1700000001000,
        ),
      );

      stateController.add(VpnStateEvent(state: VpnNativeState.running));

      await pumpEventQueue();

      expect(emittedStats, <TrafficStats>[
        TrafficStats(
          txBytes: 500,
          rxBytes: 1000,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        ),
      ]);

      expect(emittedState, const <ConnectionState>[Connected()]);

      await subStats.cancel();
      await subState.cancel();
    });
  });

  group('logEvents', () {
    test('emits engine log events from injected stream', () async {
      final logController = StreamController<String>.broadcast();
      final localEngine = AndroidVpnEngine(
        hostApi: fakeHostApi,
        stateEventsStream: stateController.stream,
        trafficStatsEventsStream: statsController.stream,
        logEventsStream: logController.stream,
      );

      final received = <String>[];
      final sub = localEngine.logEvents.listen(received.add);

      logController.add('libbox: starting inbound');
      logController.add('libbox: tun opened');
      await pumpEventQueue();

      expect(received, [
        'libbox: starting inbound',
        'libbox: tun opened',
      ]);

      await sub.cancel();
      await logController.close();
    });
  });
}
