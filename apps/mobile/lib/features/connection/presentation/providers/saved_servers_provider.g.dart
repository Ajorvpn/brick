// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_servers_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The user's saved servers, loaded from the repository on startup.
///
/// An `AsyncNotifier` so the three states a storage read can be in —
/// loading, failed, loaded — are represented rather than being faked with an
/// empty list (`CODING_STANDARDS.md` Section 4).
///
/// Depends only on the `ServerProfileRepository` **interface** from
/// `domain/`; it never imports `data/` (see `features/README.md` Section 3).
///
/// `keepAlive: true` because this is app-scoped shared state, not per-screen
/// state: both `HomeScreen` and `AddServerScreen` use it, and `AddServerScreen`
/// mutates it while `HomeScreen` observes it. A bare `@riverpod` would
/// auto-dispose the notifier the moment the last watcher navigated away,
/// disposing the `Ref` out from under an in-flight `addServer()`.

@ProviderFor(SavedServers)
final savedServersProvider = SavedServersProvider._();

/// The user's saved servers, loaded from the repository on startup.
///
/// An `AsyncNotifier` so the three states a storage read can be in —
/// loading, failed, loaded — are represented rather than being faked with an
/// empty list (`CODING_STANDARDS.md` Section 4).
///
/// Depends only on the `ServerProfileRepository` **interface** from
/// `domain/`; it never imports `data/` (see `features/README.md` Section 3).
///
/// `keepAlive: true` because this is app-scoped shared state, not per-screen
/// state: both `HomeScreen` and `AddServerScreen` use it, and `AddServerScreen`
/// mutates it while `HomeScreen` observes it. A bare `@riverpod` would
/// auto-dispose the notifier the moment the last watcher navigated away,
/// disposing the `Ref` out from under an in-flight `addServer()`.
final class SavedServersProvider
    extends $AsyncNotifierProvider<SavedServers, List<SavedServer>> {
  /// The user's saved servers, loaded from the repository on startup.
  ///
  /// An `AsyncNotifier` so the three states a storage read can be in —
  /// loading, failed, loaded — are represented rather than being faked with an
  /// empty list (`CODING_STANDARDS.md` Section 4).
  ///
  /// Depends only on the `ServerProfileRepository` **interface** from
  /// `domain/`; it never imports `data/` (see `features/README.md` Section 3).
  ///
  /// `keepAlive: true` because this is app-scoped shared state, not per-screen
  /// state: both `HomeScreen` and `AddServerScreen` use it, and `AddServerScreen`
  /// mutates it while `HomeScreen` observes it. A bare `@riverpod` would
  /// auto-dispose the notifier the moment the last watcher navigated away,
  /// disposing the `Ref` out from under an in-flight `addServer()`.
  SavedServersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'savedServersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$savedServersHash();

  @$internal
  @override
  SavedServers create() => SavedServers();
}

String _$savedServersHash() => r'7856075a9ed2aa37069431ebdbadb39dafed9eb9';

/// The user's saved servers, loaded from the repository on startup.
///
/// An `AsyncNotifier` so the three states a storage read can be in —
/// loading, failed, loaded — are represented rather than being faked with an
/// empty list (`CODING_STANDARDS.md` Section 4).
///
/// Depends only on the `ServerProfileRepository` **interface** from
/// `domain/`; it never imports `data/` (see `features/README.md` Section 3).
///
/// `keepAlive: true` because this is app-scoped shared state, not per-screen
/// state: both `HomeScreen` and `AddServerScreen` use it, and `AddServerScreen`
/// mutates it while `HomeScreen` observes it. A bare `@riverpod` would
/// auto-dispose the notifier the moment the last watcher navigated away,
/// disposing the `Ref` out from under an in-flight `addServer()`.

abstract class _$SavedServers extends $AsyncNotifier<List<SavedServer>> {
  FutureOr<List<SavedServer>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<SavedServer>>, List<SavedServer>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<SavedServer>>, List<SavedServer>>,
              AsyncValue<List<SavedServer>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
