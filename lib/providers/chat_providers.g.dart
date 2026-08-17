// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(IncidentChat)
final incidentChatProvider = IncidentChatFamily._();

final class IncidentChatProvider
    extends $StreamNotifierProvider<IncidentChat, List<IncidentComment>> {
  IncidentChatProvider._({
    required IncidentChatFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'incidentChatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$incidentChatHash();

  @override
  String toString() {
    return r'incidentChatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  IncidentChat create() => IncidentChat();

  @override
  bool operator ==(Object other) {
    return other is IncidentChatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$incidentChatHash() => r'e90979c39050a22f8099c16711f781c7f609a298';

final class IncidentChatFamily extends $Family
    with
        $ClassFamilyOverride<
          IncidentChat,
          AsyncValue<List<IncidentComment>>,
          List<IncidentComment>,
          Stream<List<IncidentComment>>,
          int
        > {
  IncidentChatFamily._()
    : super(
        retry: null,
        name: r'incidentChatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  IncidentChatProvider call(int incidentId) =>
      IncidentChatProvider._(argument: incidentId, from: this);

  @override
  String toString() => r'incidentChatProvider';
}

abstract class _$IncidentChat extends $StreamNotifier<List<IncidentComment>> {
  late final _$args = ref.$arg as int;
  int get incidentId => _$args;

  Stream<List<IncidentComment>> build(int incidentId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<IncidentComment>>, List<IncidentComment>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<IncidentComment>>,
                List<IncidentComment>
              >,
              AsyncValue<List<IncidentComment>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
