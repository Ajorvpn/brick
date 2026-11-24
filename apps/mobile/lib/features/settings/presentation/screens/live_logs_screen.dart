// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

// `intl` (re-exported by easy_localization) also defines a `TextDirection`
// whose constants are `LTR`/`RTL`; hide it so this file resolves Flutter's
// `dart:ui` `TextDirection` (with `.ltr`/`.rtl`) instead.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/logging/log_entry.dart';
import 'package:mobile/core/logging/log_manager.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:ui_theme/ui_theme.dart';

/// Live diagnostic logs screen displaying native tunnel engine logs.
///
/// Backed by a virtualized list, structured log level badges, and an
/// auto-scrolling mechanism that pauses on user scroll-up and can be
/// resumed manually via a floating action button or by scrolling to the bottom.
///
/// Visually rendered in the "Obsidian Glass & Brick Ember" language: an
/// obsidian `AppBar` with a monospace entry-count badge, a glass empty state,
/// and high-contrast virtualized terminal rows led by a semantic level rail.
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

  /// Resolves a WCAG AA compliant semantic hue for a structured log level.
  ///
  /// Dark mode uses soft high-contrast hues over the obsidian surface; light
  /// mode uses deep hues (>= 5.8:1 on the ceramic surface / level pill).
  Color _levelColor(LogLevel level, BrickSemanticColors colors, bool isDark) {
    switch (level) {
      case LogLevel.fatal:
      case LogLevel.error:
        return isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
      case LogLevel.warning:
        // Light mode needs a deeper amber than `stateConnecting`: composited
        // over the level pill it only reaches 4.25:1. This hue clears 5.8:1.
        return isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E);
      case LogLevel.info:
        // Likewise, `brandBrick` reaches only 4.32:1 inside the light pill.
        return isDark ? colors.brandBrick : const Color(0xFF9A3412);
      case LogLevel.debug:
      case LogLevel.trace:
        return colors.textMuted;
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _handleCopyLogs(BuildContext context) async {
    final colors = context.brickColors;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          key: const ValueKey<String>('logs_privacy_warning_dialog'),
          title: Row(
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 20,
                color: colors.stateConnecting,
              ),
              const SizedBox(width: BrickSpacing.xs),
              Expanded(child: Text('logs.copy_warning_title'.tr())),
            ],
          ),
          content: Text('logs.copy_warning_body'.tr()),
          actions: [
            OutlinedButton(
              key: const ValueKey<String>('logs_copy_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('logs.copy_cancel'.tr()),
            ),
            FilledButton(
              key: const ValueKey<String>('logs_copy_confirm_button'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.brandBrick,
                foregroundColor: colors.onAccent,
              ),
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
    final colors = context.brickColors;
    final isDark = theme.brightness == Brightness.dark;
    // `AppShell` uses `extendBody: true`, so this route's own Scaffold floats
    // under the dock: the inset carries the dock height + gesture area (and is
    // 0.0 when the screen is opened standalone).
    final bottomInset = MediaQuery.paddingOf(context).bottom;

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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.titleKey.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: BrickSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(BrickRadius.xs),
                border: Border.all(color: colors.glassBorder),
              ),
              child: Text(
                '${entries.length}',
                style: BrickTypography.monoLog(color: colors.textMuted),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey<String>('logs_copy_button'),
            tooltip: 'logs.copy_tooltip'.tr(),
            icon: const Icon(Icons.copy_outlined),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(BrickSpacing.minTouchTarget),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
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
            style: IconButton.styleFrom(
              minimumSize: const Size.square(BrickSpacing.minTouchTarget),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            onPressed: () {
              unawaited(ref.read(logManagerProvider.notifier).clear());
            },
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      floatingActionButton: (!_autoScrollEnabled && entries.isNotEmpty)
          ? Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: FloatingActionButton.extended(
                key: const ValueKey<String>('logs_jump_to_latest_button'),
                backgroundColor: colors.brandBrick,
                foregroundColor: colors.onAccent,
                elevation: 2,
                shape: const StadiumBorder(),
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
                icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                label: Text(
                  'logs.jump_to_latest'.tr(),
                  style: const TextStyle(
                    fontFamily: BrickTypography.primaryFontFamily,
                    fontSize: BrickTypography.sizeLabel,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          : null,
      body: entries.isEmpty
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: BrickSpacing.maxReadableWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(BrickSpacing.lg),
                  child: BrickGlassCard(
                    padding: const EdgeInsets.all(BrickSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: colors.surfaceElevated,
                            borderRadius: BorderRadius.circular(
                              BrickRadius.card,
                            ),
                            border: Border.all(color: colors.glassBorder),
                          ),
                          child: Icon(
                            Icons.terminal_rounded,
                            size: 28,
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: BrickSpacing.md),
                        Text(
                          'settings.no_logs'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: BrickSpacing.maxReadableWidth,
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      0,
                      BrickSpacing.xs,
                      0,
                      bottomInset + BrickSpacing.section,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final levelColor = _levelColor(
                        entry.level,
                        colors,
                        isDark,
                      );
                      final bgAlpha = isDark ? 0.14 : 0.07;
                      final borderAlpha = isDark ? 0.36 : 0.28;
                      final hasSource =
                          entry.source != null && entry.source!.isNotEmpty;

                      // Persian renders RTL, but engine log lines,
                      // timestamps, level pills and redacted endpoints are
                      // technical data: pin them to LTR so bidi reordering
                      // never scrambles a host, port or timestamp.
                      return Directionality(
                        textDirection: TextDirection.ltr,
                        child: DecoratedBox(
                          key: ValueKey<String>('log_entry_tile_$index'),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: colors.glassBorder),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: BrickSpacing.md,
                              vertical: BrickSpacing.xs,
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: levelColor.withValues(alpha: 0.70),
                                    width: 2.5,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: BrickSpacing.sm,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // A `Wrap` keeps the level badge, UTC
                                    // timestamp and source readable at 1.5x /
                                    // 2.0x font sizes by flowing onto a second
                                    // line instead of overflowing the row.
                                    Wrap(
                                      spacing: BrickSpacing.xs,
                                      runSpacing: BrickSpacing.xxs,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          key: ValueKey<String>(
                                            'log_level_badge_'
                                            '${entry.level.name}_$index',
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: levelColor.withValues(
                                              alpha: bgAlpha,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              BrickRadius.xs,
                                            ),
                                            border: Border.all(
                                              color: levelColor.withValues(
                                                alpha: borderAlpha,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            entry.level.label,
                                            style:
                                                BrickTypography.monoLog(
                                                  color: levelColor,
                                                ).copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          _formatTime(entry.timestamp.toUtc()),
                                          style: BrickTypography.monoLog(
                                            color: colors.textMuted,
                                          ),
                                        ),
                                        if (hasSource)
                                          Text(
                                            '[${entry.source}]',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style:
                                                BrickTypography.monoLog(
                                                  color: colors.brandBrick,
                                                ).copyWith(
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: BrickSpacing.xxs),
                                    SelectableText(
                                      entry.message.isNotEmpty
                                          ? entry.message
                                          : entry.raw,
                                      style: BrickTypography.monoLog(
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }
}
