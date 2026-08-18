import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/incident_models.dart';
import '../repositories/sync_repository.dart';
import '../providers/auth_provider.dart';
import '../services/incident_service.dart';

import '../services/user_service.dart';
import '../models/user_role.dart';

part 'incident_providers.g.dart';

enum IncidentQuickFilter { active, assignedToMe, all }
enum IncidentPeriod { allTime, today, thisWeek }

class IncidentFilterState {
  final IncidentQuickFilter quickFilter;
  final IncidentPeriod period;
  final String searchQuery;
  final bool? stoppedHotWater;
  final bool? stoppedHeating;

  IncidentFilterState({
    this.quickFilter = IncidentQuickFilter.active,
    this.period = IncidentPeriod.allTime,
    this.searchQuery = '',
    this.stoppedHotWater,
    this.stoppedHeating,
  });

  IncidentFilterState copyWith({
    IncidentQuickFilter? quickFilter,
    IncidentPeriod? period,
    String? searchQuery,
    bool? stoppedHotWater,
    bool? stoppedHeating,
  }) {
    return IncidentFilterState(
      quickFilter: quickFilter ?? this.quickFilter,
      period: period ?? this.period,
      searchQuery: searchQuery ?? this.searchQuery,
      stoppedHotWater: stoppedHotWater ?? this.stoppedHotWater,
      stoppedHeating: stoppedHeating ?? this.stoppedHeating,
    );
  }
}

@Riverpod(keepAlive: true)
class IncidentFilter extends _$IncidentFilter {
  @override
  IncidentFilterState build() => IncidentFilterState();

  void setQuickFilter(IncidentQuickFilter filter) => state = state.copyWith(quickFilter: filter);
  void setPeriod(IncidentPeriod period) => state = state.copyWith(period: period);
  void updateSearchQuery(String query) => state = state.copyWith(searchQuery: query);
  void setStoppedHotWater(bool? value) => state = state.copyWith(stoppedHotWater: value);
  void setStoppedHeating(bool? value) => state = state.copyWith(stoppedHeating: value);
}

final allIncidentsProvider = StreamProvider<List<IncidentResponse>>((ref) {
  // CRITICAL: Prevent instant destruction, but also throttle fast updates
  // to prevent UI cascades as requested (2 seconds rate limit).
  ref.keepAlive(); 
  final syncRepo = ref.watch(syncRepositoryProvider);
  return syncRepo.watchAllIncidents().transform(_ThrottleWithTrailingStreamTransformer(const Duration(seconds: 2)));
});

class _ThrottleWithTrailingStreamTransformer<T> extends StreamTransformerBase<T, T> {
  final Duration duration;
  _ThrottleWithTrailingStreamTransformer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    Timer? timer;
    StreamController<T>? controller;
    StreamSubscription<T>? subscription;
    T? pendingEvent;
    bool hasPending = false;

    void emitPending() {
      if (hasPending && controller != null && !controller.isClosed) {
        controller.add(pendingEvent as T);
        hasPending = false;
        pendingEvent = null;
        timer = Timer(duration, emitPending);
      } else {
        timer = null;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = stream.listen((event) {
          if (timer == null || !timer!.isActive) {
            controller?.add(event);
            timer = Timer(duration, emitPending);
          } else {
            hasPending = true;
            pendingEvent = event;
          }
        },
        onError: controller?.addError,
        onDone: () {
          if (hasPending && controller != null && !controller.isClosed) {
            controller.add(pendingEvent as T);
          }
          controller?.close();
        });
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        subscription?.cancel();
        timer?.cancel();
      },
    );

    return controller.stream;
  }
}

// Global Event Stream for explicit UI refreshes bypassing Riverpod caches
final globalRefreshEventControllerProvider = Provider<StreamController<void>>((ref) {
  final controller = StreamController<void>.broadcast();
  ref.onDispose(controller.close);
  return controller;
});

final globalRefreshEventProvider = StreamProvider<void>((ref) {
  return ref.watch(globalRefreshEventControllerProvider).stream;
});

class IncidentViewModel {
  final IncidentResponse raw;
  final String? boilerHouseDetail;
  final int totalResidents;
  final String? assigneeName;
  final String formattedTimestamp;
  final String? stoppedServicesText;
  final String? broadcastText;
  final String? boilersInfoText; // Информация о неработающих котлах (текст)
  /// Номера неработающих котлов для чипов в карточке
  final List<int> inactiveBoilerNumbers;
  /// Общее кол-во котлов в котельной для отрисовки чипов
  final int totalBoilersCount;
  final bool supplyFullyStopped;
  /// Локально вычисленный цвет инцидента ("normal" | "partial" | "full")
  final String resolvedColorStatus;

