// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/logging/log_manager.dart';

/// Live diagnostic logs screen displaying native tunnel engine logs.
///
/// Bounded in memory to prevent OOM during long VPN sessions.
class LiveLogsScreen extends ConsumerWidget {
  const LiveLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logManagerProvider);
    final logList = logs.toList();

    return Scaffold(
      appBar: AppBar(title: Text('settings.live_logs'.tr())),
      body: logList.isEmpty
          ? Center(
              child: Text(
                'settings.no_logs'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: logList.length,
              itemBuilder: (context, index) {
                final log = logList[logList.length - 1 - index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
