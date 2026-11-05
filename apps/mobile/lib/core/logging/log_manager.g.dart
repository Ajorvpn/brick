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
///    for string consumers and structured entries in a bounded [LogBuffer].
/// 2. Burst Coalescing: Coalesces high-volume bursts per microtask so rapid
///    log streams do not flood the UI thread with hundreds of rebuilds.
/// 3. Stream Resilience: Catches and absorbs errors from engine logEvents
///    gracefully without disrupting the VPN connection or UI.
/// 4. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with default write mode, which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 5. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.

@ProviderFor(LogManager)
final logManagerProvider = LogManagerProvider._();

/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    for string consumers and structured entries in a bounded [LogBuffer].
/// 2. Burst Coalescing: Coalesces high-volume bursts per microtask so rapid
///    log streams do not flood the UI thread with hundreds of rebuilds.
/// 3. Stream Resilience: Catches and absorbs errors from engine logEvents
///    gracefully without disrupting the VPN connection or UI.
/// 4. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with default write mode, which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 5. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.
final class LogManagerProvider
    extends $NotifierProvider<LogManager, ListQueue<String>> {
  /// Manages live streaming logs from the native VPN engine.
  ///
  /// CRITICAL ARCHITECTURAL CONSTRAINTS:
  /// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
  ///    for string consumers and structured entries in a bounded [LogBuffer].
  /// 2. Burst Coalescing: Coalesces high-volume bursts per microtask so rapid
  ///    log streams do not flood the UI thread with hundreds of rebuilds.
  /// 3. Stream Resilience: Catches and absorbs errors from engine logEvents
  ///    gracefully without disrupting the VPN connection or UI.
  /// 4. Asynchronous File Streaming: Streams all lines to a temporary file
  ///    `brick_vpn_live.log` using [IOSink] with default write mode, which
  ///    automatically clears past session logs on initialization to protect
  ///    privacy.
  /// 5. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.
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

String _$logManagerHash() => r'4b6e05ce59cef8ebf937df9391031ce07e539ef1';

/// Manages live streaming logs from the native VPN engine.
///
/// CRITICAL ARCHITECTURAL CONSTRAINTS:
/// 1. RAM Protection: Keeps at most [maxBufferSize] (300) lines in memory
///    for string consumers and structured entries in a bounded [LogBuffer].
/// 2. Burst Coalescing: Coalesces high-volume bursts per microtask so rapid
///    log streams do not flood the UI thread with hundreds of rebuilds.
/// 3. Stream Resilience: Catches and absorbs errors from engine logEvents
///    gracefully without disrupting the VPN connection or UI.
/// 4. Asynchronous File Streaming: Streams all lines to a temporary file
///    `brick_vpn_live.log` using [IOSink] with default write mode, which
///    automatically clears past session logs on initialization to protect
///    privacy.
/// 5. Resource Cleanup: Closes [IOSink] and cancels subscription on disposal.

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

/// Structured log entries from the native VPN engine's bounded buffer.

@ProviderFor(structuredLogEntries)
final structuredLogEntriesProvider = StructuredLogEntriesProvider._();

/// Structured log entries from the native VPN engine's bounded buffer.

final class StructuredLogEntriesProvider
    extends $FunctionalProvider<List<LogEntry>, List<LogEntry>, List<LogEntry>>
    with $Provider<List<LogEntry>> {
  /// Structured log entries from the native VPN engine's bounded buffer.
  StructuredLogEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'structuredLogEntriesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$structuredLogEntriesHash();

  @$internal
  @override
  $ProviderElement<List<LogEntry>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<LogEntry> create(Ref ref) {
    return structuredLogEntries(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LogEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LogEntry>>(value),
    );
  }
}

String _$structuredLogEntriesHash() =>
    r'9c8f0e8023444a176e20d79fb64e50a90b0b54fd';
