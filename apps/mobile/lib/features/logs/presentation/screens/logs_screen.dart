// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:mobile/features/settings/presentation/screens/live_logs_screen.dart';

/// Screen for the `logs` feature shell branch.
///
/// Delegates to [LiveLogsScreen] to present bounded real-time diagnostic logs.
class LogsScreen extends StatelessWidget {
  /// Creates the logs screen.
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LiveLogsScreen(titleKey: 'logs.title');
  }
}
