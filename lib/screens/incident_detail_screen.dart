import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../providers/incident_providers.dart';
import '../models/incident_models.dart';
import '../models/permission_key.dart';
import '../services/incident_service.dart';
import '../services/permission_service.dart';
import '../repositories/sync_repository.dart';
import '../widgets/incident_detail/incident_header_card.dart';
import '../widgets/incident_detail/incident_description_card.dart';
import '../widgets/incident_detail/incident_chat_card.dart';
import '../widgets/incident_detail/incident_activity_card.dart';
import '../widgets/incident_detail/incident_photos_card.dart';
import '../providers/offline_edit_permission.dart';
import '../services/chat_read_service.dart';
import 'incident_form_screen.dart';

class IncidentDetailScreen extends ConsumerStatefulWidget {
  final int incidentId;

  const IncidentDetailScreen({super.key, required this.incidentId});

  @override
  ConsumerState<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends ConsumerState<IncidentDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Помечаем чат как прочитанный когда пользователь открыл детали инцидента
    Future.microtask(() {
      ref.read(unreadCountsProvider.notifier).markAsRead(widget.incidentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final incidentAsync = ref.watch(singleIncidentProvider(widget.incidentId));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('ИНЦИДЕНТ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: incidentAsync.when(
        data: (incident) => RefreshIndicator(
          onRefresh: () async {
            // Перезагрузить данные инцидента с сервера
            try {
              final service = ref.read(incidentServiceProvider);
              await service.getIncident(widget.incidentId);
            } catch (_) {}
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            physics: const AlwaysScrollableScrollPhysics(),
            child: incident == null ? Center(child: Text('Инцидент не найден', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))) : Column(
              children: [
                IncidentHeaderCard(
                  incident: incident,
                  onStatusToggle: () async {
                    if (!ref.read(permissionStateProvider).hasPermission(PermissionKey.incidentUpdate)) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Нет прав на редактирование инцидентов'), backgroundColor: Colors.red),
                        );
                      }
                      return;
                    }
                    final canWrite = ref.read(writeAccessProvider);
                    if (!canWrite) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Нет интернета и у вас нет прав на редактирование без сети'), backgroundColor: Colors.red),
                        );
                      }
                      return;
                    }
                    final service = ref.read(incidentServiceProvider);
                    final syncRepo = ref.read(syncRepositoryProvider);
                    final isClosed = incident.status == IncidentStatus.resolved || incident.status == IncidentStatus.closed;
                    final newStatus = isClosed ? IncidentStatus.open : IncidentStatus.resolved;

                    try {
                      if (isClosed) {
                        // КРИТИЧНО: При возобновлении используем resumeIncident,
                        // чтобы отправить finishedAt=null и autoResolveOnFinish=false.
                        await service.resumeIncident(widget.incidentId);
                      } else {
                        await service.updateIncident(widget.incidentId, IncidentUpdate(id: widget.incidentId, status: newStatus));
                      }
                    } on DioException catch (e) {
                      // Нет сети — сохраняем оффлайн для синхронизации позже
                      if (e.type == DioExceptionType.connectionError ||
                          e.type == DioExceptionType.connectionTimeout ||
                          e.type == DioExceptionType.sendTimeout ||
                          e.type == DioExceptionType.receiveTimeout ||
                          e.type == DioExceptionType.unknown) {
                        await syncRepo.saveIncidentOffline(
                          update: IncidentUpdate(
                            id: widget.incidentId,
                            status: newStatus,
                            boilerHouseId: incident.boilerHouseId,
                            title: incident.title,
                            description: incident.description,
                            severity: incident.severity,
                            resourceHotWaterStopped: incident.resourceHotWaterStopped,
                            resourceHeatingStopped: incident.resourceHeatingStopped,
                            affectedHouseIds: incident.affectedHouseIds,
                            assignedTo: incident.assignedTo,
                            startedAt: isClosed ? DateTime.now().toUtc().toIso8601String() : null,
                            autoResolveOnFinish: isClosed ? false : null,
                            resolvedAt: newStatus == IncidentStatus.resolved
                                ? DateTime.now().toIso8601String() : null,
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Сохранено оффлайн. Синхронизируется при подключении.'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка обновления статуса: $e')));
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка обновления статуса: $e')));
                      }
                    }
                  },
                  onEdit: () {
                    if (!ref.read(permissionStateProvider).hasPermission(PermissionKey.incidentUpdate)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Нет прав на редактирование инцидентов'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => IncidentFormScreen(initialIncident: incident),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // BoilerHouseInfoCard скрыт по требованию УК

                // AffectedHousesCard скрыт по требованию УК

                if (incident.description != null) ...[
                  IncidentDescriptionCard(description: incident.description!),
                  const SizedBox(height: 16),
                ],
                IncidentChatCard(incidentId: widget.incidentId),
                const SizedBox(height: 16),
                IncidentPhotosCard(
                  incidentId: widget.incidentId,
                  photos: incident.photos ?? [],
                ),
                const SizedBox(height: 16),
                IncidentActivityCard(incidentId: widget.incidentId),
                const SizedBox(height: 32), // Bottom padding
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Ошибка загрузки: $err', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(singleIncidentProvider(widget.incidentId)),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
