// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:core_domain/core_domain.dart' show Connected, Connecting;
import 'package:core_vpn_engine/core_vpn_engine.dart' show VpnCommandAccepted;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/features/connection/domain/entities/connection_location_target.dart';
import 'package:mobile/features/connection/domain/entities/saved_server.dart';
import 'package:mobile/features/connection/presentation/providers/active_server_provider.dart';
import 'package:mobile/features/connection/presentation/providers/auto_reconnect_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_controller_provider.dart';
import 'package:mobile/features/connection/presentation/providers/connection_state_provider.dart';
import 'package:mobile/features/servers/data/services/built_in_directory_sync_service.dart';
import 'package:mobile/features/servers/domain/built_in_feed_config.dart';
import 'package:mobile/features/servers/domain/entities/subscription_metadata.dart';
import 'package:mobile/features/servers/domain/models/server_location_group.dart';
import 'package:mobile/features/servers/presentation/providers/built_in_directory_sync_provider.dart';
import 'package:mobile/features/servers/presentation/providers/server_list_provider.dart';
import 'package:mobile/features/servers/presentation/providers/server_management_controller.dart';
import 'package:mobile/features/servers/presentation/widgets/server_profile_tile.dart'
    show BrokenServerTile;
import 'package:mobile/features/servers/presentation/widgets/update_servers_disclosure_sheet.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;
import 'package:ui_theme/ui_theme.dart';

