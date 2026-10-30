// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/connection/presentation/widgets/connection_state_badge.dart';
import 'package:vpn_engine_android/vpn_engine_android.dart';

/// Test harness for Gate B Flutter integration chaos testing.
///
/// Drives integration tests through the real Flutter UI and verifies
/// that Dart-side state remains synchronized with native truth.

/// Key of the [ConnectionStateBadge] chip.
const Key connectionBadgeKey = ValueKey<String>('connection_state_badge');

/// Key of the ThroughputReadout widget.
const Key throughputKey = ValueKey<String>('throughput_readout');

/// Fake VLESS URI used for testing (contains dummy credentials only).
const String dummyVlessUri =
    'vless://11111111-2222-3333-4444-555555555555@example.com:443#Chaos%20Node';

/// Initializes the test binding for real-device execution.
IntegrationTestWidgetsFlutterBinding initChaosTestHarness() {
  return IntegrationTestWidgetsFlutterBinding.ensureInitialized();
}

/// Extracts the raw string label from the [ConnectionStateBadge].
String getBadgeText(WidgetTester tester) {
  final chip = tester.widget<Chip>(find.byKey(connectionBadgeKey));
  final labelWidget = chip.label;
  if (labelWidget is Text) {
    return labelWidget.data ?? '';
  }
  return '';
}

/// Extracts the raw string label from the ThroughputReadout.
String getThroughputText(WidgetTester tester) {
  final textWidget = tester.widget<Text>(find.byKey(throughputKey));
  return textWidget.data ?? '';
}

/// Polls the badge text until [condition] is met or [timeout] elapses.
Future<String> waitForBadgeText(
  WidgetTester tester,
  bool Function(String text) condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(pollInterval);
    final text = getBadgeText(tester);
    if (condition(text)) {
      return text;
    }
  }
  final finalBadge = getBadgeText(tester);
  throw TimeoutException(
    'ConnectionStateBadge condition was not satisfied within $timeout. '
    'Final text: "$finalBadge"',
  );
}

/// Directly queries the authoritative native VPN state via Pigeon HostApi.
Future<VpnNativeState> getNativeVpnState() async {
  final event = await VpnEngineHostApi().getStatus();
  return event.state;
}
