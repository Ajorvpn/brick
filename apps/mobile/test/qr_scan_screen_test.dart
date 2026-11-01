// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/connection/presentation/screens/add_server_screen.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';
import 'package:mobile/features/connection/presentation/screens/qr_scan_screen.dart';
import 'package:mobile/main.dart';

import 'localization_test_harness.dart';

/// Mutable camera permission service double for deterministic testing.
class MutableCameraPermissionService implements CameraPermissionService {
  MutableCameraPermissionService({
    this.initialStatus = CameraPermissionStatus.granted,
    this.requestStatuses = const <CameraPermissionStatus>[],
  });

  CameraPermissionStatus initialStatus;
  final List<CameraPermissionStatus> requestStatuses;
  int checkStatusCalls = 0;
  int requestPermissionCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<CameraPermissionStatus> checkStatus() async {
    checkStatusCalls++;
    return initialStatus;
  }

  @override
  Future<CameraPermissionStatus> requestPermission() async {
    final index = requestPermissionCalls;
    requestPermissionCalls++;
    if (index < requestStatuses.length) {
      initialStatus = requestStatuses[index];
    }
    return initialStatus;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}

void main() {
  setUpAll(initTestLocalization);

  group('QrScanScreen — P5-T3 QR Code Scan & Camera Permission Flow', () {
    testWidgets(
      'valid VLESS QR scan saves to repository and pops back to HomeScreen',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        Widget mockScanner(
          BuildContext context,
          Future<void> Function(String rawValue) onDetect,
        ) {
          return ElevatedButton(
            key: const ValueKey<String>('mock_scan_button'),
            onPressed: () => onDetect(validVlessUri),
            child: const Text('Simulate Scan'),
          );
        }

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          scannerBuilder: mockScanner,
        );

        expect(dataSource.records, isEmpty);

        // Navigate from HomeScreen to AddServerScreen
        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        // Tap "Scan QR Code" button to open QrScanScreen
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(QrScanScreen), findsOneWidget);

        // Trigger simulated QR code scan
        await tester.tap(
          find.byKey(const ValueKey<String>('mock_scan_button')),
        );
        await tester.pumpAndSettle();

        // Verified: direct persistence without preview, popped back to
        // HomeScreen.
        expect(dataSource.records, hasLength(1));
        expect(dataSource.records.single.sourceUri, equals(validVlessUri));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byType(AddServerScreen), findsNothing);
        expect(find.byType(QrScanScreen), findsNothing);
      },
    );

    testWidgets(
      'valid Trojan QR scan saves to repository and pops back to HomeScreen',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        Widget mockScanner(
          BuildContext context,
          Future<void> Function(String rawValue) onDetect,
        ) {
          return ElevatedButton(
            key: const ValueKey<String>('mock_scan_button'),
            onPressed: () => onDetect(validTrojanUri),
            child: const Text('Simulate Scan'),
          );
        }

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          scannerBuilder: mockScanner,
        );

        expect(dataSource.records, isEmpty);

        // Navigate from HomeScreen to AddServerScreen
        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();
        expect(find.byType(AddServerScreen), findsOneWidget);

        // Tap "Scan QR Code" button
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(QrScanScreen), findsOneWidget);

        // Trigger scan
        await tester.tap(
          find.byKey(const ValueKey<String>('mock_scan_button')),
        );
        await tester.pumpAndSettle();

        // Verified: second protocol persisted, popped back to HomeScreen
        expect(dataSource.records, hasLength(1));
        expect(dataSource.records.single.sourceUri, equals(validTrojanUri));
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'single-scan lock prevents duplicate submissions from rapid frames',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        late Future<void> Function(String rawValue) scanCallback;

        Widget mockScanner(
          BuildContext context,
          Future<void> Function(String rawValue) onDetect,
        ) {
          scanCallback = onDetect;
          return const SizedBox();
        }

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          scannerBuilder: mockScanner,
        );

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
        );
        await tester.pumpAndSettle();

        // Fire 5 rapid detection events concurrently in the exact same turn
        await Future.wait([
          scanCallback(validVlessUri),
          scanCallback(validVlessUri),
          scanCallback(validVlessUri),
          scanCallback(validVlessUri),
          scanCallback(validVlessUri),
        ]);
        await tester.pumpAndSettle();

        // Verified: single-scan lock prevented duplicates; saved exactly once
        expect(dataSource.records, hasLength(1));
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets(
      'invalid QR code shows SnackBar, stays on screen, and unlocks for retry',
      (tester) async {
        final engine = FakeVpnEngine();
        final dataSource = FakeServerProfileDataSource();
        addTearDown(engine.dispose);

        late Future<void> Function(String rawValue) scanCallback;

        Widget mockScanner(
          BuildContext context,
          Future<void> Function(String rawValue) onDetect,
        ) {
          scanCallback = onDetect;
          return const SizedBox();
        }

        await pumpConnectionApp(
          tester,
          const MyApp(),
          engine: engine,
          dataSource: dataSource,
          scannerBuilder: mockScanner,
        );

        await tester.tap(find.text('Add Server'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
        );
        await tester.pumpAndSettle();

        // Scan invalid URI
        await scanCallback('vless://invalid-uri-without-at');
        await tester.pump();

        // Error SnackBar displayed
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byType(QrScanScreen), findsOneWidget);
        expect(dataSource.records, isEmpty);

        // Dismiss SnackBar and pump
        await tester.pumpAndSettle();

        // Scan valid URI after error: lock is released and save succeeds
        await scanCallback(validVlessUri);
        await tester.pumpAndSettle();

        expect(dataSource.records, hasLength(1));
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );

    testWidgets('subscription QR code displays subscription error without '
        'leaking secrets', (tester) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      late Future<void> Function(String rawValue) scanCallback;

      Widget mockScanner(
        BuildContext context,
        Future<void> Function(String rawValue) onDetect,
      ) {
        scanCallback = onDetect;
        return const SizedBox();
      }

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
        scannerBuilder: mockScanner,
      );

      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
      );
      await tester.pumpAndSettle();

      const subscriptionUrl = 'https://secret-token@example.com/subscription';
      await scanCallback(subscriptionUrl);
      await tester.pump();

      // Displays specialized subscription error
      expect(
        find.text(
          'This is a subscription URL. Please use the Add Subscription flow.',
        ),
        findsOneWidget,
      );
      expect(find.byType(QrScanScreen), findsOneWidget);
      expect(dataSource.records, isEmpty);

      // Security check: raw URL / secret token never leaked in Text widget
      expect(find.text(subscriptionUrl), findsNothing);
      expect(find.textContaining('secret-token'), findsNothing);
    });

    testWidgets('permission denied state renders retry button and transitions '
        'when granted', (tester) async {
      final fakeService = MutableCameraPermissionService(
        initialStatus: CameraPermissionStatus.denied,
        requestStatuses: const <CameraPermissionStatus>[
          CameraPermissionStatus.denied,
          CameraPermissionStatus.granted,
        ],
      );

      await pumpConnectionMaterialApp(
        tester,
        QrScanScreen(scannerBuilder: (context, onDetect) => const SizedBox()),
        engine: FakeVpnEngine(),
        cameraPermissionService: fakeService,
      );

      // Initial check called requestPermission once since initialStatus
      // was denied.
      expect(fakeService.requestPermissionCalls, equals(1));
      expect(
        find.text('Camera permission is required to scan QR codes.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('qr_scan_request_permission_button')),
        findsOneWidget,
      );
      expect(find.text('Point your camera at a server QR code'), findsNothing);

      // Tap "Grant Permission"
      await tester.tap(
        find.byKey(const ValueKey<String>('qr_scan_request_permission_button')),
      );
      await tester.pumpAndSettle();

      // Second requestPermission call returned granted; transitions to
      // scanner.
      expect(fakeService.requestPermissionCalls, equals(2));
      expect(
        find.text('Point your camera at a server QR code'),
        findsOneWidget,
      );
      expect(
        find.text('Camera permission is required to scan QR codes.'),
        findsNothing,
      );
    });

    testWidgets(
      'permission permanently denied state renders Open Settings button',
      (tester) async {
        final fakeService = MutableCameraPermissionService(
          initialStatus: CameraPermissionStatus.permanentlyDenied,
        );

        await pumpConnectionMaterialApp(
          tester,
          QrScanScreen(scannerBuilder: (context, onDetect) => const SizedBox()),
          engine: FakeVpnEngine(),
          cameraPermissionService: fakeService,
        );

        expect(
          find.text(
            'Camera permission is permanently denied. Please enable it in '
            'system settings.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('qr_scan_open_settings_button')),
          findsOneWidget,
        );

        // Tap "Open Settings"
        expect(fakeService.openSettingsCalls, equals(0));
        await tester.tap(
          find.byKey(const ValueKey<String>('qr_scan_open_settings_button')),
        );
        await tester.pumpAndSettle();

        expect(fakeService.openSettingsCalls, equals(1));
      },
    );

    testWidgets(
      'returning from settings via app resume auto-recovers to granted scanner',
      (tester) async {
        final fakeService = MutableCameraPermissionService(
          initialStatus: CameraPermissionStatus.permanentlyDenied,
        );

        await pumpConnectionMaterialApp(
          tester,
          QrScanScreen(scannerBuilder: (context, onDetect) => const SizedBox()),
          engine: FakeVpnEngine(),
          cameraPermissionService: fakeService,
        );

        expect(
          find.text(
            'Camera permission is permanently denied. Please enable it in '
            'system settings.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('qr_scan_open_settings_button')),
          findsOneWidget,
        );

        // Tap "Open Settings"
        await tester.tap(
          find.byKey(const ValueKey<String>('qr_scan_open_settings_button')),
        );
        await tester.pumpAndSettle();
        expect(fakeService.openSettingsCalls, equals(1));

        // User enables camera permission in settings and resumes app
        fakeService.initialStatus = CameraPermissionStatus.granted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // Screen auto-transitions to granted scanner preview
        expect(
          find.text('Point your camera at a server QR code'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Camera permission is permanently denied. Please enable it in '
            'system settings.',
          ),
          findsNothing,
        );
      },
    );

    testWidgets('cancel button pops QrScanScreen without modifying '
        'repository', (tester) async {
      final engine = FakeVpnEngine();
      final dataSource = FakeServerProfileDataSource();
      addTearDown(engine.dispose);

      await pumpConnectionApp(
        tester,
        const MyApp(),
        engine: engine,
        dataSource: dataSource,
        scannerBuilder: (context, onDetect) => const SizedBox(),
      );

      await tester.tap(find.text('Add Server'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('add_server_scan_qr_button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrScanScreen), findsOneWidget);

      // Tap "Cancel" button
      await tester.tap(
        find.byKey(const ValueKey<String>('qr_scan_cancel_button')),
      );
      await tester.pumpAndSettle();

      // QrScanScreen popped, returned to AddServerScreen, repository untouched
      expect(find.byType(QrScanScreen), findsNothing);
      expect(find.byType(AddServerScreen), findsOneWidget);
      expect(dataSource.records, isEmpty);
    });
  });
}