  IncidentViewModel({
    required this.raw,
    this.boilerHouseDetail,
    required this.totalResidents,
    this.assigneeName,
    required this.formattedTimestamp,
    this.stoppedServicesText,
    this.broadcastText,
    this.boilersInfoText,
    this.inactiveBoilerNumbers = const [],
    this.totalBoilersCount = 0,
    this.supplyFullyStopped = false,
    required this.resolvedColorStatus,
  });
}

final incidentViewModelsProvider = Provider<AsyncValue<List<IncidentViewModel>>>((ref) {
  final filteredAsync = ref.watch(filteredIncidentsProvider);
  final usersMap = ref.watch(usersMapProvider).value ?? {};

  return filteredAsync.whenData((incidents) {
    if (incidents.isEmpty) return [];
    return incidents.map((inc) {
      String? boilerHouseDetail;
      if (inc.boilerHouse != null) {
        final address = inc.boilerHouse!.address ?? 'Неизвестно';
        final manager = inc.boilerHouse!.siteManager ?? '?';
        final site = inc.boilerHouse!.siteNumber ?? '?';
        boilerHouseDetail = '📍 Котельная: $address\nНач: $manager | Участок: $site';
      }
      return _createViewModel(inc, boilerHouseDetail, usersMap);
    }).toList();
  });
});

