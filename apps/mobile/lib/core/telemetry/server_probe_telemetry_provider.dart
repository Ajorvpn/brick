// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/providers/app_preferences_provider.dart';
import 'package:mobile/core/telemetry/server_probe_reporter.dart';

/// Provides the anonymous server-probe reporter.
///
/// Deliberately a plain [Provider], not a `@Riverpod` annotation: no code
/// generation is needed, and nothing reads it during `AppBootstrap.init()`, so
/// cold start is untouched. The reporter is only constructed when a caller
/// first asks for it, and it reads the opt-in preference lazily on every flush.
final serverProbeReporterProvider = Provider<ServerProbeReporter>((ref) {
  final preferences = ref.watch(appPreferencesRepositoryProvider);
  return ServerProbeReporter(
    isEnabled: preferences.isAnonymousProbeReportingEnabled,
  );
});
