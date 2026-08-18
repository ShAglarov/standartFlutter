import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../services/resident_auth_service.dart';
import '../services/realtime_service.dart';
import '../services/token_refresh_service.dart';
import '../models/resident_models.dart';
import '../models/incident_models.dart';
import '../utils/app_theme.dart';
import 'resident_incident_detail_screen.dart';
import 'resident_profile_screen.dart';

/// Провайдер для кэширования профиля жильца
class ResidentProfileNotifier extends Notifier<ResidentResponse?> {
  @override
  ResidentResponse? build() => null;
  void set(ResidentResponse? value) => state = value;
}

final residentProfileProvider = NotifierProvider<ResidentProfileNotifier, ResidentResponse?>(
  ResidentProfileNotifier.new,
);

/// Счётчик для принудительного обновления residentIncidentsProvider.
/// Инкрементируется при получении WS-обновления entity_type == 'incident'.
class _ResidentRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

final _residentRefreshTrigger = NotifierProvider<_ResidentRefreshNotifier, int>(
  _ResidentRefreshNotifier.new,
);

/// Провайдер для загрузки инцидентов жильца.
final residentIncidentsProvider = FutureProvider<List<IncidentResponse>>((ref) async {
  // Зависимость от счётчика: каждый инкремент вызывает перезагрузку.
  ref.watch(_residentRefreshTrigger);

  final authService = ref.watch(residentAuthServiceProvider);
  final rawIncidents = await authService.getMyIncidents();
  return rawIncidents.map((json) => IncidentResponse.fromJson(json)).toList();
});

class ResidentHomeScreen extends ConsumerStatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  ConsumerState<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends ConsumerState<ResidentHomeScreen>
    with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();

    // Запускаем проактивное обновление токена
    ref.read(tokenRefreshServiceProvider).start();

    // КРИТИЧНО: Подключаем WebSocket при старте приложения.
    ref.read(realtimeServiceProvider).connect();

    // Слушаем WS-сообщения: при обновлении инцидента инкрементируем счётчик,
    // что вызывает перезагрузку residentIncidentsProvider.
    final realtime = ref.read(realtimeServiceProvider);
    _wsSub = realtime.messages.listen((msg) {
      final data = msg['data'] as Map<String, dynamic>?;
      if (data == null) return;
      final entityType = data['entity_type'] ?? msg['entity_type'];
      if (entityType == 'incident') {
        print('🎯 [ResidentHome] WS incident update → refreshing list');
        ref.read(_residentRefreshTrigger.notifier).increment();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    ref.read(tokenRefreshServiceProvider).stop();
    super.dispose();
  }

  /// При возвращении из фона — переподключаем WS и обновляем инциденты,
  /// чтобы отобразить изменения статусов, произошедшие пока приложение было свёрнуто.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [ResidentHome] App resumed → reconnecting WS + refreshing incidents');
      ref.read(realtimeServiceProvider).reconnectNow();
      ref.invalidate(residentIncidentsProvider);
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    try {
      final authService = ref.read(residentAuthServiceProvider);
      final profile = await authService.getMyProfile();
      ref.read(residentProfileProvider.notifier).set(profile);
    } catch (e) {
      print('⚠️ [ResidentHome] Failed to load profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(residentProfileProvider);
    final incidentsAsync = ref.watch(residentIncidentsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Мой дом', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (profile != null)
              Text(
                profile.displayAddress,
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withAlpha(180)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ResidentProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(residentIncidentsProvider);
          await _loadProfile();
        },
        child: incidentsAsync.when(
          data: (incidents) => _buildIncidentList(incidents, theme),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => _buildError(err, theme),
        ),
      ),
    );
  }

  Widget _buildIncidentList(List<IncidentResponse> incidents, ThemeData theme) {
    if (incidents.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(Icons.check_circle_outline, size: 80, color: Colors.green.withAlpha(120)),
                const SizedBox(height: 16),
                Text(
                  'Нет активных инцидентов',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Всё работает в штатном режиме',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: incidents.length,
      itemBuilder: (context, index) {
        final inc = incidents[index];
        return _ResidentIncidentCard(
          incident: inc,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ResidentIncidentDetailScreen(incidentId: inc.id),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildError(Object err, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.errorRed, size: 48),
            const SizedBox(height: 16),
            Text('Ошибка загрузки: $err', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(residentIncidentsProvider),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Resident Incident Card

class _ResidentIncidentCard extends StatelessWidget {
  final IncidentResponse incident;
  final VoidCallback onTap;

  const _ResidentIncidentCard({required this.incident, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isResolved = incident.status == IncidentStatus.resolved || incident.status == IncidentStatus.closed;
    final isScheduled = incident.isScheduledLocal;
    
    final Color statusColor;
    final String statusText;
    if (isScheduled) {
      statusColor = Colors.blueGrey;
      statusText = 'ЗАПЛАНИРОВАН';
    } else if (isResolved) {
      statusColor = Colors.green;
      statusText = 'ЗАВЕРШЁН';
    } else {
      statusColor = Colors.orange;
      statusText = 'АКТИВЕН';
    }

    // Ресурсы
    final stoppedServices = <String>[];
    if (incident.resourceHotWaterStopped == 1) stoppedServices.add('🚿 ГВС');
    if (incident.resourceHeatingStopped == 1) stoppedServices.add('🔥 Отопление');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Status + Date
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (incident.createdAt != null)
                    Text(
                      _formatDate(incident.createdAt!),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withAlpha(140),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              // Title
              Text(
                incident.title ?? 'Инцидент №${incident.id}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              // Boiler house
              if (incident.boilerHouse?.address != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.onSurface.withAlpha(140)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Котельная: ${incident.boilerHouse!.address}',
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withAlpha(180)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // Stopped services
              if (stoppedServices.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: stoppedServices.map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(s, style: const TextStyle(fontSize: 12, color: Colors.red)),
                  )).toList(),
                ),
              ],

              // Description preview
              if (incident.description != null && incident.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  incident.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withAlpha(160),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
      if (diff.inHours < 24) return '${diff.inHours} ч назад';
      if (diff.inDays < 7) return '${diff.inDays} дн назад';

      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}
