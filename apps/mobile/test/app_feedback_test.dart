// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:core_domain/core_domain.dart'
    show
        Connected,
        Disconnected,
        Error,
        InvalidConfig,
        PermissionDenied,
        PlatformError,
        Unknown;
import 'package:core_vpn_engine/core_vpn_engine.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/connection/presentation/screens/home_screen.dart';

import 'localization_test_harness.dart';

class _CustomDomainError implements HasUserMessage {
  const _CustomDomainError(this.message);

  final String message;

  @override
  String toUserMessage() => message;
}

void main() {
  setUpAll(initTestLocalization);

  group('ErrorMapper — localization mapping tests', () {
    testWidgets('maps ConnectionErrorReason variants to localized strings', (
      tester,
    ) async {
      await pumpLocalizedApp(tester, localizedMaterialApp());
      expect(
        ErrorMapper.mapToUserMessage(const PermissionDenied()),
        equals('VPN permission was denied by the system'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const InvalidConfig()),
        equals('The server configuration is invalid'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const PlatformError('native failure')),
        equals('VPN engine encountered an internal error'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const Unknown()),
        equals('An unknown connection error occurred'),
      );
    });

    testWidgets('unwraps core_domain.Error and maps its reason', (
      tester,
    ) async {
      await pumpLocalizedApp(tester, localizedMaterialApp());
      expect(
        ErrorMapper.mapToUserMessage(const Error(PermissionDenied())),
        equals('VPN permission was denied by the system'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const Error(InvalidConfig())),
        equals('The server configuration is invalid'),
      );
    });

    testWidgets('maps VpnCommandResult failure variants', (tester) async {
      await pumpLocalizedApp(tester, localizedMaterialApp());
      expect(
        ErrorMapper.mapToUserMessage(const VpnCommandRejectedBusy()),
        equals('A VPN operation is already in progress'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const VpnCommandRejectedInvalidConfig()),
        equals('The server configuration is invalid'),
      );
      expect(
        ErrorMapper.mapToUserMessage(
          const VpnCommandRejectedPermissionDenied(),
        ),
        equals('VPN permission was denied by the system'),
      );
      expect(
        ErrorMapper.mapToUserMessage(const VpnCommandFailed()),
        equals('VPN engine encountered an internal error'),
      );
    });

    testWidgets('respects HasUserMessage interface', (tester) async {
      await pumpLocalizedApp(tester, localizedMaterialApp());
      const custom = _CustomDomainError('Custom localized error message');
      expect(
        ErrorMapper.mapToUserMessage(custom),
        equals('Custom localized error message'),
      );
    });

    testWidgets(
      'falls back to generic error for unrecognized objects or null',
      (tester) async {
        await pumpLocalizedApp(tester, localizedMaterialApp());
        expect(
          ErrorMapper.mapToUserMessage(Exception('random')),
          equals('An unexpected error occurred'),
        );
        expect(
          ErrorMapper.mapToUserMessage(null),
          equals('An unexpected error occurred'),
        );
      },
    );

    testWidgets(
      'mapConnectionState returns error string only for Error state',
      (tester) async {
        await pumpLocalizedApp(tester, localizedMaterialApp());
        expect(ErrorMapper.mapConnectionState(const Disconnected()), isNull);
        expect(ErrorMapper.mapConnectionState(const Connected()), isNull);
        expect(
          ErrorMapper.mapConnectionState(const Error(PermissionDenied())),
          equals('VPN permission was denied by the system'),
        );
      },
    );
  });

  group('AppFeedback — widget tests', () {
    testWidgets('showError displays floating SnackBar with error styling', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    AppFeedback.showError(context, 'Test error message');
                  },
                  child: const Text('Trigger Error'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Error'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Test error message'), findsOneWidget);

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, equals(SnackBarBehavior.floating));
    });

    testWidgets('showSuccess and showInfo display floating SnackBars', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        AppFeedback.showSuccess(context, 'Success message');
                      },
                      child: const Text('Trigger Success'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        AppFeedback.showInfo(context, 'Info message');
                      },
                      child: const Text('Trigger Info'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Trigger Success'));
      await tester.pumpAndSettle();
      expect(find.text('Success message'), findsOneWidget);

      await tester.tap(find.text('Trigger Info'));
      await tester.pumpAndSettle();
      expect(find.text('Info message'), findsOneWidget);
    });
  });

  group('HomeScreen — error presentation integration', () {
    testWidgets(
      'engine error emission triggers SnackBar via ErrorMapper and AppFeedback',
      (tester) async {
        final engine = FakeVpnEngine();
        addTearDown(engine.dispose);

        await pumpConnectionMaterialApp(
          tester,
          const HomeScreen(),
          engine: engine,
        );

        // Initially disconnected, no snackbar
        expect(find.byType(SnackBar), findsNothing);

        // Engine enters Error state (PermissionDenied)
        engine.emit(const Error(PermissionDenied()));
        await tester.pumpAndSettle();

        // SnackBar is shown with localized error message
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text('VPN permission was denied by the system'),
          findsOneWidget,
        );

        // Next error replaces previous snackbar cleanly
        engine.emit(const Error(InvalidConfig()));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text('The server configuration is invalid'),
          findsOneWidget,
        );
      },
    );
  });
}
