// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Callback type for injecting a mock scanner in hermetic widget tests.
typedef QrScannerBuilder = Widget Function(
  BuildContext context,
  Future<void> Function(String rawValue) onDetect,
);

/// Simplified camera permission status for QR scanning.
enum CameraPermissionStatus {
  /// Permission has been granted; the camera preview may be rendered.
  granted,

  /// Permission has been denied, but the user may be prompted again.
  denied,

  /// Permission has been permanently denied; the user must open system
  /// settings.
  permanentlyDenied,
}

/// Abstract contract for camera permission checks and requests.
///
/// Abstracted behind an interface to allow hermetic testing without native
/// platform channels or physical hardware.
abstract interface class CameraPermissionService {
  /// Checks current camera permission status.
  Future<CameraPermissionStatus> checkStatus();

  /// Requests camera permission from the platform.
  Future<CameraPermissionStatus> requestPermission();

  /// Opens system app settings so the user can grant permission manually.
  Future<bool> openSettings();
}

/// Production implementation of [CameraPermissionService] backed by
/// `permission_handler`.
class PermissionHandlerCameraPermissionService
    implements CameraPermissionService {
  /// Creates the default permission handler service.
  const PermissionHandlerCameraPermissionService();

  @override
  Future<CameraPermissionStatus> checkStatus() async {
    final status = await Permission.camera.status;
    return _mapStatus(status);
  }

  @override
  Future<CameraPermissionStatus> requestPermission() async {
    final status = await Permission.camera.request();
    return _mapStatus(status);
  }

  @override
  Future<bool> openSettings() {
    return openAppSettings();
  }

  CameraPermissionStatus _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return CameraPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }
}

/// Provider exposing the current [CameraPermissionService].
///
/// Can be overridden in automated widget tests using `overrideWithValue`.
final Provider<CameraPermissionService> cameraPermissionServiceProvider =
    Provider<CameraPermissionService>((ref) {
      return const PermissionHandlerCameraPermissionService();
    });

/// Optional provider to override the camera scanner widget across the app in
/// hermetic tests.
final Provider<QrScannerBuilder?> qrScannerBuilderProvider =
    Provider<QrScannerBuilder?>((ref) => null);
