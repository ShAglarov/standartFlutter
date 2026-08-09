// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'incident_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IncidentFilter)
final incidentFilterProvider = IncidentFilterProvider._();

final class IncidentFilterProvider
    extends $NotifierProvider<IncidentFilter, IncidentFilterState> {
  IncidentFilterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'incidentFilterProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$incidentFilterHash();

  @$internal
  @override
  IncidentFilter create() => IncidentFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(IncidentFilterState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<IncidentFilterState>(value),
    );
  }
}

String _$incidentFilterHash() => r'3851b294396331da8215a55ad0c5d2c430cb43bf';

abstract class _$IncidentFilter extends $Notifier<IncidentFilterState> {
  IncidentFilterState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<IncidentFilterState, IncidentFilterState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<IncidentFilterState, IncidentFilterState>,
              IncidentFilterState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(singleIncident)
final singleIncidentProvider = SingleIncidentFamily._();

final class SingleIncidentProvider
    extends
        $FunctionalProvider<
          AsyncValue<IncidentResponse?>,
          IncidentResponse?,
          Stream<IncidentResponse?>
        >
    with
        $FutureModifier<IncidentResponse?>,
        $StreamProvider<IncidentResponse?> {
  SingleIncidentProvider._({
    required SingleIncidentFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'singleIncidentProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$singleIncidentHash();

  @override
  String toString() {
    return r'singleIncidentProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<IncidentResponse?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<IncidentResponse?> create(Ref ref) {
    final argument = this.argument as int;
    return singleIncident(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SingleIncidentProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$singleIncidentHash() => r'2bb4dec638f49ab8f2ee042403456952917b375c';

final class SingleIncidentFamily extends $Family
    with $FunctionalFamilyOverride<Stream<IncidentResponse?>, int> {
  SingleIncidentFamily._()
    : super(
        retry: null,
        name: r'singleIncidentProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  SingleIncidentProvider call(int id) =>
      SingleIncidentProvider._(argument: id, from: this);

  @override
  String toString() => r'singleIncidentProvider';
}
