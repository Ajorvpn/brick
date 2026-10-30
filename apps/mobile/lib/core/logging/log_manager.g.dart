// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_manager.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    using a bounded [ListQueue<String>].
/// 2. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with [FileMode.write], which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 3. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.

@ProviderFor(LogManager)
final logManagerProvider = LogManagerProvider._();

/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    using a bounded [ListQueue<String>].
/// 2. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with [FileMode.write], which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 3. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.
final class LogManagerProvider
    extends $NotifierProvider<LogManager, ListQueue<String>> {
  /// Manages live streaming logs from the native VPN engine.
  ///
  /// CRITICAL ARCHITECTURAL CONSTRAINTS:
  /// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
  ///    using a bounded [ListQueue<String>].
  /// 2. Asynchronous File Streaming: Streams all lines to a temporary file
  ///    `brick_vpn_live.log` using [IOSink] with [FileMode.write], which
  ///    automatically clears past session logs on initialization to protect
  ///    privacy.
  /// 3. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.
  LogManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'logManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$logManagerHash();

  @$internal
  @override
  LogManager create() => LogManager();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ListQueue<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ListQueue<String>>(value),
    );
  }
}

String _$logManagerHash() => r'eedfd8f2f245b8e2cff98f69eb140fb73672d38d';

/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    using a bounded [ListQueue<String>].
/// 2. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with [FileMode.write], which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 3. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.

abstract class _$LogManager extends $Notifier<ListQueue<String>> {
  ListQueue<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ListQueue<String>, ListQueue<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ListQueue<String>, ListQueue<String>>,
              ListQueue<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
