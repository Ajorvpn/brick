// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_preferences_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides the active [AppPreferencesRepository] instance.
///
/// Defaults to [FakeAppPreferencesRepository] so tests and detached widgets
/// function without platform channel setup, and overridden with
/// [SharedPreferencesAppPreferencesRepository] in production `main()`.

@ProviderFor(appPreferencesRepository)
final appPreferencesRepositoryProvider = AppPreferencesRepositoryProvider._();

/// Provides the active [AppPreferencesRepository] instance.
///
/// Defaults to [FakeAppPreferencesRepository] so tests and detached widgets
/// function without platform channel setup, and overridden with
/// [SharedPreferencesAppPreferencesRepository] in production `main()`.

final class AppPreferencesRepositoryProvider
    extends
        $FunctionalProvider<
          AppPreferencesRepository,
          AppPreferencesRepository,
          AppPreferencesRepository
        >
    with $Provider<AppPreferencesRepository> {
  /// Provides the active [AppPreferencesRepository] instance.
  ///
  /// Defaults to [FakeAppPreferencesRepository] so tests and detached widgets
  /// function without platform channel setup, and overridden with
  /// [SharedPreferencesAppPreferencesRepository] in production `main()`.
  AppPreferencesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appPreferencesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appPreferencesRepositoryHash();

  @$internal
  @override
  $ProviderElement<AppPreferencesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AppPreferencesRepository create(Ref ref) {
    return appPreferencesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppPreferencesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppPreferencesRepository>(value),
    );
  }
}

String _$appPreferencesRepositoryHash() =>
    r'b5ef46d52c3246dd3eeef3d546e2dae6377c5e3f';

/// Manages and persists the active [ThemeMode].

@ProviderFor(ThemeModeNotifier)
final themeModeProvider = ThemeModeNotifierProvider._();

/// Manages and persists the active [ThemeMode].
final class ThemeModeNotifierProvider
    extends $NotifierProvider<ThemeModeNotifier, ThemeMode> {
  /// Manages and persists the active [ThemeMode].
  ThemeModeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeNotifierHash();

  @$internal
  @override
  ThemeModeNotifier create() => ThemeModeNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeNotifierHash() => r'6608a6ff5bc437fbc64f3489e46a3aa6aaf48aac';

/// Manages and persists the active [ThemeMode].

abstract class _$ThemeModeNotifier extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode, ThemeMode>,
              ThemeMode,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Manages and persists the active [Locale].

@ProviderFor(LocaleNotifier)
final localeProvider = LocaleNotifierProvider._();

/// Manages and persists the active [Locale].
final class LocaleNotifierProvider
    extends $NotifierProvider<LocaleNotifier, Locale?> {
  /// Manages and persists the active [Locale].
  LocaleNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localeNotifierHash();

  @$internal
  @override
  LocaleNotifier create() => LocaleNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Locale? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Locale?>(value),
    );
  }
}

String _$localeNotifierHash() => r'814fe3ec5acfca6f79973daca0f9d69252a61e0a';

/// Manages and persists the active [Locale].

abstract class _$LocaleNotifier extends $Notifier<Locale?> {
  Locale? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Locale?, Locale?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Locale?, Locale?>,
              Locale?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
