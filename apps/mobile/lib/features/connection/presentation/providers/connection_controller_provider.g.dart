// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_controller_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Dispatches connect/disconnect intents to the engine.
///
/// This notifier holds **no** connection state of its own. It exists purely
/// to turn a button press into an engine command, and it deliberately does
/// not publish a "connecting"/"connected" value: the UI reads that from
/// `connectionStateProvider`, which is the authoritative stream
/// (`VpnEngine` Invariant 1). If this class also tracked state, the two
/// sources could disagree and the UI would have to pick a winner — the exact
/// design failure that produced the legacy prototype's false "Connected".
///
/// The in-flight guard is the one piece of state kept here, and it guards
/// against a *duplicate command*, not against describing the tunnel: it stops
/// a second tap while the first command is still being dispatched. It is not
/// rendered as connection state.

@ProviderFor(ConnectionController)
final connectionControllerProvider = ConnectionControllerProvider._();

/// Dispatches connect/disconnect intents to the engine.
///
/// This notifier holds **no** connection state of its own. It exists purely
/// to turn a button press into an engine command, and it deliberately does
/// not publish a "connecting"/"connected" value: the UI reads that from
/// `connectionStateProvider`, which is the authoritative stream
/// (`VpnEngine` Invariant 1). If this class also tracked state, the two
/// sources could disagree and the UI would have to pick a winner — the exact
/// design failure that produced the legacy prototype's false "Connected".
///
/// The in-flight guard is the one piece of state kept here, and it guards
/// against a *duplicate command*, not against describing the tunnel: it stops
/// a second tap while the first command is still being dispatched. It is not
/// rendered as connection state.
final class ConnectionControllerProvider
    extends $AsyncNotifierProvider<ConnectionController, void> {
  /// Dispatches connect/disconnect intents to the engine.
  ///
  /// This notifier holds **no** connection state of its own. It exists purely
  /// to turn a button press into an engine command, and it deliberately does
  /// not publish a "connecting"/"connected" value: the UI reads that from
  /// `connectionStateProvider`, which is the authoritative stream
  /// (`VpnEngine` Invariant 1). If this class also tracked state, the two
  /// sources could disagree and the UI would have to pick a winner — the exact
  /// design failure that produced the legacy prototype's false "Connected".
  ///
  /// The in-flight guard is the one piece of state kept here, and it guards
  /// against a *duplicate command*, not against describing the tunnel: it stops
  /// a second tap while the first command is still being dispatched. It is not
  /// rendered as connection state.
  ConnectionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionControllerHash();

  @$internal
  @override
  ConnectionController create() => ConnectionController();
}

String _$connectionControllerHash() =>
    r'd893a671ecd548e1bd4ff4b69dff0c7646bde712';

/// Dispatches connect/disconnect intents to the engine.
///
/// This notifier holds **no** connection state of its own. It exists purely
/// to turn a button press into an engine command, and it deliberately does
/// not publish a "connecting"/"connected" value: the UI reads that from
/// `connectionStateProvider`, which is the authoritative stream
/// (`VpnEngine` Invariant 1). If this class also tracked state, the two
/// sources could disagree and the UI would have to pick a winner — the exact
/// design failure that produced the legacy prototype's false "Connected".
///
/// The in-flight guard is the one piece of state kept here, and it guards
/// against a *duplicate command*, not against describing the tunnel: it stops
/// a second tap while the first command is still being dispatched. It is not
/// rendered as connection state.

abstract class _$ConnectionController extends $AsyncNotifier<void> {
  FutureOr<void> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, void>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
