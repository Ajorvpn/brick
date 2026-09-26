// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('app boots and renders the MaterialApp.router shell', (
    WidgetTester tester,
  ) async {
    // The original counter smoke test was removed in P1-T8: the
    // `MaterialApp(home: MyHomePage)` counter demo it exercised no longer
    // exists, and routing behaviour is covered in `app_router_test.dart`.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