IncidentViewModel _createViewModel(IncidentResponse inc, String? boilerHouseDetail, Map<int, dynamic> usersMap) {
  // 1. Total Residents
  int totalResidents = 0;
  if (inc.affectedHouseDetails != null) {
    for (final hd in inc.affectedHouseDetails!) {
      totalResidents += (hd.residentsCount ?? 0);
    }
  }

  // 2. Assignee Name
  String? assigneeName;
  if (inc.assignedTo != null) {
    final user = usersMap[inc.assignedTo];
    if (user != null) {
      assigneeName = user.formattedDisplayName;
    } else {
      assigneeName = 'Неизвестный (${inc.assignedTo})';
    }
  }

  // 3. Timestamp — используем startedAt для начала, createdAt как fallback
  final startRaw = inc.startedAt ?? inc.createdAt;
  final startDt = startRaw != null && startRaw.isNotEmpty ? DateTime.tryParse(startRaw)?.toLocal() : null;
  final startStr = startDt != null ? '${startDt.day.toString().padLeft(2, '0')}.${startDt.month.toString().padLeft(2, '0')}.${startDt.year} ${startDt.hour.toString().padLeft(2, '0')}:${startDt.minute.toString().padLeft(2, '0')}' : startRaw ?? '';
  
  String formattedTimestamp;
  if (inc.isScheduledLocal) {
    // Запланированный инцидент — показываем время старта
    if (inc.finishedAt != null) {
      final endDt = DateTime.tryParse(inc.finishedAt!)?.toLocal();
      final endStr = endDt != null ? '${endDt.day.toString().padLeft(2, '0')}.${endDt.month.toString().padLeft(2, '0')}.${endDt.year} ${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}' : '';
      formattedTimestamp = 'Старт: $startStr → $endStr';
    } else {
      formattedTimestamp = 'Старт: $startStr';
    }
  } else if (inc.status == IncidentStatus.resolved || inc.status == IncidentStatus.closed) {
    final endDtStr = inc.resolvedAt ?? inc.finishedAt ?? inc.updatedAt;
    final endDt = endDtStr != null && endDtStr.isNotEmpty ? DateTime.tryParse(endDtStr)?.toLocal() : null;
    final endStr = endDt != null ? '${endDt.day.toString().padLeft(2, '0')}.${endDt.month.toString().padLeft(2, '0')}.${endDt.year} ${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}' : endDtStr ?? '';
    formattedTimestamp = 'с $startStr до $endStr';
  } else if (inc.isOverdue) {
    // Просроченный — показываем что время завершения прошло
    final endDt = DateTime.tryParse(inc.finishedAt!)?.toLocal();
    final endStr = endDt != null ? '${endDt.day.toString().padLeft(2, '0')}.${endDt.month.toString().padLeft(2, '0')}.${endDt.year} ${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}' : '';
    formattedTimestamp = 'с $startStr (до $endStr)';
  } else if (inc.finishedAt != null) {
    // Активный с запланированным окончанием
    final endDt = DateTime.tryParse(inc.finishedAt!)?.toLocal();
    final endStr = endDt != null ? '${endDt.day.toString().padLeft(2, '0')}.${endDt.month.toString().padLeft(2, '0')}.${endDt.year} ${endDt.hour.toString().padLeft(2, '0')}:${endDt.minute.toString().padLeft(2, '0')}' : '';
    formattedTimestamp = 'с $startStr до $endStr';
  } else {
    formattedTimestamp = 'с $startStr по наст. время';
  }

  // 4. Stopped Services
  List<String> stopped = [];
  if (inc.resourceHotWaterStopped == 1) stopped.add('ГВС');
  if (inc.resourceHeatingStopped == 1) stopped.add('Отопление');
  final stoppedServicesText = stopped.isEmpty ? null : stopped.join(', ');

  // 5. Broadcast Text — показываем конкретику, а не enum-имя
  String? broadcastText;
  final config = inc.notificationConfig;
  if (config != null) {
    if (config.type == AudienceType.broadcast) {
      broadcastText = 'Всем пользователям';
    } else if (config.type == AudienceType.roleBased) {
      final roleIds = config.roleIds ?? [];
      if (roleIds.isEmpty) {
        broadcastText = '👥 По ролям';
      } else if (roleIds.length == 1) {
        final role = UserRole.fromAnyString(roleIds.first);
        broadcastText = '👥 Роль: ${role.title}';
      } else {
        final titles = roleIds.map((r) => UserRole.fromAnyString(r).title).join(', ');
        broadcastText = '👥 Роли: $titles';
      }
    } else if (config.type == AudienceType.userBased) {
      final ids = config.userIds ?? [];
      if (ids.isEmpty) {
        broadcastText = '👤 По пользователям';
      } else {
        final names = ids.map((id) {
          final user = usersMap[id];
          return user?.formattedDisplayName ?? 'ID $id';
        }).toList();
        if (names.length == 1) {
          broadcastText = '👤 ${names.first}';
        } else {
          broadcastText = '👤 ${names.join(', ')}';
        }
      }
    }
  }

  // 6. Информация о неработающих котлах
  String? boilersInfoText;
  if (inc.supplyFullyStopped == true) {
    boilersInfoText = '🔴 Подача полностью прекращена';
  } else if (inc.inactiveBoilerNumbers != null && inc.inactiveBoilerNumbers!.isNotEmpty) {
    final inactive = List<int>.from(inc.inactiveBoilerNumbers!)..sort();
    final numsText = inactive.map((n) => '№$n').join(', ');
    final total = inc.boilerHouse?.totalBoilersCount;
    if (total != null && total > 0) {
      boilersInfoText = '⚠️ Котлы $numsText из $total — не работают';
    } else {
      boilersInfoText = '⚠️ Котлы $numsText — не работают';
    }
  }

  // 7. Локально вычисленный colorStatus — идентично map_providers._computeIncidentColorStatus
  final resolvedColorStatus = _computeColorStatus(inc);

  // 8. Номера неработающих котлов (отсортированные)
  final inactiveBoilerNums = inc.inactiveBoilerNumbers != null
      ? (List<int>.from(inc.inactiveBoilerNumbers!)..sort())
      : const <int>[];

  return IncidentViewModel(
    raw: inc,
    boilerHouseDetail: boilerHouseDetail,
    totalResidents: stoppedServicesText != null ? totalResidents : 0,
    assigneeName: assigneeName,
    formattedTimestamp: formattedTimestamp,
    stoppedServicesText: stoppedServicesText,
    broadcastText: broadcastText,
    boilersInfoText: boilersInfoText,
    inactiveBoilerNumbers: inactiveBoilerNums,
    totalBoilersCount: inc.boilerHouse?.totalBoilersCount ?? 0,
    supplyFullyStopped: inc.supplyFullyStopped ?? false,
    resolvedColorStatus: resolvedColorStatus,
  );
}

