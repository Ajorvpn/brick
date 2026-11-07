// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/core/security/sensitive_field_cipher.dart';
import 'package:mobile/features/connection/domain/repositories/server_profile_repository.dart';
import 'package:mobile/features/servers/data/repositories/file_server_profile_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'server_profile_repository_provider.g.dart';

/// Binds the application's [ServerProfileRepository] contract to its
/// concrete persistent [FileServerProfileRepository] implementation.
///
/// In Phase 5 (P5-T1), this replaces the Phase 4 in-memory/SharedPreferences
/// scaffold with a versioned, atomic JSON-file persistent store.
///
/// In case of storage initialization failure (e.g., missing directory or
/// permission issue), it logs the error and gracefully degrades to an
/// in-memory fallback store in the system temp directory rather than
/// crashing the application.
@Riverpod(keepAlive: true)
Future<ServerProfileRepository> serverProfileRepository(Ref ref) async {
  final cipher = ref.watch(sensitiveFieldCipherProvider);
  try {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final tempDir = Directory.systemTemp.createTempSync('brick_test_');
      ref.onDispose(() {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } on Object catch (_) {}
      });
      final testFile = File('${tempDir.path}/server_profiles.json');
      final testRepo = FileServerProfileRepository(
        storageFile: testFile,
        cipher: cipher,
      );
      await testRepo.init();
      return testRepo;
    }

    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/server_profiles.json');
    final repo = FileServerProfileRepository(storageFile: file, cipher: cipher);
    await repo.init();
    return repo;
  } on Object catch (error, stackTrace) {
    AppLogger().e(
      'Failed to initialize FileServerProfileRepository; '
      'degrading to fallback store',
      error,
      stackTrace,
    );
    final tempDir = Directory.systemTemp.createTempSync('brick_fallback_');
    ref.onDispose(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } on Object catch (_) {}
    });
    final fallbackFile = File('${tempDir.path}/server_profiles.json');
    final fallbackRepo = FileServerProfileRepository(
      storageFile: fallbackFile,
      cipher: cipher,
    );
    await fallbackRepo.init();
    return fallbackRepo;
  }
}
