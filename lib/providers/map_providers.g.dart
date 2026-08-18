// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'map_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MapData)
final mapDataProvider = MapDataProvider._();

final class MapDataProvider extends $NotifierProvider<MapData, MapDataState> {
  MapDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapDataHash();

  @$internal
  @override
  MapData create() => MapData();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapDataState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapDataState>(value),
    );
  }
}

String _$mapDataHash() => r'c2f11c1abb0f59e9031dd1a24ac049dc47f710a1';

abstract class _$MapData extends $Notifier<MapDataState> {
  MapDataState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<MapDataState, MapDataState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MapDataState, MapDataState>,
              MapDataState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(MapSearchQuery)
final mapSearchQueryProvider = MapSearchQueryProvider._();

final class MapSearchQueryProvider
    extends $NotifierProvider<MapSearchQuery, String> {
  MapSearchQueryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapSearchQueryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapSearchQueryHash();

  @$internal
  @override
  MapSearchQuery create() => MapSearchQuery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$mapSearchQueryHash() => r'4c973355cb49f1b47c4dd823ff4fd3a27e26284c';

abstract class _$MapSearchQuery extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(MapFilter)
final mapFilterProvider = MapFilterProvider._();

final class MapFilterProvider
    extends $NotifierProvider<MapFilter, MapFilterState> {
  MapFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapFilterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapFilterHash();

  @$internal
  @override
  MapFilter create() => MapFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapFilterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapFilterState>(value),
    );
  }
}

String _$mapFilterHash() => r'1223cd3a818566654be21488d244643e76cef88d';

abstract class _$MapFilter extends $Notifier<MapFilterState> {
  MapFilterState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<MapFilterState, MapFilterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MapFilterState, MapFilterState>,
              MapFilterState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(filteredMapData)
final filteredMapDataProvider = FilteredMapDataProvider._();

final class FilteredMapDataProvider
    extends $FunctionalProvider<MapDataState, MapDataState, MapDataState>
    with $Provider<MapDataState> {
  FilteredMapDataProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'filteredMapDataProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$filteredMapDataHash();

  @$internal
  @override
  $ProviderElement<MapDataState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MapDataState create(Ref ref) {
    return filteredMapData(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapDataState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapDataState>(value),
    );
  }
}

String _$filteredMapDataHash() => r'ff9c7d673f01f1645d424472a55f3fdae7237438';

@ProviderFor(mapSections)
final mapSectionsProvider = MapSectionsProvider._();

final class MapSectionsProvider
    extends $FunctionalProvider<List<String>, List<String>, List<String>>
    with $Provider<List<String>> {
  MapSectionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mapSectionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mapSectionsHash();

  @$internal
  @override
  $ProviderElement<List<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<String> create(Ref ref) {
    return mapSections(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$mapSectionsHash() => r'305d6bd16a63d5e3427546f7bfc342c752fb960c';
