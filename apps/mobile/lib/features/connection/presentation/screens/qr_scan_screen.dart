// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/presentation/utils/app_feedback.dart';
import 'package:mobile/core/presentation/utils/error_mapper.dart';
import 'package:mobile/features/connection/presentation/providers/add_server_controller.dart';
import 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_utils/shared_utils.dart' show Err, Ok;

export 'package:mobile/features/connection/presentation/providers/camera_permission_provider.dart'
    show CameraPermissionService, CameraPermissionStatus, QrScannerBuilder;

/// Screen for scanning a server configuration QR code via the camera.
///
/// Features:
/// 1. Android camera permission request flow handling `granted`, `denied`,
///    and `permanentlyDenied` states distinctly with localized messaging.
/// 2. Live camera scanner preview using `mobile_scanner` with an optional
///    [scannerBuilder] for hermetic widget testing.
/// 3. Single-scan lock (`_isProcessing`) guarding `onDetect` to prevent
///    duplicate frame processing and redundant server submissions.
/// 4. Direct save UX routing the scanned payload through
///    [AddServerController.submit] and popping to the server list on success.
class QrScanScreen extends ConsumerStatefulWidget {
  /// Creates the QR code scanner screen.
  const QrScanScreen({this.scannerBuilder, super.key});

  /// Optional builder to override the camera scanner widget in tests.
  final QrScannerBuilder? scannerBuilder;

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  late final AppLifecycleListener _lifecycleListener;
  CameraPermissionStatus? _permissionStatus;
  MobileScannerController? _scannerController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _onAppResumed);
    unawaited(_initPermission());
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(_scannerController?.dispose());
    super.dispose();
  }

  void _ensureScannerController() {
    final customScanner =
        widget.scannerBuilder ?? ref.read(qrScannerBuilderProvider);
    if (customScanner == null && _scannerController == null) {
      _scannerController = MobileScannerController();
    }
  }

  Future<void> _initPermission() async {
    final service = ref.read(cameraPermissionServiceProvider);
    var status = await service.checkStatus();
    if (status == CameraPermissionStatus.denied) {
      status = await service.requestPermission();
    }
    if (mounted) {
      setState(() => _permissionStatus = status);
    }
  }

  Future<void> _onAppResumed() async {
    final service = ref.read(cameraPermissionServiceProvider);
    final status = await service.checkStatus();
    if (mounted && status != _permissionStatus) {
      setState(() => _permissionStatus = status);
    }
  }

  Future<void> _requestPermission() async {
    final service = ref.read(cameraPermissionServiceProvider);
    final status = await service.requestPermission();
    if (mounted) {
      setState(() => _permissionStatus = status);
    }
  }

  Future<void> _openSettings() async {
    final service = ref.read(cameraPermissionServiceProvider);
    await service.openSettings();
  }

  Future<void> _handleDetect(String rawValue) async {
    final trimmed = rawValue.trim();
    if (_isProcessing || trimmed.isEmpty) return;
    setState(() => _isProcessing = true);
    unawaited(_scannerController?.pause());

    final result = await ref
        .read(addServerControllerProvider.notifier)
        .submit(trimmed);

    if (!mounted) return;

    switch (result) {
      case Ok():
        context.pop(true);
      case Err(:final error):
        final message = ErrorMapper.mapToUserMessage(error);
        AppFeedback.showError(context, message);
        unawaited(_scannerController?.start());
        setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('qr_scan.title'.tr())),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final status = _permissionStatus;
    if (status == null) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (status) {
      case CameraPermissionStatus.denied:
        return _buildDeniedState(context);
      case CameraPermissionStatus.permanentlyDenied:
        return _buildPermanentlyDeniedState(context);
      case CameraPermissionStatus.granted:
        return _buildScannerState(context);
    }
  }

  Widget _buildDeniedState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'qr_scan.permission_denied'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey<String>('qr_scan_request_permission_button'),
              onPressed: _requestPermission,
              child: Text('qr_scan.request_permission'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermanentlyDeniedState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.settings_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'qr_scan.permission_permanently_denied'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey<String>('qr_scan_open_settings_button'),
              onPressed: _openSettings,
              child: Text('qr_scan.open_settings'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerState(BuildContext context) {
    final customScanner =
        widget.scannerBuilder ?? ref.watch(qrScannerBuilderProvider);
    if (customScanner == null) {
      _ensureScannerController();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            'qr_scan.instruction'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRect(
                child: customScanner != null
                    ? customScanner(context, _handleDetect)
                    : MobileScanner(
                        controller: _scannerController,
                        onDetect: (capture) {
                          for (final barcode in capture.barcodes) {
                            final raw = barcode.rawValue;
                            if (raw != null && raw.trim().isNotEmpty) {
                              unawaited(_handleDetect(raw));
                              break;
                            }
                          }
                        },
                      ),
              ),
              if (_isProcessing)
                const ColoredBox(
                  color: Colors.black45,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            key: const ValueKey<String>('qr_scan_cancel_button'),
            onPressed: _isProcessing ? null : () => context.pop(),
            child: Text('qr_scan.cancel'.tr()),
          ),
        ),
      ],
    );
  }
}
