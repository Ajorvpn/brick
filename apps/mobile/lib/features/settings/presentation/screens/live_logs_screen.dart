// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';

/// Live diagnostic logs screen displaying native tunnel engine logs.
///
/// Backed by a virtualized list, structured log level badges, and an
/// auto-scrolling mechanism that pauses on user scroll-up and can be
/// resumed manually via a floating action button or by scrolling to the bottom.
class LiveLogsScreen extends ConsumerStatefulWidget {
  /// Creates the live logs screen.
  const LiveLogsScreen({super.key, this.titleKey = 'settings.live_logs'});

  /// The localization key for the screen's AppBar title.
  final String titleKey;

  @override
  ConsumerState<LiveLogsScreen> createState() => _LiveLogsScreenState();
}

class _LiveLogsScreenState extends ConsumerState<LiveLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScrollEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomIfNeeded();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded() {
    if (_autoScrollEnabled && _scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  Color _levelColor(LogLevel level, ColorScheme scheme) {
    switch (level) {
      case LogLevel.fatal:
      case LogLevel.error:
        return scheme.error;
      case LogLevel.warning:
        return Colors.orange.shade800;
      case LogLevel.info:
        return scheme.primary;
      case LogLevel.debug:
      case LogLevel.trace:
        return scheme.outline;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _handleCopyLogs(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey<String>('logs_privacy_warning_dialog'),
          title: Text('logs.copy_warning_title'.tr()),
          content: Text('logs.copy_warning_body'.tr()),
          actions: [
            TextButton(
              key: const ValueKey<String>('logs_copy_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('logs.copy_cancel'.tr()),
            ),
            FilledButton(
              key: const ValueKey<String>('logs_copy_confirm_button'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('logs.copy_confirm'.tr()),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final currentEntries = ref.read(structuredLogEntriesProvider);
    if (currentEntries.isEmpty) return;

    final payload = currentEntries
        .map((entry) {
          final time = entry.timestamp.toUtc().toIso8601String();
          final sourceTag = (entry.source != null && entry.source!.isNotEmpty)
              ? ' [${entry.source}]'
              : '';
          final msg = entry.message.isNotEmpty ? entry.message : entry.raw;
          return '$time [${entry.level.label}]$sourceTag $msg';
        })
        .join('\n');

    await Clipboard.setData(ClipboardData(text: payload));

    if (!context.mounted) return;
    AppFeedback.showInfo(context, 'logs.copied_to_clipboard'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(structuredLogEntriesProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    ref.listen<List<LogEntry>>(structuredLogEntriesProvider, (previous, next) {
      if (_autoScrollEnabled &&
          (previous == null ||
              previous.isEmpty ||
              next.isEmpty ||
              next.last != previous.last)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottomIfNeeded();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titleKey.tr()),
        actions: [
          IconButton(
            key: const ValueKey<String>('logs_copy_button'),
            tooltip: 'logs.copy_tooltip'.tr(),
            icon: const Icon(Icons.copy_outlined),
            onPressed: entries.isEmpty
                ? null
                : () {
                    unawaited(_handleCopyLogs(context));
                  },
          ),
          IconButton(
            key: const ValueKey<String>('logs_clear_button'),
            tooltip: 'logs.clear_tooltip'.tr(),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              unawaited(ref.read(logManagerProvider.notifier).clear());
            },
          ),
        ],
      ),
      floatingActionButton: (!_autoScrollEnabled && entries.isNotEmpty)
          ? FloatingActionButton.extended(
              key: const ValueKey<String>('logs_jump_to_latest_button'),
              onPressed: () {
                if (_scrollController.hasClients) {
                  _scrollController.jumpTo(
                    _scrollController.position.maxScrollExtent,
                  );
                }
                setState(() {
                  _autoScrollEnabled = true;
                });
              },
              icon: const Icon(Icons.arrow_downward),
              label: Text('logs.jump_to_latest'.tr()),
            )
          : null,
      body: entries.isEmpty
          ? Center(
              child: Text(
                'settings.no_logs'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification ||
                    notification is UserScrollNotification) {
                  final metrics = notification.metrics;
                  if (metrics.maxScrollExtent > 0) {
                    final distanceToBottom =
                        metrics.maxScrollExtent - metrics.pixels;
                    if (distanceToBottom > 48.0 && _autoScrollEnabled) {
                      setState(() {
                        _autoScrollEnabled = false;
                      });
                    } else if (distanceToBottom <= 12.0 &&
                        !_autoScrollEnabled) {
                      setState(() {
                        _autoScrollEnabled = true;
                      });
                    }
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return Padding(
                    key: ValueKey<String>('log_entry_tile_$index'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              key: ValueKey<String>(
                                'log_level_badge_${entry.level.name}_$index',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _levelColor(
                                  entry.level,
                                  scheme,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _levelColor(
                                    entry.level,
                                    scheme,
                                  ).withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                entry.level.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _levelColor(entry.level, scheme),
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(entry.timestamp.toUtc()),
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                            if (entry.source != null &&
                                entry.source!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                '[${entry.source}]',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.primary,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          entry.message.isNotEmpty ? entry.message : entry.raw,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