/// Та же логика что в map_providers._computeIncidentColorStatus
/// Гарантирует правильный цвет в карточке даже если сервер не прислал colorStatus
String _computeColorStatus(IncidentResponse inc) {
  // 1. supplyFullyStopped — наивысший приоритет
  if (inc.supplyFullyStopped == true) return 'full';

  final hotWaterStopped = inc.resourceHotWaterStopped == 1;
  final heatingStopped = inc.resourceHeatingStopped == 1;

  // 2. ОБА ресурса остановлены → full
  if (hotWaterStopped && heatingStopped) return 'full';

  // 3. Сервер посчитал full — значит все котлы нерабочие
  if (inc.colorStatus == 'full') return 'full';

  // 4. Сервер посчитал partial — часть котлов нерабочая
  if (inc.colorStatus == 'partial') return 'partial';

  // 5. Есть неработающие котлы → partial
  if (inc.inactiveBoilerNumbers != null && inc.inactiveBoilerNumbers!.isNotEmpty) return 'partial';

  // 6. ОДИН ресурс остановлен → partial
  if (hotWaterStopped || heatingStopped) return 'partial';

  // 7. Нет деталей — full (полное отключение по умолчанию для активных инцидентов)
  return 'full';
}

final filteredIncidentsProvider = Provider<AsyncValue<List<IncidentResponse>>>((ref) {
  final allAsync = ref.watch(allIncidentsProvider);
  final filter = ref.watch(incidentFilterProvider);
  final authState = ref.watch(authProvider);
  final currentUserId = int.tryParse(authState.user?.id ?? '');
  
  return allAsync.whenData((incidents) {
    return incidents.where((inc) {
      // 1. Search Query
      if (filter.searchQuery.isNotEmpty) {
        final query = filter.searchQuery.toLowerCase();
        final matches = (inc.title?.toLowerCase().contains(query) ?? false) ||
            (inc.description?.toLowerCase().contains(query) ?? false) ||
            (inc.boilerHouse?.address.toLowerCase().contains(query) ?? false);
        if (!matches) return false;
      }

      // 2. Quick Filter
      if (filter.quickFilter == IncidentQuickFilter.active) {
        if (inc.status?.name.toLowerCase().contains('resolved') ?? false) return false;
        if (inc.status?.name.toLowerCase().contains('closed') ?? false) return false;
      } else if (filter.quickFilter == IncidentQuickFilter.assignedToMe) {
        if (currentUserId != null && inc.assignedTo != currentUserId) return false;
      }

      // 3. Period (Simplified)
      if (filter.period != IncidentPeriod.allTime) {
        final now = DateTime.now();
        final incidentDate = inc.createdAt != null && inc.createdAt!.isNotEmpty ? DateTime.tryParse(inc.createdAt!)?.toLocal() : null;
        if (incidentDate != null) {
          if (filter.period == IncidentPeriod.today) {
            final startOfDay = DateTime(now.year, now.month, now.day);
            if (incidentDate.isBefore(startOfDay)) return false;
          } else if (filter.period == IncidentPeriod.thisWeek) {
            final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
            final startOfWeekDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
            if (incidentDate.isBefore(startOfWeekDate)) return false;
          }
        }
      }

      // 4. Resources
      if (filter.stoppedHotWater != null) {
        final isStopped = inc.resourceHotWaterStopped == 1;
        if (isStopped != filter.stoppedHotWater) return false;
      }
      if (filter.stoppedHeating != null) {
        final isStopped = inc.resourceHeatingStopped == 1;
        if (isStopped != filter.stoppedHeating) return false;
      }

      return true;
    }).toList();
  });
});



@riverpod
Stream<IncidentResponse?> singleIncident(Ref ref, int id) {
  final syncRepo = ref.watch(syncRepositoryProvider);
  final incidentService = ref.watch(incidentServiceProvider);

  // КРИТИЧНО: Фоновый fetch с сервера для актуализации данных.
  // autoDispose (не keepAlive) — провайдер пересоздаётся при каждом
  // открытии экрана деталей, гарантируя свежий fetch с сервера.
  // Это решает проблему когда фото загружено с другого устройства
  // пока это устройство было офлайн.
  Future.microtask(() async {
    try {
      await incidentService.getIncident(id);
    } catch (_) {
      // Не критично — локальные данные останутся
    }
  });

  // Подписка на globalRefreshEvent — при получении WebSocket-обновления
  // (например, фото загружено другим устройством в реальном времени)
  // перезагружаем данные инцидента с сервера.
  ref.listen(globalRefreshEventProvider, (prev, next) {
    Future.microtask(() async {
      try {
        await incidentService.getIncident(id);
      } catch (_) {}
    });
  });

  return syncRepo.watchIncidentById(id);
}
