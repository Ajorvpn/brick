// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Connecting,
        Disconnected,
        Disconnecting,
        Error,
        PlatformError;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/domain/formatters/traffic_formatter.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/saved_servers_provider.dart';
import 'package:mobile/features/connection/presentation/widgets/session_info_panel.dart';

import 'localization_test_harness.dart';

void main() {
  setUpAll(initTestLocalization);

  group('TrafficFormatter.formatDuration', () {
    test('formats durations into HH:MM:SS', () {
      expect(TrafficFormatter.formatDuration(Duration.zero), '00:00:00');
      expect(
        TrafficFormatter.formatDuration(const Duration(seconds: -10)),
        '00:00:00',
      );
      expect(
        TrafficFormatter.formatDuration(const Duration(seconds: 45)),
        '00:00:45',
      );
      expect(
        TrafficFormatter.formatDuration(const Duration(minutes: 5, seconds: 3)),
        '00:05:03',
      );
      expect(
        TrafficFormatter.formatDuration(
          const Duration(hours: 1, minutes: 23, seconds: 45),
        ),
        '01:23:45',
      );
      expect(
        TrafficFormatter.formatDuration(const Duration(hours: 100)),
        '100:00:00',
      );
    });
  });

  group('SessionInfoPanel and sessionDurationProvider', () {
    late FakeVpnEngine fakeEngine;

    setUp(() {
      fakeEngine = FakeVpnEngine();
    });

    tearDown(() async {
      await fakeEngine.dispose();
    });

    testWidgets(
      'duration timer lifecycle: starts on Connected, survives idempotent '
      'Connected, resets on disconnect/reconnect',
      (tester) async {
        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: fakeEngine,
        );

        // Initially Disconnected: duration is 00:00:00
        expect(find.text('Duration: 00:00:00'), findsOneWidget);
        expect(find.text('Tunnel: Disconnected'), findsOneWidget);

        // Transition to Connected
        fakeEngine.emit(const Connected());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Tunnel: Connected'), findsOneWidget);
        expect(find.text('Duration: 00:00:00'), findsOneWidget);

        // Advance 3 seconds
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Duration: 00:00:01'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Duration: 00:00:03'), findsOneWidget);

        // Idempotent Connected emission (e.g. app lifecycle resume)
        fakeEngine.emit(const Connected());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Advance 2 more seconds: must NOT reset to zero
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Duration: 00:00:05'), findsOneWidget);

        // Transition to Disconnecting: timer cancels and resets
        fakeEngine.emit(const Disconnecting());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Disconnecting'), findsOneWidget);
        expect(find.text('Duration: 00:00:00'), findsOneWidget);

        // Transition to Disconnected: remains 00:00:00
        fakeEngine.emit(const Disconnected());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Disconnected'), findsOneWidget);
        expect(find.text('Duration: 00:00:00'), findsOneWidget);

        // Reconnect: starts fresh from 00:00:00
        fakeEngine.emit(const Connected());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(seconds: 4));
        expect(find.text('Duration: 00:00:04'), findsOneWidget);

        // Clean teardown while timer is ticking
        fakeEngine.emit(const Disconnected());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('starts duration timer when connectionStateProvider is already '
        'Connected on initial build', (tester) async {
      fakeEngine.emit(const Connected());

      await pumpConnectionMaterialApp(
        tester,
        const Scaffold(body: SessionInfoPanel()),
        engine: fakeEngine,
      );

      expect(find.text('Tunnel: Connected'), findsOneWidget);
      expect(find.text('Duration: 00:00:00'), findsOneWidget);

      // Advance 3 seconds
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Duration: 00:00:01'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Duration: 00:00:03'), findsOneWidget);

      // Clean teardown
      fakeEngine.emit(const Disconnected());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'active server display: shows None selected when empty, updates when '
      'server is added or selected',
      (tester) async {
        final dataSource = FakeServerProfileDataSource();

        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: fakeEngine,
          dataSource: dataSource,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SessionInfoPanel)),
        );

        // When no servers exist
        expect(find.text('Server: None selected'), findsOneWidget);

        // Add a server
        final repo = buildRepository(dataSource);
        await repo.addServer(validVlessUri);
        container.invalidate(savedServersProvider);
        await tester.pumpAndSettle();

        expect(find.text('Server: My Server (vless)'), findsOneWidget);

        // Add a second server and explicitly select it
        await repo.addServer(validTrojanUri);
        final secondId = dataSource.records.last.id;
        container.invalidate(savedServersProvider);
        await tester.pumpAndSettle();

        // Switch active server via activeServerIdProvider
        await container
            .read(activeServerIdProvider.notifier)
            .selectServer(secondId);
        await tester.pumpAndSettle();

        expect(find.text('Server: Trojan Node (trojan)'), findsOneWidget);
      },
    );

    testWidgets(
      'engine state display: maps every connection state to localized text',
      (tester) async {
        await pumpConnectionMaterialApp(
          tester,
          const Scaffold(body: SessionInfoPanel()),
          engine: fakeEngine,
        );

        expect(find.text('Tunnel: Disconnected'), findsOneWidget);

        fakeEngine.emit(const Connecting());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Connecting'), findsOneWidget);

        fakeEngine.emit(const Connected());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Tunnel: Connected'), findsOneWidget);

        fakeEngine.emit(const Disconnecting());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Disconnecting'), findsOneWidget);

        fakeEngine.emit(const Error(PlatformError('Platform unreachable')));
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Connection error'), findsOneWidget);

        fakeEngine.emit(const Disconnected());
        await tester.pumpAndSettle();
        expect(find.text('Tunnel: Disconnected'), findsOneWidget);
      },
    );

    testWidgets('rebuild isolation: duration ticks rebuild only '
        '_SessionDurationText leaf', (tester) async {
      var panelRebuilds = 0;

      await pumpConnectionMaterialApp(
        tester,
        Scaffold(
          body: Column(
            children: [
              Builder(
                builder: (context) {
                  panelRebuilds++;
                  return const SessionInfoPanel();
                },
              ),
            ],
          ),
        ),
        engine: fakeEngine,
      );

      fakeEngine.emit(const Connected());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Duration: 00:00:00'), findsOneWidget);
      final initialPanelRebuilds = panelRebuilds;

      // Advance timer 3 ticks
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Duration: 00:00:03'), findsOneWidget);
      // Outer panel Builder was NOT rebuilt during duration timer ticks!
      expect(panelRebuilds, equals(initialPanelRebuilds));

      fakeEngine.emit(const Disconnected());
      await tester.pumpAndSettle();
    });
  });
}