/// Screen showing high-level VPN location selection (`Smart Auto` + countries).
///
/// Obsidian Glass consumer selector:
/// 1. Reactive Riverpod integration via [groupedServerListProvider] and
///    [resolvedLocationTargetProvider].
/// 2. Custom obsidian header bar with a play-compliant `Update Servers`
///    action (disclosure sheet when no subscription feed exists).
/// 3. Instant search across `Smart Auto` and country names/codes.
/// 4. Active location spotlight card.
/// 5. Linked subscription feed strip with refresh and cascade-delete actions.
/// 6. Top hero `Smart Auto` card + flat country-only cards (each backed by a
///    scoped `sing-box` `urltest` pool).
/// 7. Safe broken-server recovery section without credential leakage.
class ServersScreen extends ConsumerStatefulWidget {
  /// Creates the servers screen.
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(groupedServerListProvider);
    final data = listAsync.value;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, data),
            _buildDirectorySyncBanner(context, data),
            Expanded(
              child: listAsync.when(
                loading: () => _buildLoadingSkeleton(context),
                error: (error, _) =>
                    Center(child: Text('connection.load_failed'.tr())),
                data: (data) {
                  if (data.isEmpty) {
                    return _buildEmptyState(context, data);
                  }
                  return _buildPopulatedBrowser(context, data);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(BuildContext context, GroupedServerList? data) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final refreshingIds =
        ref.watch(serverManagementControllerProvider).value ?? const <String>{};
    final isRefreshing = refreshingIds.isNotEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: BrickSpacing.maxReadableWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            BrickSpacing.md,
            BrickSpacing.md,
            BrickSpacing.md,
            BrickSpacing.sm,
          ),
          child: Row(
            children: [
              const BrickEmblemPlaceholder(size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        'servers.title'.tr(),
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(BrickRadius.xs),
                        border: Border.all(color: colors.glassBorder),
                      ),
                      child: Text(
                        (data?.totalCount ?? 0).toString(),
                        style: BrickTypography.monoLog(color: colors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BrickSpacing.xs),
              // Flexible lets the pill shrink (label ellipsizes) instead of
              // overflowing the header at 1.5x / 2.0x system font sizes.
              Flexible(
                // Rebuilds only when a directory sync starts or finishes, so a
                // background refresh never rebuilds the whole header.
                child: ListenableBuilder(
                  listenable: ref.watch(builtInDirectorySyncControllerProvider),
                  builder: (context, _) => _buildUpdateServersButton(
                    context,
                    isRefreshing:
                        isRefreshing ||
                        ref
                            .read(builtInDirectorySyncControllerProvider)
                            .isSyncing,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateServersButton(
    BuildContext context, {
    required bool isRefreshing,
  }) {
    final colors = context.brickColors;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: BrickSpacing.minTouchTarget),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.brandBrickSoft,
          borderRadius: BorderRadius.circular(BrickRadius.pill),
          border: Border.all(color: colors.brandBrick.withValues(alpha: 0.35)),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey<String>('servers_update_button'),
            borderRadius: BorderRadius.circular(BrickRadius.pill),
            onTap: isRefreshing ? null : () => _handleUpdateServers(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BrickSpacing.sm,
                vertical: BrickSpacing.xs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRefreshing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.brandBrick,
                      ),
                    )
                  else
                    Icon(
                      Icons.sync_rounded,
                      size: 18,
                      color: colors.brandBrick,
                    ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isRefreshing
                          ? 'servers.updating_servers'.tr()
                          : 'servers.update_servers'.tr(),
                      style: TextStyle(
                        fontFamily: BrickTypography.primaryFontFamily,
                        fontSize: BrickTypography.sizeLabel,
                        fontWeight: FontWeight.w700,
                        color: colors.brandBrick,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Runs a manual directory refresh.
  ///
  /// The Play-compliant disclosure is shown once, on the first manual sync;
  /// afterwards `Update Servers` refreshes immediately. Automatic background
  /// refreshes are governed by the same 30-minute throttle either way.
  Future<void> _handleUpdateServers(BuildContext context) async {
    final preferences = ref.read(appPreferencesRepositoryProvider);
    if (!preferences.hasAcceptedDirectorySync()) {
      final accepted = await UpdateServersDisclosureSheet.show(context);
      if (accepted != true) return;
      await preferences.setDirectorySyncAccepted(accepted: true);
      if (!context.mounted) return;
    }

    final result = await ref
        .read(builtInDirectorySyncControllerProvider)
        .forceSync();

    if (!context.mounted) return;

    switch (result) {
      case DirectorySyncSuccess(:final serverCount):
        AppFeedback.showSuccess(
          context,
          'servers.sync_success'.tr(namedArgs: {'count': '$serverCount'}),
        );
      case DirectorySyncSkipped():
        // Not reachable from a manual tap, but exhaustive by construction.
        break;
      case DirectorySyncFailure():
        // Cached servers are still on screen: say so rather than implying the
        // list is gone. The inline offline/retry banner covers the empty case.
        final controller = ref.read(builtInDirectorySyncControllerProvider);
        AppFeedback.showInfo(
          context,
          (controller.serverCount > 0
                  ? 'servers.sync_cached_notice'
                  : 'servers.sync_failed_offline')
              .tr(),
        );
    }
  }

  /// Calm, non-blocking status line for the built-in server directory.
  ///
  /// Shows progress only while a sync is actually running, and an offline/retry
  /// hint only when the list is completely empty — a cached directory is never
  /// announced with extra chrome the user did not ask for.
  Widget _buildDirectorySyncBanner(
    BuildContext context,
    GroupedServerList? data,
  ) {
    final controller = ref.watch(builtInDirectorySyncControllerProvider);
    final colors = context.brickColors;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isSyncing = controller.isSyncing;
        final isEmpty = data?.isEmpty ?? true;
        if (!isSyncing && !(controller.hasFailed && isEmpty)) {
          return const SizedBox.shrink();
        }

        final label = isSyncing
            ? 'servers.sync_in_progress'.tr()
            : 'servers.sync_failed_offline'.tr();

        return Padding(
          key: const ValueKey<String>('servers_directory_sync_banner'),
          padding: const EdgeInsets.fromLTRB(
            BrickSpacing.md,
            0,
            BrickSpacing.md,
            BrickSpacing.xs,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: BrickSpacing.maxReadableWidth,
              ),
              child: Row(
                children: [
                  if (isSyncing)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.brandBrick,
                      ),
                    )
                  else
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 16,
                      color: colors.textMuted,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontFamily: BrickTypography.primaryFontFamily,
                        fontSize: BrickTypography.sizeLabel,
                        fontWeight: FontWeight.w400,
                        color: colors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Loading skeleton
  // ---------------------------------------------------------------------------

  /// Shimmer placeholders shaped like the populated browser (search field +
  /// country group cards) so the first paint matches the loaded layout.
  Widget _buildLoadingSkeleton(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: BrickSpacing.maxReadableWidth,
        ),
        child: ListView(
          key: const ValueKey<String>('servers_loading_skeleton'),
          padding: const EdgeInsets.fromLTRB(
            BrickSpacing.md,
            0,
            BrickSpacing.md,
            BrickSpacing.xl,
          ),
          children: [
            const BrickSkeletonBox(height: 48),
            const SizedBox(height: BrickSpacing.sm),
            for (var i = 0; i < 3; i++) ...[
              const BrickGlassCard(
                padding: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      BrickSkeletonBox(width: 40, height: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BrickSkeletonBox(height: 14),
                            SizedBox(height: BrickSpacing.xs),
                            FractionallySizedBox(
                              widthFactor: 0.5,
                              alignment: AlignmentDirectional.centerStart,
                              child: BrickSkeletonBox(height: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: BrickSpacing.xs),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Empty state
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(BuildContext context, GroupedServerList data) {
    final theme = Theme.of(context);
    final colors = context.brickColors;

    return Center(
      key: const ValueKey<String>('servers_empty_state'),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          BrickSpacing.lg,
          BrickSpacing.lg,
          BrickSpacing.lg,
          MediaQuery.paddingOf(context).bottom + BrickSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: BrickSpacing.maxReadableWidth,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.brandBrickSoft,
                  border: Border.all(
                    color: colors.brandBrick.withValues(alpha: 0.25),
                  ),
                ),
                child: const Center(child: BrickEmblemPlaceholder(size: 64)),
              ),
              const SizedBox(height: BrickSpacing.lg),
              Text(
                'servers.empty_title'.tr(),
                style: TextStyle(
                  fontFamily: BrickTypography.primaryFontFamily,
                  fontSize: BrickTypography.sizeTitle,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'servers.empty_subtitle'.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey<String>('servers_empty_update_button'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(
                    BrickSpacing.minTouchTarget,
                  ),
                  backgroundColor: colors.brandBrick,
                  foregroundColor: colors.onAccent,
                ),
                onPressed: () => _handleUpdateServers(context),
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text('servers.update_servers'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Populated browser
  // ---------------------------------------------------------------------------

  Widget _buildPopulatedBrowser(BuildContext context, GroupedServerList data) {
    final locationTarget = ref.watch(resolvedLocationTargetProvider);
    final connectionState = ref.watch(connectionStateProvider).value;
    final isConnected = connectionState is Connected;

    final allValidServers = <SavedServerProfile>[
      ...data.standalone,
      for (final servers in data.subscriptionGroups.values) ...servers,
    ];

    // The official directory has its own sync path (mirror failover, throttle
    // and acceptance disclosure) and must never be presented as a user-owned
    // feed with its own refresh and delete actions.
    final userSubscriptions = data.subscriptionGroups.entries
        .where((entry) => entry.key.id != kBuiltInDirectorySubscriptionId)
        .toList(growable: false);

    final allCountryGroups = ServerLocationGrouper.group(allValidServers);
    final query = _searchQuery.trim().toLowerCase();
    final isSearching = query.isNotEmpty;

    final filteredCountryGroups = isSearching
        ? allCountryGroups
              .where((group) {
                final displayName =
                    group.countryCode == ServerLocationParser.unknownCountryCode
                    ? 'servers.other_locations'.tr().toLowerCase()
                    : group.countryName.toLowerCase();
                final codeMatch =
                    group.countryCode !=
                        ServerLocationParser.unknownCountryCode &&
                    group.countryCode.toLowerCase().contains(query);
                return displayName.contains(query) || codeMatch;
              })
              .toList(growable: false)
        : allCountryGroups;

    final showSmartAuto =
        allValidServers.isNotEmpty &&
        (!isSearching || _matchesSmartAutoQuery(query));

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: BrickSpacing.maxReadableWidth,
        ),
        child: ListView(
          // `extendBody` floats the dock over the list, so the bottom inset
          // carries the dock height + gesture area.
          padding: EdgeInsets.fromLTRB(
            BrickSpacing.md,
            0,
            BrickSpacing.md,
            MediaQuery.paddingOf(context).bottom + BrickSpacing.xl,
          ),
          children: [
            _buildSearchField(context),
            if (allValidServers.isNotEmpty && !isSearching) ...[
              const SizedBox(height: BrickSpacing.sm),
              _buildActiveSpotlight(
                context,
                locationTarget,
                allCountryGroups,
                isConnected,
              ),
            ],
            if (userSubscriptions.isNotEmpty) ...[
              const SizedBox(height: BrickSpacing.sm),
              _buildSubscriptionFeeds(context, userSubscriptions),
            ],
            const SizedBox(height: BrickSpacing.sm),
            if (isSearching && !showSmartAuto && filteredCountryGroups.isEmpty)
              _buildNoMatchesState(context)
            else ...[
              if (showSmartAuto) ...[
                _buildSmartAutoCard(
                  context,
                  countryCount: allCountryGroups.length,
                  isSelected: locationTarget is SmartAutoTarget,
                  isConnected: isConnected,
                ),
                const SizedBox(height: BrickSpacing.xs),
              ],
              for (final group in filteredCountryGroups) ...[
                _buildCountryGroupCard(
                  context,
                  group,
                  isSelected:
                      locationTarget is CountryTarget &&
                      locationTarget.countryCode == group.countryCode,
                  isConnected: isConnected,
                ),
                const SizedBox(height: BrickSpacing.xs),
              ],
            ],
            if (data.broken.isNotEmpty && !isSearching) ...[
              const SizedBox(height: BrickSpacing.md),
              BrickSectionHeader(
                title: 'connection.broken_title'.tr(),
                icon: Icons.warning_amber_rounded,
                countLabel: '${data.broken.length}',
              ),
              const SizedBox(height: BrickSpacing.xs),
              for (final broken in data.broken)
                BrokenServerTile(
                  server: broken,
                  onDelete: () => _showConfirmDeleteDialog(
                    context,
                    title: 'servers.delete_server_title'.tr(),
                    message: 'servers.delete_server_message'.tr(),
                    onConfirm: () => _handleDeleteServer(context, broken.id),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static bool _matchesSmartAutoQuery(String normalizedQuery) {
    final localizedTitle = 'servers.smart_auto_title'.tr().toLowerCase();
    return localizedTitle.contains(normalizedQuery) ||
        'smart auto'.contains(normalizedQuery) ||
        'automatic'.contains(normalizedQuery) ||
        'fastest'.contains(normalizedQuery) ||
        'هوشمند'.contains(normalizedQuery) ||
        'خودکار'.contains(normalizedQuery);
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = context.brickColors;

    return TextField(
      key: const ValueKey<String>('servers_search_field'),
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'servers.search_hint'.tr(),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: colors.textMuted,
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                key: const ValueKey<String>('servers_search_clear'),
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colors.textMuted,
                ),
                tooltip: 'servers.clear_search'.tr(),
                constraints: const BoxConstraints(
                  minWidth: BrickSpacing.minTouchTarget,
                  minHeight: BrickSpacing.minTouchTarget,
                ),
                onPressed: _clearSearch,
              ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  Widget _buildActiveSpotlight(
    BuildContext context,
    ConnectionLocationTarget target,
    List<CountryLocationGroup> countryGroups,
    bool isConnected,
  ) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final accentColor = isConnected ? colors.stateConnected : colors.brandBrick;

    final String leadingGlyph;
    final String title;
    final String subtitle;
    switch (target) {
      case SmartAutoTarget():
        leadingGlyph = '⚡';
        title = 'servers.smart_auto_title'.tr();
        subtitle = 'servers.smart_auto_subtitle'.tr();
      case CountryTarget(:final countryCode):
        var serverCount = 0;
        for (final group in countryGroups) {
          if (group.countryCode == countryCode) {
            serverCount = group.totalServerCount;
            break;
          }
        }
        leadingGlyph = ServerLocationParser.emojiForCountryCode(countryCode);
        title = countryCode == ServerLocationParser.unknownCountryCode
            ? 'servers.other_locations'.tr()
            : ServerLocationParser.countryNameForCode(countryCode);
        subtitle = serverCount == 1
            ? 'servers.server_count_one'.tr()
            : 'servers.country_auto_subtitle'.tr(
                namedArgs: {'count': '$serverCount'},
              );
    }

    return BrickGlassCard(
      key: const ValueKey<String>('servers_active_spotlight'),
      isSelected: true,
      elevated: true,
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              BrickStatusDot(color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'servers.active_spotlight_label'.tr().toUpperCase(),
                  style: TextStyle(
                    fontFamily: BrickTypography.primaryFontFamily,
                    fontSize: BrickTypography.sizeLabel,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.8,
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: BrickSpacing.xs),
          Row(
            children: [
              Text(leadingGlyph, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: BrickSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: BrickTypography.primaryFontFamily,
                        fontSize: BrickTypography.sizeLabel,
                        fontWeight: FontWeight.w400,
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionFeeds(
    BuildContext context,
    List<MapEntry<SubscriptionMetadata, List<SavedServerProfile>>>
    userSubscriptions,
  ) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final refreshingIds =
        ref.watch(serverManagementControllerProvider).value ?? const <String>{};

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in userSubscriptions)
          Padding(
            padding: const EdgeInsets.only(bottom: BrickSpacing.xxs),
            child: BrickGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.rss_feed_rounded,
                    size: 18,
                    color: colors.brandBrick,
                  ),
                  const SizedBox(width: BrickSpacing.xs),
                  Expanded(
                    child: Text(
                      entry.key.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: BrickSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(BrickRadius.xs),
                      border: Border.all(color: colors.glassBorder),
                    ),
                    child: Text(
                      '${entry.value.length}',
                      style: BrickTypography.monoLog(color: colors.textMuted),
                    ),
                  ),
                  if (refreshingIds.contains(entry.key.id))
                    const SizedBox(
                      width: BrickSpacing.minTouchTarget,
                      height: BrickSpacing.minTouchTarget,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    IconButton(
                      key: ValueKey<String>(
                        'subscription_refresh_${entry.key.id}',
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      color: colors.textMuted,
                      tooltip: 'servers.refresh_subscription'.tr(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: BrickSpacing.minTouchTarget,
                        minHeight: BrickSpacing.minTouchTarget,
                      ),
                      onPressed: () =>
                          _handleRefreshSubscription(context, entry.key),
                    ),
                  IconButton(
                    key: ValueKey<String>(
                      'subscription_delete_${entry.key.id}',
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    color: colors.textMuted,
                    tooltip: 'servers.delete_subscription'.tr(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: BrickSpacing.minTouchTarget,
                      minHeight: BrickSpacing.minTouchTarget,
                    ),
                    onPressed: () => _showConfirmDeleteDialog(
                      context,
                      title: 'servers.delete_subscription_title'.tr(),
                      message: 'servers.delete_subscription_message'.tr(),
                      onConfirm: () =>
                          _handleDeleteSubscription(context, entry.key.id),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNoMatchesState(BuildContext context) {
    final colors = context.brickColors;

    return Center(
      key: const ValueKey<String>('servers_no_matches_state'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: BrickSpacing.xl),
        child: BrickGlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 32, color: colors.textMuted),
              const SizedBox(height: BrickSpacing.sm),
              Text(
                'servers.no_matches_title'.tr(),
                style: TextStyle(
                  fontFamily: BrickTypography.primaryFontFamily,
                  fontSize: BrickTypography.sizeTitle,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: BrickSpacing.md),
              OutlinedButton(
                key: const ValueKey<String>('servers_clear_search_button'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, BrickSpacing.minTouchTarget),
                ),
                onPressed: _clearSearch,
                child: Text('servers.clear_search'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmartAutoCard(
    BuildContext context, {
    required int countryCount,
    required bool isSelected,
    required bool isConnected,
  }) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final accentColor = isSelected && isConnected
        ? colors.stateConnected
        : colors.brandBrick;

    return BrickGlassCard(
      key: const ValueKey<String>('server_location_auto'),
      padding: EdgeInsets.zero,
      isSelected: isSelected,
      elevated: isSelected,
      accentColor: accentColor,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey<String>('server_location_auto_tap'),
          borderRadius: BorderRadius.circular(BrickRadius.card),
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            unawaited(_handleSelectLocation(context, const SmartAutoTarget()));
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(BrickRadius.md),
                      border: Border.all(color: colors.glassBorder),
                    ),
                    child: const Center(
                      child: Text('⚡', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'servers.smart_auto_title'.tr(),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'servers.smart_auto_country_count'.tr(
                            namedArgs: {'count': '$countryCount'},
                          ),
                          style: TextStyle(
                            fontFamily: BrickTypography.primaryFontFamily,
                            fontSize: BrickTypography.sizeLabel,
                            fontWeight: FontWeight.w400,
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: BrickSpacing.xs),
                    BrickStatusDot(
                      key: const ValueKey<String>(
                        'server_location_auto_selected',
                      ),
                      color: accentColor,
                      size: 7,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCountryGroupCard(
    BuildContext context,
    CountryLocationGroup group, {
    required bool isSelected,
    required bool isConnected,
  }) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final accentColor = isSelected && isConnected
        ? colors.stateConnected
        : colors.brandBrick;

    final subtitle = group.totalServerCount == 1
        ? 'servers.server_count_one'.tr()
        : 'servers.server_count'.tr(
            namedArgs: {'count': '${group.totalServerCount}'},
          );

    return BrickGlassCard(
      key: ValueKey<String>('country_group_${group.countryCode}'),
      padding: EdgeInsets.zero,
      isSelected: isSelected,
      accentColor: accentColor,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey<String>('country_header_${group.countryCode}'),
          borderRadius: BorderRadius.circular(BrickRadius.card),
          onTap: () {
            unawaited(HapticFeedback.selectionClick());
            unawaited(
              _handleSelectLocation(context, CountryTarget(group.countryCode)),
            );
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(BrickRadius.md),
                      border: Border.all(color: colors.glassBorder),
                    ),
                    child: Center(
                      child: Text(
                        group.flagEmoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          group.countryCode ==
                                  ServerLocationParser.unknownCountryCode
                              ? 'servers.other_locations'.tr()
                              : group.countryName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: BrickTypography.primaryFontFamily,
                            fontSize: BrickTypography.sizeLabel,
                            fontWeight: FontWeight.w400,
                            color: colors.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: BrickSpacing.xs),
                    BrickStatusDot(
                      key: ValueKey<String>(
                        'country_selected_${group.countryCode}',
                      ),
                      color: accentColor,
                      size: 7,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Handles tapping `Smart Auto` or a country card.
  ///
  /// Selecting a location updates the local preference when disconnected or
  /// re-tapping the already-active target. Only when a live session is active
  /// (or reconnecting) and the tapped target differs does it hot-switch the
  /// tunnel via [ConnectionController.connectForTarget], persisting the
  /// preference only after [VpnCommandAccepted].
  Future<void> _handleSelectLocation(
    BuildContext context,
    ConnectionLocationTarget target,
  ) async {
    final controller = ref.read(connectionControllerProvider.notifier);
    if (controller.isBusy) {
      // A command is already dispatching; ignore overlapping taps before they
      // can race selectedLocationProvider or draw a RejectedBusy error.
      return;
    }

    final connState =
        ref.read(connectionStateProvider).value ??
        ref.read(initialConnectionStateProvider);
    final isReconnecting = ref.read(autoReconnectProvider).isReconnecting;
    final hasLiveSession =
        connState is Connected || connState is Connecting || isReconnecting;
    final activeTargetKey =
        controller.activeConnectingTargetKey ??
        ref.read(resolvedLocationTargetProvider).storageKey;
    final isLiveSwitch = hasLiveSession && target.storageKey != activeTargetKey;

    if (!isLiveSwitch) {
      await ref.read(selectedLocationProvider.notifier).selectLocation(target);
      return;
    }

    // Capture the notifier before the async switch so persistence still runs
    // safely if the user leaves this screen before `connectForTarget()`
    // resolves.
    final selectedLocationNotifier = ref.read(
      selectedLocationProvider.notifier,
    );
    final result = await controller.connectForTarget(target);
    if (result is VpnCommandAccepted) {
      await selectedLocationNotifier.selectLocation(target);
    } else if (context.mounted) {
      AppFeedback.showError(context, ErrorMapper.mapToUserMessage(result));
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _handleRefreshSubscription(
    BuildContext context,
    SubscriptionMetadata subscription,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .refreshSubscription(subscription);

    if (!context.mounted) return;

    switch (result) {
      case Ok(:final value):
        if (value.skippedCount > 0) {
          AppFeedback.showSuccess(
            context,
            'add_subscription.partial_success_message'.tr(
              namedArgs: {
                'count': value.importedCount.toString(),
                'skipped': value.skippedCount.toString(),
              },
            ),
          );
        } else {
          AppFeedback.showSuccess(
            context,
            'add_subscription.success_message'.tr(
              namedArgs: {'count': value.importedCount.toString()},
            ),
          );
        }
      case Err(:final error):
        AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _handleDeleteSubscription(
    BuildContext context,
    String subscriptionId,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .deleteSubscription(subscriptionId);

    if (!context.mounted) return;

    if (result case Err(:final error)) {
      AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _handleDeleteServer(
    BuildContext context,
    String serverId,
  ) async {
    final result = await ref
        .read(serverManagementControllerProvider.notifier)
        .deleteServer(serverId);

    if (!context.mounted) return;

    if (result case Err(:final error)) {
      AppFeedback.showError(context, ErrorMapper.mapToUserMessage(error));
    }
  }

  Future<void> _showConfirmDeleteDialog(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey<String>('confirm_delete_dialog'),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            key: const ValueKey<String>('confirm_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('servers.cancel'.tr()),
          ),
          FilledButton(
            key: const ValueKey<String>('confirm_delete_confirm'),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await onConfirm();
            },
            child: Text('servers.confirm_delete'.tr()),
          ),
        ],
      ),
    );
  }
}
