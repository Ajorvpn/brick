// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/data/repositories/app_preferences_repository.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/telemetry/server_probe_report.dart';
import 'package:mobile/core/telemetry/server_probe_reporter.dart';
import 'package:mobile/core/telemetry/server_probe_telemetry_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A safe, resolvable-looking collector used in tests. Never contacted: every
/// test injects a transport closure.
const String _collectorUrl = 'https://probe.brickvpn.example/v1/reports';

/// SHA-256('vless|example.com|443') starts with `00bf7b78cd7fbaf0`, computed
/// independently with `sha256sum`. Hardcoding it proves the local FIPS 180-4
/// implementation agrees with a reference tool rather than with itself.
const String _expectedNodeHash = '00bf7b78cd7fbaf0';

ServerProbeReport _report({bool ok = true, int? latencyMs = 120}) {
  return ServerProbeReport.create(
    nodeHash: ServerProbeReport.computeNodeHash(
      protocol: 'vless',
      host: 'example.com',
      port: 443,
    ),
    ok: ok,
    latencyMs: latencyMs,
    networkType: ProbeNetworkType.wifi,
    observedAt: DateTime.utc(2026, 11, 23, 8, 41, 29),
  );
}

void main() {
  group('Anonymous probe opt-in preference (strict, default OFF)', () {
    test('defaults to false in both fake and persisted repositories', () async {
      expect(
        FakeAppPreferencesRepository().isAnonymousProbeReportingEnabled(),
        isFalse,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo = SharedPreferencesAppPreferencesRepository(prefs);
      expect(repo.isAnonymousProbeReportingEnabled(), isFalse);
    });

    test('round-trips through SharedPreferences across a restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final repo1 = SharedPreferencesAppPreferencesRepository(prefs);

      await repo1.setAnonymousProbeReportingEnabled(enabled: true);
      expect(repo1.isAnonymousProbeReportingEnabled(), isTrue);
      expect(
        prefs.getBool(
          SharedPreferencesAppPreferencesRepository
              .keyAnonymousProbeReportingEnabled,
        ),
        isTrue,
      );

      final repo2 = SharedPreferencesAppPreferencesRepository(prefs);
      expect(repo2.isAnonymousProbeReportingEnabled(), isTrue);

      await repo2.setAnonymousProbeReportingEnabled(enabled: false);
      expect(repo2.isAnonymousProbeReportingEnabled(), isFalse);
    });

    test(
      'provider starts disabled and persists toggles through the notifier',
      () async {
        final fakeRepo = FakeAppPreferencesRepository();
        final container = ProviderContainer(
          overrides: [
            appPreferencesRepositoryProvider.overrideWithValue(fakeRepo),
          ],
        );
        addTearDown(container.dispose);

        expect(container.read(anonymousProbeReportingEnabledProvider), isFalse);

        await container
            .read(anonymousProbeReportingEnabledProvider.notifier)
            .setEnabled(enabled: true);
        expect(container.read(anonymousProbeReportingEnabledProvider), isTrue);
        expect(fakeRepo.isAnonymousProbeReportingEnabled(), isTrue);

        // The reporter reads the same preference through its provider.
        expect(container.read(serverProbeReporterProvider).endpoint, isNull);
      },
    );
  });

  group('ServerProbeReport privacy allowlist', () {
    test('node_hash is a 16-char SHA-256 prefix that never contains the host, '
        'IP, password, or server name', () {
      final hash = ServerProbeReport.computeNodeHash(
        protocol: 'vless',
        host: '  ExAmPlE.CoM  ',
        port: 443,
      );

      expect(hash, equals(_expectedNodeHash));
      expect(hash, hasLength(16));
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(hash), isTrue);

      // Irreversible: no fragment of the connection secret survives.
      for (final secret in <String>[
        'example',
        'ExAmPlE',
        'com',
        '443',
        'vless',
        'password',
        'Tokyo Node',
      ]) {
        expect(hash.contains(secret.toLowerCase()), isFalse);
      }

      // Host casing/whitespace cannot change the identity, but the port can.
      expect(
        ServerProbeReport.computeNodeHash(
          protocol: 'vless',
          host: 'example.com',
          port: 8443,
        ),
        isNot(equals(hash)),
      );
    });

    test('toJson emits exactly the five allowlisted keys', () {
      final json = _report().toJson();

      expect(
        json.keys.toSet(),
        equals(<String>{
          'node_hash',
          'ok',
          'latency_ms',
          'network_type',
          'hour_utc',
        }),
      );
      expect(json, hasLength(5));
      expect(json['node_hash'], equals(_expectedNodeHash));
      expect(json['ok'], isTrue);
      expect(json['latency_ms'], equals(120));
      expect(json['network_type'], equals('wifi'));
      expect(json['hour_utc'], equals('2026-11-23T08:00:00Z'));

      // No key can carry an identifier or raw connection detail.
      for (final forbidden in <String>[
        'host',
        'port',
        'ip',
        'uuid',
        'password',
        'private',
        'name',
        'device',
        'user',
        'ssid',
        'user_agent',
      ]) {
        expect(
          json.keys.where((key) => key.contains(forbidden)),
          isEmpty,
          reason: 'Forbidden field fragment "$forbidden" in payload',
        );
      }
    });

    test('latency_ms is clamped to 0..30000 and null on failure', () {
      final tooSlow = _report(latencyMs: 999999).toJson();
      expect(tooSlow['latency_ms'], equals(30000));

      final negative = _report(latencyMs: -42).toJson();
      expect(negative['latency_ms'], equals(0));

      final failed = _report(ok: false, latencyMs: 87).toJson();
      expect(failed['ok'], isFalse);
      expect(failed['latency_ms'], isNull);

      final unknown = _report(latencyMs: null).toJson();
      expect(unknown['latency_ms'], isNull);
    });

    test('hour_utc is truncated to the UTC hour and never carries minutes', () {
      final truncated = ServerProbeReport.formatHourUtc(
        DateTime.utc(2026, 1, 5, 23, 59, 59, 999),
      );
      expect(truncated, equals('2026-01-05T23:00:00Z'));
      expect(truncated.contains(':59'), isFalse);

      // A local-time input is normalized to UTC before truncation.
      final local = DateTime(2026, 6, 1, 14, 30).toUtc();
      expect(
        ServerProbeReport.formatHourUtc(DateTime(2026, 6, 1, 14, 30)),
        equals(ServerProbeReport.formatHourUtc(local)),
      );
    });

    test('network_type carries only the three coarse wire values', () {
      expect(
        ProbeNetworkType.values.map((type) => type.wireValue).toList(),
        equals(<String>['wifi', 'cellular', 'other']),
      );
      expect(ProbeNetworkType.cellular.wireValue, equals('cellular'));
      expect(ProbeNetworkType.other.wireValue, equals('other'));
    });
  });

  group('ServerProbeReporter safety gates', () {
    test('sends nothing when the user has not opted in', () async {
      final calls = <String>[];
      final reporter = ServerProbeReporter(
        isEnabled: () => false,
        endpoint: Uri.parse(_collectorUrl),
        transport: (endpoint, body) async => calls.add(body),
      );

      expect(await reporter.submit(_report()), equals(0));
      expect(calls, isEmpty);
      // Not opted in means not even buffered.
      expect(reporter.pendingCount, equals(0));
    });

    test('sends nothing when no collector endpoint is configured', () async {
      final calls = <String>[];
      final reporter = ServerProbeReporter(
        isEnabled: () => true,
        transport: (endpoint, body) async => calls.add(body),
      );

      // `BRICK_PROBE_ENDPOINT` is never defined in the test build.
      expect(reporter.endpoint, isNull);
      expect(await reporter.submit(_report()), equals(0));
      expect(calls, isEmpty);
      expect(reporter.pendingCount, equals(0));
    });

    test('rejects cleartext, userinfo, loopback, private and link-local '
        'endpoints', () {
      const rejected = <String>[
        'http://probe.brickvpn.example/v1',
        'https://127.0.0.1/v1',
        'https://10.1.2.3/v1',
        'https://172.16.0.9/v1',
        'https://172.31.255.1/v1',
        'https://192.168.0.5/v1',
        'https://169.254.10.10/v1',
        'https://[::1]/v1',
        'https://[fc00::1]/v1',
        'https://[fe80::1]/v1',
        'https://localhost/v1',
        'https://evil.local/v1',
        'https://user:secret@probe.brickvpn.example/v1',
        'https:///no-host',
      ];

      for (final raw in rejected) {
        final uri = Uri.parse(raw);
        expect(
          ServerProbeReporter.isSecureEndpoint(uri),
          isFalse,
          reason: 'Endpoint $raw must be rejected',
        );
      }

      expect(
        ServerProbeReporter.isSecureEndpoint(Uri.parse(_collectorUrl)),
        isTrue,
      );
      expect(
        ServerProbeReporter.isSecureEndpoint(
          Uri.parse('https://[2001:4860:4860::8888]/v1'),
        ),
        isTrue,
      );
    });

    test(
      'an invalid endpoint produces zero requests and no buffered data',
      () async {
        for (final endpoint in <Uri>[
          Uri.parse('http://probe.brickvpn.example/v1'),
          Uri.parse('https://192.168.1.10/v1'),
        ]) {
          final calls = <String>[];
          final reporter = ServerProbeReporter(
            isEnabled: () => true,
            endpoint: endpoint,
            transport: (uri, body) async => calls.add(body),
          );

          expect(await reporter.submit(_report()), equals(0));
          expect(calls, isEmpty);
          expect(reporter.pendingCount, equals(0));
        }
      },
    );

    test('delivers an allowlisted body with minimal content', () async {
      final bodies = <String>[];
      final endpoints = <Uri>[];
      final reporter = ServerProbeReporter(
        isEnabled: () => true,
        endpoint: Uri.parse(_collectorUrl),
        transport: (endpoint, body) async {
          endpoints.add(endpoint);
          bodies.add(body);
        },
      );

      expect(await reporter.submit(_report()), equals(1));
      expect(bodies, hasLength(1));
      expect(endpoints.single.toString(), equals(_collectorUrl));

      final decoded = jsonDecode(bodies.single) as Map<String, dynamic>;
      final reports = decoded['reports'] as List<dynamic>;
      expect(reports, hasLength(1));

      final payload = reports.single as Map<String, dynamic>;
      expect(payload.keys.toSet(), equals(_report().toJson().keys.toSet()));
      expect(payload['node_hash'], equals(_expectedNodeHash));

      // The wire body never carries the raw server identity.
      expect(bodies.single.contains('example.com'), isFalse);
      expect(bodies.single.contains('vless|'), isFalse);
      // ...nor device or app fingerprints.
      for (final forbidden in <String>[
        'device',
        'user_agent',
        'imei',
        'android_id',
        'app_version',
      ]) {
        expect(
          bodies.single.toLowerCase().contains(forbidden),
          isFalse,
          reason: 'Payload must not carry "$forbidden"',
        );
      }
    });

    test('enforces the 60 s rate limit and the 20-item batch cap', () async {
      var now = DateTime.utc(2026, 11, 23, 12);
      final bodies = <String>[];
      final reporter = ServerProbeReporter(
        isEnabled: () => true,
        endpoint: Uri.parse(_collectorUrl),
        transport: (endpoint, body) async => bodies.add(body),
        clock: () => now,
      );

      expect(reporter.minFlushInterval, equals(const Duration(seconds: 60)));
      expect(reporter.maxBatchSize, equals(20));

      // First submission flushes immediately.
      expect(await reporter.submit(_report()), equals(1));
      expect(bodies, hasLength(1));

      // Any immediate retry is rate-limited, even though reports are queued.
      expect(await reporter.submit(_report()), equals(0));
      expect(bodies, hasLength(1));

      // The ring buffer keeps at most `maxBatchSize` reports.
      for (var i = 0; i < 25; i++) {
        await reporter.submit(_report());
      }
      expect(reporter.pendingCount, equals(20));

      // Once the interval elapses, exactly one capped batch is delivered.
      now = now.add(const Duration(seconds: 61));
      expect(await reporter.flush(), equals(20));
      expect(bodies, hasLength(2));

      final decoded = jsonDecode(bodies.last) as Map<String, dynamic>;
      expect(decoded['reports'] as List<dynamic>, hasLength(20));
      expect(reporter.pendingCount, equals(0));
    });

    test(
      'a throwing transport never throws and keeps the report queued',
      () async {
        final reporter = ServerProbeReporter(
          isEnabled: () => true,
          endpoint: Uri.parse(_collectorUrl),
          transport: (endpoint, body) async =>
              throw StateError('collector blocked or censored'),
        );

        expect(await reporter.submit(_report()), equals(0));
        expect(reporter.pendingCount, equals(1));
      },
    );

    test(
      'a hanging collector is cut off by the 3 s timeout without throwing',
      () async {
        final reporter = ServerProbeReporter(
          isEnabled: () => true,
          endpoint: Uri.parse(_collectorUrl),
          // Never completes: models a censored or black-holed collector.
          transport: (endpoint, body) => Completer<void>().future,
        );

        expect(
          ServerProbeReporter.requestTimeout,
          equals(const Duration(seconds: 3)),
        );

        final stopwatch = Stopwatch()..start();
        expect(await reporter.submit(_report()), equals(0));
        stopwatch.stop();

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 6)));
      },
    );
  });

  group('ServerProbeReport node_hash hardening', () {
    test('computeNodeHash normalizes protocol casing and whitespace', () {
      expect(
        ServerProbeReport.computeNodeHash(
          protocol: ' VLESS ',
          host: 'example.com',
          port: 443,
        ),
        equals(_expectedNodeHash),
      );
      expect(
        ServerProbeReport.computeNodeHash(
          protocol: 'vless',
          host: '  ExAmPlE.CoM  ',
          port: 443,
        ),
        equals(_expectedNodeHash),
      );
    });

    test('create rejects anything that is not 16 lowercase hex chars', () {
      for (final invalid in <String>[
        '127.0.0.1',
        'example.com',
        'vless|example.com|443',
        'b2f5b2f5-0000-4000-8000-000000000000',
        '00BF7B78CD7FBAF0',
        '00bf7b78cd7fbaf',
        '00bf7b78cd7fbaf01',
        '',
      ]) {
        expect(
          () => ServerProbeReport.create(
            nodeHash: invalid,
            ok: true,
            networkType: ProbeNetworkType.wifi,
            observedAt: DateTime.utc(2026, 11, 23),
          ),
          throwsArgumentError,
          reason: 'nodeHash "$invalid" must be rejected',
        );
      }

      // The legitimate digest still builds at full latency.
      expect(_report().nodeHash, equals(_expectedNodeHash));
    });
  });

  group('ServerProbeReporter SSRF coverage', () {
    test(
      'rejects IPv4-mapped IPv6, CGNAT, multicast and reserved literals',
      () {
        const rejected = <String>[
          'https://[::ffff:127.0.0.1]/probe',
          'https://[::ffff:192.168.1.1]/probe',
          'https://[::ffff:7f00:1]/probe',
          'https://[::ffff:169.254.1.1]/probe',
          'https://100.64.0.1/probe',
          'https://100.127.255.254/probe',
          'https://224.0.0.1/probe',
          'https://239.255.255.250/probe',
          'https://255.255.255.255/probe',
          'https://[ff02::1]/probe',
        ];

        for (final raw in rejected) {
          expect(
            ServerProbeReporter.isSecureEndpoint(Uri.parse(raw)),
            isFalse,
            reason: 'Endpoint $raw must be rejected',
          );
        }

        // Public space on both families is still accepted.
        expect(
          ServerProbeReporter.isSecureEndpoint(
            Uri.parse('https://100.63.255.255/probe'),
          ),
          isTrue,
        );
        expect(
          ServerProbeReporter.isSecureEndpoint(
            Uri.parse('https://[::ffff:8.8.8.8]/probe'),
          ),
          isTrue,
        );
      },
    );

    test('the real transport never follows a redirect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${server.port}/captured',
          );
        await request.response.close();
      });

      final local = Uri.parse('http://127.0.0.1:${server.port}/v1/reports');

      // The 302 itself is surfaced as a non-2xx failure, and the target of the
      // redirect is never requested.
      await expectLater(
        ServerProbeReporter.httpTransport(local, '{"reports":[]}'),
        throwsA(isA<HttpException>()),
      );
      expect(requests, equals(1));
    });
  });

  group('ServerProbeReporter lifecycle hardening', () {
    test(
      'turning the switch off wipes the buffered queue immediately',
      () async {
        var enabled = true;
        final now = DateTime.utc(2026, 11, 23, 12);
        final reporter = ServerProbeReporter(
          isEnabled: () => enabled,
          endpoint: Uri.parse(_collectorUrl),
          transport: (endpoint, body) async =>
              throw StateError('collector blocked or censored'),
          clock: () => now,
        );

        expect(await reporter.submit(_report()), equals(0));
        expect(reporter.pendingCount, equals(1));

        enabled = false;
        expect(await reporter.flush(), equals(0));
        expect(reporter.pendingCount, equals(0));

        // Still off: a later submit buffers nothing.
        expect(await reporter.submit(_report()), equals(0));
        expect(reporter.pendingCount, equals(0));
      },
    );

    test('flipping the switch off during an in-flight send wipes the queue '
        'immediately', () async {
      var enabled = true;
      final gate = Completer<void>();
      final reporter = ServerProbeReporter(
        isEnabled: () => enabled,
        endpoint: Uri.parse(_collectorUrl),
        transport: (endpoint, body) async {
          await gate.future;
        },
        clock: () => DateTime.utc(2026, 11, 23, 12),
      );

      final inFlight = reporter.submit(_report());
      await Future<void>.delayed(Duration.zero);
      expect(reporter.pendingCount, equals(1));

      // The opt-out is checked before the in-flight guard, so the wipe is
      // immediate rather than deferred until the open request settles.
      enabled = false;
      expect(await reporter.flush(), equals(0));
      expect(reporter.pendingCount, equals(0));

      // Completing the earlier send removes from an already-empty queue: a
      // safe no-op that cannot resurrect or double-drop reports.
      gate.complete();
      expect(await inFlight, equals(1));
      expect(reporter.pendingCount, equals(0));
    });

    test(
      'a report enqueued during an in-flight flush is never dropped',
      () async {
        final gate = Completer<void>();
        final sent = <String>[];
        final reporter = ServerProbeReporter(
          isEnabled: () => true,
          endpoint: Uri.parse(_collectorUrl),
          transport: (endpoint, body) async {
            sent.add(body);
            await gate.future;
          },
          clock: () => DateTime.utc(2026, 11, 23, 12),
          maxBatchSize: 2,
        );

        // The first flush is now suspended inside the transport with the
        // first report taken as its batch.
        final first = reporter.submit(_report());
        final second = reporter.submit(_report());
        final third = reporter.submit(_report());

        // Overlapping flushes are refused while one send is in flight.
        expect(await second, equals(0));
        expect(await third, equals(0));
        // The ring cap of 2 evicted the in-flight report from the queue, which
        // is exactly the case a positional `removeRange` gets wrong.
        expect(reporter.pendingCount, equals(2));

        gate.complete();
        expect(await first, equals(1));
        expect(sent, hasLength(1));

        // The two reports that were never transmitted are still queued.
        expect(reporter.pendingCount, equals(2));
      },
    );
  });

  group('ServerProbeReporter real socket transport', () {
    test(
      'a non-2xx block page is not a delivery and no User-Agent is sent',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final receivedHeaders = <HttpHeaders>[];
        final receivedBodies = <String>[];
        server.listen((request) async {
          receivedHeaders.add(request.headers);
          receivedBodies.add(await utf8.decoder.bind(request).join());
          request.response
            ..statusCode = HttpStatus.forbidden
            ..write('blocked by middlebox');
          await request.response.close();
        });

        final local = Uri.parse('http://127.0.0.1:${server.port}/v1/reports');

        // The transport itself must refuse the 403 rather than drain it.
        await expectLater(
          ServerProbeReporter.httpTransport(local, '{"reports":[]}'),
          throwsA(isA<HttpException>()),
        );
        expect(receivedBodies.single, equals('{"reports":[]}'));
        expect(
          receivedHeaders.single.value(HttpHeaders.userAgentHeader),
          isNull,
        );
        expect(
          receivedHeaders.single.value(HttpHeaders.contentTypeHeader),
          equals('application/json'),
        );

        // Through the reporter, that failure keeps the batch queued.
        final reporter = ServerProbeReporter(
          isEnabled: () => true,
          endpoint: Uri.parse(_collectorUrl),
          transport: (uri, body) =>
              ServerProbeReporter.httpTransport(local, body),
          clock: () => DateTime.utc(2026, 11, 23, 12),
        );
        expect(await reporter.submit(_report()), equals(0));
        expect(reporter.pendingCount, equals(1));
      },
    );
  });
}
