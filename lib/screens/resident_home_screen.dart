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
class _ResidentRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

final _residentRefreshTrigger = NotifierProvider<_ResidentRefreshNotifier, int>(
  _ResidentRefreshNotifier.new,
);

/// Провайдер для загрузки инцидентов жильца.
/// Бекенд возвращает все инциденты (активные + завершённые),
/// фильтрация по статусу происходит на стороне UI (табы).
final residentIncidentsProvider = FutureProvider<List<IncidentResponse>>((ref) async {
  ref.watch(_residentRefreshTrigger);
  final authService = ref.watch(residentAuthServiceProvider);

  final rawList = await authService.getMyIncidents();
  return rawList.map((json) => IncidentResponse.fromJson(json)).toList();
});

class ResidentHomeScreen extends ConsumerStatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  ConsumerState<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends ConsumerState<ResidentHomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _loadProfile();

    ref.read(tokenRefreshServiceProvider).start();
    ref.read(realtimeServiceProvider).connect();

    final realtime = ref.read(realtimeServiceProvider);
    _wsSub = realtime.messages.listen((msg) {
      final data = msg['data'] as Map<String, dynamic>?;
      if (data == null) return;
      final entityType = data['entity_type'] ?? msg['entity_type'];
      if (entityType == 'incident') {
        ref.read(_residentRefreshTrigger.notifier).increment();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _wsSub?.cancel();
    ref.read(tokenRefreshServiceProvider).stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
    } catch (_) {}
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
            const Text('Мой дом',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (profile != null)
              Text(
                profile.displayAddress,
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withAlpha(180)),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResidentProfileScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Активные'),
            Tab(text: 'Завершённые'),
          ],
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          indicatorColor: AppTheme.primaryBlue,
          labelColor: AppTheme.primaryBlue,
          unselectedLabelColor: Colors.grey,
        ),
      ),
      body: incidentsAsync.when(
        data: (incidents) {
          final active = incidents
              .where((inc) =>
                  inc.status != IncidentStatus.resolved &&
                  inc.status != IncidentStatus.closed)
              .toList();
          final completed = incidents
              .where((inc) =>
                  inc.status == IncidentStatus.resolved ||
                  inc.status == IncidentStatus.closed)
              .toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(residentIncidentsProvider);
              await _loadProfile();
            },
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildList(
                  active,
                  theme,
                  emptyIcon: Icons.check_circle_outline,
                  emptyIconColor: Colors.green,
                  emptyMessage: 'Нет активных инцидентов',
                  emptySubtitle: 'Всё работает в штатном режиме',
                ),
                _buildList(
                  completed,
                  theme,
                  emptyIcon: Icons.history,
                  emptyIconColor: Colors.grey,
                  emptyMessage: 'Нет завершённых инцидентов',
                  emptySubtitle: 'Завершённые инциденты появятся здесь',
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _buildError(err, theme),
      ),
    );
  }

  Widget _buildList(
    List<IncidentResponse> incidents,
    ThemeData theme, {
    required IconData emptyIcon,
    required Color emptyIconColor,
    required String emptyMessage,
    required String emptySubtitle,
  }) {
    if (incidents.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(emptyIcon, size: 80, color: emptyIconColor.withAlpha(120)),
                const SizedBox(height: 16),
                Text(emptyMessage,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withAlpha(180))),
                const SizedBox(height: 8),
                Text(emptySubtitle,
                    style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface.withAlpha(120))),
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ResidentIncidentDetailScreen(incidentId: inc.id),
            ),
          ),
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
    final isResolved = incident.status == IncidentStatus.resolved ||
        incident.status == IncidentStatus.closed;
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

    // ГВС / Отопление скрыты от жильца

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  if (incident.createdAt != null)
                    Text(
                      _formatDate(incident.createdAt!),
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withAlpha(140)),
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
                    color: theme.colorScheme.onSurface),
              ),

              // Organisation (boiler house address)
              if (incident.boilerHouse?.address != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurface.withAlpha(140)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Организация: ${incident.boilerHouse!.address}',
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withAlpha(180)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],

              // Description preview
              if (incident.description != null &&
                  incident.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  incident.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withAlpha(160)),
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
