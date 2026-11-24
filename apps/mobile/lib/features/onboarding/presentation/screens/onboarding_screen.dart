// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:ui_theme/ui_theme.dart';

/// A single first-run onboarding step (icon, accent and localized copy keys).
class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.accent,
    required this.titleKey,
    required this.bodyKey,
    required this.point1Key,
    required this.point2Key,
  });

  final IconData icon;
  final Color accent;
  final String titleKey;
  final String bodyKey;
  final String point1Key;
  final String point2Key;
}

/// First-run onboarding: three calm "Obsidian Glass & Brick Ember" steps that
/// explain privacy, server control, and the Android VPN permission prompt.
///
/// Completion is persisted through [onboardingCompletedProvider]; the router
/// gates the app on that same preference, so this screen is shown exactly once
/// per install (unless the preference is cleared).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _pageCount = 3;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isCompleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Persists completion, then leaves onboarding. Guarded so a double tap can
  /// never write twice or navigate twice.
  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _isCompleting = true);
    try {
      await ref.read(onboardingCompletedProvider.notifier).markCompleted();
    } catch (_) {
      // Never leave the controls permanently locked if storage fails.
      if (mounted) setState(() => _isCompleting = false);
      rethrow;
    }
    if (!mounted) return;
    context.go('/');
  }

  void _goToPage(int index) {
    // WCAG 2.1 SC 2.3.3: a horizontal page slide is motion the user explicitly
    // asked not to see when Android's "Remove animations" setting is on.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(index);
      return;
    }
    _pageController.animateToPage(
      index,
      duration: BrickMotion.standard,
      curve: BrickMotion.curveStandard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.brickColors;
    final isDark = theme.brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final steps = <_OnboardingStep>[
      _OnboardingStep(
        icon: Icons.shield_outlined,
        accent: colors.brandBrick,
        titleKey: 'onboarding.step1_title',
        bodyKey: 'onboarding.step1_body',
        point1Key: 'onboarding.step1_point1',
        point2Key: 'onboarding.step1_point2',
      ),
      _OnboardingStep(
        icon: Icons.public_rounded,
        accent: colors.brandBrick,
        titleKey: 'onboarding.step2_title',
        bodyKey: 'onboarding.step2_body',
        point1Key: 'onboarding.step2_point1',
        point2Key: 'onboarding.step2_point2',
      ),
      _OnboardingStep(
        icon: Icons.vpn_key_outlined,
        accent: colors.stateConnected,
        titleKey: 'onboarding.step3_title',
        bodyKey: 'onboarding.step3_body',
        point1Key: 'onboarding.step3_point1',
        point2Key: 'onboarding.step3_point2',
      ),
    ];

    final isLastPage = _currentPage == _pageCount - 1;

    return Scaffold(
      key: const ValueKey<String>('onboarding_screen'),
      body: Stack(
        children: [
          // Ambient radial glow. Gradient only — never a color plus gradient in
          // one BoxDecoration.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: const ValueKey<String>('onboarding_atmosphere_glow'),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.45),
                    radius: 0.9,
                    colors: <Color>[
                      colors.brandBrick.withValues(alpha: isDark ? 0.13 : 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: BrickSpacing.maxReadableWidth,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BrickSpacing.md,
                        BrickSpacing.md,
                        BrickSpacing.md,
                        BrickSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          const BrickEmblemPlaceholder(size: 26),
                          const SizedBox(width: BrickSpacing.xs),
                          Expanded(
                            child: Text(
                              'app_title'.tr(),
                              style: theme.textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            key: const ValueKey<String>(
                              'onboarding_skip_button',
                            ),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                BrickSpacing.minTouchTarget,
                                BrickSpacing.minTouchTarget,
                              ),
                            ),
                            onPressed: _isCompleting
                                ? null
                                : _completeOnboarding,
                            child: Text('onboarding.skip'.tr()),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pageCount,
                        onPageChanged: (index) {
                          setState(() => _currentPage = index);
                        },
                        itemBuilder: (context, index) {
                          return _stepPage(
                            steps[index],
                            index: index,
                            theme: theme,
                            colors: colors,
                            isDark: isDark,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BrickSpacing.md,
                        BrickSpacing.sm,
                        BrickSpacing.md,
                        BrickSpacing.lg,
                      ),
                      child: Column(
                        children: [
                          // Purely decorative progress dots: the mono
                          // "Step {current} of {total}" label already speaks
                          // the same information, so TalkBack must not read an
                          // additional, redundant node here.
                          ExcludeSemantics(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                for (var i = 0; i < _pageCount; i++) ...[
                                  if (i > 0)
                                    const SizedBox(width: BrickSpacing.xs),
                                  AnimatedContainer(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : BrickMotion.standard,
                                    curve: BrickMotion.curveStandard,
                                    width: i == _currentPage ? 24 : 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: i == _currentPage
                                          ? colors.brandBrick
                                          : colors.glassBorder,
                                      borderRadius: BorderRadius.circular(
                                        BrickRadius.pill,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: BrickSpacing.md),
                          Row(
                            children: [
                              if (_currentPage > 0) ...[
                                OutlinedButton(
                                  key: const ValueKey<String>(
                                    'onboarding_back_button',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(
                                      BrickSpacing.minTouchTarget,
                                      BrickSpacing.minTouchTarget,
                                    ),
                                  ),
                                  onPressed: _isCompleting
                                      ? null
                                      : () => _goToPage(_currentPage - 1),
                                  child: Text('onboarding.back'.tr()),
                                ),
                                const SizedBox(width: BrickSpacing.sm),
                              ],
                              Expanded(
                                child: FilledButton(
                                  key: ValueKey<String>(
                                    isLastPage
                                        ? 'onboarding_finish_button'
                                        : 'onboarding_next_button',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colors.brandBrick,
                                    foregroundColor: colors.onAccent,
                                    minimumSize: const Size.fromHeight(
                                      BrickSpacing.minTouchTarget,
                                    ),
                                  ),
                                  onPressed: _isCompleting
                                      ? null
                                      : () {
                                          if (isLastPage) {
                                            unawaited(_completeOnboarding());
                                          } else {
                                            _goToPage(_currentPage + 1);
                                          }
                                        },
                                  child: Text(
                                    isLastPage
                                        ? 'onboarding.get_started'.tr()
                                        : 'onboarding.next'.tr(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepPage(
    _OnboardingStep step, {
    required int index,
    required ThemeData theme,
    required BrickSemanticColors colors,
    required bool isDark,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: BrickSpacing.md,
          vertical: BrickSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Decorative step squircle: the step title and body below already
            // carry the meaning, so the icon is excluded from the semantics
            // tree rather than announced as an unlabelled graphic.
            ExcludeSemantics(
              child: Center(
                child: Container(
                  width: BrickSpacing.hero,
                  height: BrickSpacing.hero,
                  decoration: BoxDecoration(
                    color: step.accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    borderRadius: BorderRadius.circular(BrickRadius.sheet),
                    border: Border.all(
                      color: step.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Center(
                    child: Icon(step.icon, size: 36, color: step.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(height: BrickSpacing.lg),
            Text(
              'onboarding.step_indicator'.tr(
                namedArgs: <String, String>{
                  'current': '${index + 1}',
                  'total': '$_pageCount',
                },
              ),
              textAlign: TextAlign.center,
              style: BrickTypography.monoLog(color: colors.textMuted),
            ),
            const SizedBox(height: BrickSpacing.xs),
            Text(
              step.titleKey.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: BrickTypography.sizeDisplay,
                fontWeight: FontWeight.w700,
                height: 1.15,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: BrickSpacing.sm),
            Text(
              step.bodyKey.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: BrickSpacing.lg),
            BrickGlassCard(
              elevated: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _trustRow(step.point1Key, colors, step.accent),
                  const SizedBox(height: BrickSpacing.xs),
                  _trustRow(step.point2Key, colors, step.accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trustRow(String key, BrickSemanticColors colors, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline_rounded, size: 18, color: accent),
        const SizedBox(width: BrickSpacing.xs),
        Expanded(
          child: Text(
            key.tr(),
            style: TextStyle(
              fontSize: BrickTypography.sizeBody,
              fontWeight: FontWeight.w400,
              height: 1.35,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
