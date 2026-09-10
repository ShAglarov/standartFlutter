import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/user_service.dart';
import '../../models/incident_models.dart';
import '../../models/user_role.dart';
import '../base_card.dart';
import '../user_profile_sheet.dart';

class IncidentHeaderCard extends ConsumerWidget {
  final IncidentResponse incident;
  final VoidCallback? onStatusToggle;
  final VoidCallback? onEdit;

  const IncidentHeaderCard({
    super.key,
    required this.incident,
    this.onStatusToggle,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersMapAsync = ref.watch(usersMapProvider);
    final usersMap = usersMapAsync.value ?? {};
    
    String getUsername(int? id) {
      if (id == null) return "Не назначен";
      final user = usersMap[id];
      if (user != null) {
        return user.formattedDisplayName;
      }
      return 'ID $id';
    }

    void showUserProfile(int? id) {
      if (id == null) return;
      final user = usersMap[id];
      if (user != null) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => UserProfileSheet(user: user),
        );
      }
    }

    String getNotificationTarget() {
      final config = incident.notificationConfig;
      if (config == null || config.type == AudienceType.broadcast) return "Всем пользователям";
      if (config.type == AudienceType.roleBased) {
        final roleIds = config.roleIds ?? [];
        if (roleIds.isEmpty) return "Никому (роли не выбраны)";
        if (roleIds.length == 1) {
          final role = UserRole.fromAnyString(roleIds.first);
          return "Роль: ${role.title}";
        }
        return "Выбрано ролей: ${roleIds.length}";
      }
      if (config.type == AudienceType.userBased) {
        final ids = config.userIds ?? [];
        if (ids.isEmpty) return "Никому (список пуст)";
        if (ids.length == 1) return getUsername(ids.first);
        return "Выбрано: ${ids.length}";
      }
      return "Всем";
    }

    bool isScheduled = incident.isScheduledLocal;
    bool isActive = !isScheduled && incident.status != IncidentStatus.resolved && incident.status != IncidentStatus.closed;
    
    // Цвет акцентной линии и бейджа: красный для активных, зелёный для завершённых, серый для запланированных
    Color accentColor = isScheduled ? Colors.grey : (isActive ? Colors.red : Colors.green);
    String statusLabel = isScheduled ? 'ЗАПЛАНИРОВАН' : (isActive ? 'АКТИВЕН' : 'РЕШЁН');
    
    // Format date — для запланированных показываем startedAt
    String dateStr = '';
    String? rawDate = isScheduled ? (incident.startedAt ?? incident.createdAt) : incident.createdAt;
    if (rawDate != null) {
      try {
        final dt = DateTime.parse(rawDate).toLocal();
        dateStr = isScheduled
            ? 'Старт: ${DateFormat('dd.MM.yyyy HH:mm').format(dt)}'
            : DateFormat('dd.MM.yyyy HH:mm').format(dt);
      } catch (_) {
        dateStr = rawDate;
      }
    }


    return BaseCard(
      child: Stack(
        children: [
          // Left accent line
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: Container(
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      dateStr,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(128),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '№${incident.id}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        incident.title ?? 'Без названия',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                // Адрес котельной скрыт по требованию УК
                const SizedBox(height: 16),
                Divider(color: Theme.of(context).colorScheme.onSurface.withAlpha(25), height: 1),
                const SizedBox(height: 16),
                InkWell(
                  onTap: incident.assignedTo != null ? () => showUserProfile(incident.assignedTo) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.grey[800],
                          child: Icon(Icons.person, size: 16, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            getUsername(incident.assignedTo),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                          ),
                        ),
                        Text(
                          'Ответственный',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(128), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(color: Theme.of(context).colorScheme.onSurface.withAlpha(25), height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.campaign, size: 20, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        getNotificationTarget(),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                // Остановлено ГВС/Отопление скрыто по требованию УК
                // Информация о неработающих котлах
                Builder(builder: (context) {
                  String? boilersInfo;
                  if (incident.supplyFullyStopped == true) {
                    boilersInfo = '🔴 Подача полностью прекращена';
                  } else if (incident.inactiveBoilerNumbers != null && incident.inactiveBoilerNumbers!.isNotEmpty) {
                    final inactive = List<int>.from(incident.inactiveBoilerNumbers!)..sort();
                    final numsText = inactive.map((n) => '№$n').join(', ');
                    final total = incident.boilerHouse?.totalBoilersCount;
                    if (total != null && total > 0) {
                      boilersInfo = '⚠️ Котлы $numsText из $total — не работают';
                    } else {
                      boilersInfo = '⚠️ Котлы $numsText — не работают';
                    }
                  }
                  if (boilersInfo == null) return const SizedBox.shrink();
                  final isFullStop = boilersInfo.startsWith('🔴');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Divider(color: Theme.of(context).colorScheme.onSurface.withAlpha(25), height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.settings_suggest,
                            size: 20,
                            color: isFullStop ? Colors.red : Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              boilersInfo,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withAlpha(50)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Редактировать', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isScheduled ? null : onStatusToggle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isScheduled ? Colors.grey : (isActive ? Colors.red : Colors.blue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          isScheduled ? 'Ожидает старта' : (isActive ? 'Закрыть инцидент' : 'Открыть повторно'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
