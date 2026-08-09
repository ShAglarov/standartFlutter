import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../models/incident_models.dart';
import '../services/resident_auth_service.dart';
import '../services/realtime_service.dart';
import '../providers/incident_providers.dart';
import '../widgets/incident_detail/boiler_house_info_card.dart';
import '../widgets/incident_detail/affected_houses_card.dart';
import '../widgets/incident_detail/incident_description_card.dart';
import '../widgets/resident_chat_card.dart';
import '../utils/constants.dart';

/// Экран деталей инцидента для жильца (read-only).
/// Жилец видит информацию об инциденте и может писать в чат.
/// Без возможности: редактировать, закрывать, добавлять фото.
class ResidentIncidentDetailScreen extends ConsumerStatefulWidget {
  final int incidentId;

  const ResidentIncidentDetailScreen({super.key, required this.incidentId});

  @override
  ConsumerState<ResidentIncidentDetailScreen> createState() =>
      _ResidentIncidentDetailScreenState();
}

class _ResidentIncidentDetailScreenState
    extends ConsumerState<ResidentIncidentDetailScreen> {
  IncidentResponse? _incident;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _photos = [];
  StreamSubscription<Map<String, dynamic>>? _incidentWsSub;

  @override
  void initState() {
    super.initState();
    _loadIncident();
    _listenIncidentWS();

    // Реагируем на globalRefreshEvent — DataSyncService обработал WS-обновление,
    // перезагружаем данные инцидента, чтобы отобразить свежий статус.
    ref.listenManual(globalRefreshEventProvider, (_, __) {
      _loadIncident(silent: true);
    });
  }

  void _listenIncidentWS() {
    try {
      final realtime = ref.read(realtimeServiceProvider);
      _incidentWsSub = realtime.messages.listen((msg) {
        final data = msg['data'] as Map<String, dynamic>?;
        if (data == null) return;
        final entityType = data['entity_type'] ?? msg['entity_type'];
        if (entityType != 'incident') return;

        final entityId = data['entity_id'];
        if (entityId == widget.incidentId ||
            entityId?.toString() == widget.incidentId.toString()) {
          // Тихо перезагружаем (без спиннера/ошибки)
          _loadIncident(silent: true);
        }
      });
    } catch (_) {}
  }

  Future<void> _loadIncident({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final authService = ref.read(residentAuthServiceProvider);
      final incidents = await authService.getMyIncidents();
      final matched = incidents
          .map((json) => IncidentResponse.fromJson(json))
          .where((inc) => inc.id == widget.incidentId)
          .toList();

      // Load photos
      List<Map<String, dynamic>> photos = [];
      try {
        photos = await authService.getIncidentPhotos(widget.incidentId);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _incident = matched.isNotEmpty ? matched.first : null;
          _photos = photos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!silent && mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _incidentWsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('ИНЦИДЕНТ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : _incident == null
                  ? Center(
                      child: Text('Инцидент не найден',
                          style: TextStyle(color: theme.colorScheme.onSurface)))
                  : RefreshIndicator(
                      onRefresh: _loadIncident,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16.0),
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            // Read-only header (no edit/toggle buttons)
                            _ResidentIncidentHeader(incident: _incident!),
                            const SizedBox(height: 16),

                            if (_incident!.boilerHouse != null) ...[
                              BoilerHouseInfoCard(
                                  boilerHouse: _incident!.boilerHouse!),
                              const SizedBox(height: 16),
                            ],

                            if (_incident!.affectedHouseIds != null) ...[
                              AffectedHousesCard(
                                houseIds: _incident!.affectedHouseIds!,
                                houseDetails: _incident!.affectedHouseDetails,
                                onShowAll: () {},
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (_incident!.description != null &&
                                _incident!.description!.trim().isNotEmpty) ...[
                              IncidentDescriptionCard(
                                  description: _incident!.description!),
                              const SizedBox(height: 16),
                            ],

                            // Фото инцидента (realtime через WS)
                            _ResidentIncidentPhotos(
                              incidentId: widget.incidentId,
                              initialPhotos: _photos,
                            ),
                            const SizedBox(height: 16),

                            // Чат — жилец может писать
                            ResidentChatCard(incidentId: widget.incidentId),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Ошибка загрузки: $_error',
              style: TextStyle(color: theme.colorScheme.onSurface)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadIncident,
            child: const Text('Повторить'),
          ),
        ],
      ),
    );
  }
}

// MARK: - Read-only Incident Header

class _ResidentIncidentHeader extends StatelessWidget {
  final IncidentResponse incident;

  const _ResidentIncidentHeader({required this.incident});

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

    // Ресурсы
    final stoppedServices = <String>[];
    if (incident.resourceHotWaterStopped == 1) stoppedServices.add('🚿 ГВС');
    if (incident.resourceHeatingStopped == 1) stoppedServices.add('🔥 Отопление');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badge
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (incident.createdAt != null)
                  Text(
                    _formatDate(incident.createdAt!),
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withAlpha(140)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              incident.title ?? 'Инцидент №${incident.id}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),

            // Stopped services
            if (stoppedServices.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: stoppedServices
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.red)),
                        ))
                    .toList(),
              ),
            ],

            // Dates
            if (incident.startedAt != null || incident.finishedAt != null) ...[
              const SizedBox(height: 12),
              if (incident.startedAt != null)
                _dateRow('Начало:', incident.startedAt!, theme),
              if (incident.finishedAt != null)
                _dateRow('Окончание:', incident.finishedAt!, theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateRow(String label, String isoDate, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withAlpha(140))),
          const SizedBox(width: 6),
          Text(_formatDate(isoDate),
              style: TextStyle(
                  fontSize: 13, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

// MARK: - Resident Incident Photos (with realtime WS updates)

class _ResidentIncidentPhotos extends ConsumerStatefulWidget {
  final int incidentId;
  final List<Map<String, dynamic>> initialPhotos;

  const _ResidentIncidentPhotos({
    required this.incidentId,
    required this.initialPhotos,
  });

  @override
  ConsumerState<_ResidentIncidentPhotos> createState() =>
      _ResidentIncidentPhotosState();
}

class _ResidentIncidentPhotosState
    extends ConsumerState<_ResidentIncidentPhotos> {
  late List<Map<String, dynamic>> _photos;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _photos = List.from(widget.initialPhotos);
    _connectWS();
  }

  @override
  void didUpdateWidget(covariant _ResidentIncidentPhotos oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPhotos != widget.initialPhotos) {
      setState(() => _photos = List.from(widget.initialPhotos));
    }
  }

  void _connectWS() {
    try {
      final realtime = ref.read(realtimeServiceProvider);
      _wsSub = realtime.messages.listen((msg) {
        final data = msg['data'] as Map<String, dynamic>?;
        if (data == null) return;
        final entityType = data['entity_type'] ?? msg['entity_type'];
        if (entityType != 'incident_photo') return;

        final actionType = data['action_type'] ?? msg['action_type'];
        final entityData =
            data['entity_data'] as Map<String, dynamic>? ?? data;

        if (actionType == 'create') {
          // На create, entity_data содержит данные фото с entity_id = incident_id
          final photoIncidentId = entityData['entity_id'] ?? entityData['incident_id'];
          if (photoIncidentId == widget.incidentId ||
              photoIncidentId.toString() == widget.incidentId.toString()) {
            _addPhoto(entityData);
          }
        } else if (actionType == 'delete') {
          // На delete, entity_id = photo_id (в data, не entity_data)
          final deletedPhotoId = data['entity_id'] ?? entityData['id'];
          _removePhotoById(deletedPhotoId);
        }
      });
    } catch (_) {}
  }

  void _addPhoto(Map<String, dynamic> photoData) {
    final newId = photoData['id'];
    if (newId == null) return;
    if (_photos.any((p) => p['id'] == newId)) return;
    setState(() => _photos.add(photoData));
  }

  void _removePhotoById(dynamic removedId) {
    if (removedId == null) return;
    setState(() {
      _photos.removeWhere((p) =>
          p['id'] == removedId || p['id'].toString() == removedId.toString());
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  String _fullUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    final serverRoot = AppConstants.baseUrl.replaceAll('/api/v1', '');
    return '$serverRoot$url';
  }

  void _openFullscreen(BuildContext context, int index) {
    final urls = _photos
        .map((p) => _fullUrl(p['url'] as String?))
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerScreen(urls: urls, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_photos.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.photo_library_outlined,
                    color: Colors.blue.withOpacity(0.7), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Фото (${_photos.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  final thumbUrl = _fullUrl(
                      photo['thumbnail_url'] as String? ??
                          photo['url'] as String?);

                  return GestureDetector(
                    onTap: () => _openFullscreen(context, index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        thumbUrl,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 120,
                            height: 120,
                            color: Colors.grey[900],
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (_, error, __) {
                          debugPrint('[ResidentPhotos] Error loading: $error, URL: $thumbUrl');
                          return Container(
                            width: 120,
                            height: 120,
                            color: Colors.grey[800],
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Fullscreen Photo Viewer

class _PhotoViewerScreen extends StatelessWidget {
  final List<String> urls;
  final int initialIndex;

  const _PhotoViewerScreen({required this.urls, required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('${initialIndex + 1} / ${urls.length}',
            style: const TextStyle(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: urls.length,
        itemBuilder: (_, index) {
          return Center(
            child: InteractiveViewer(
              child: Image.network(
                urls[index],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
