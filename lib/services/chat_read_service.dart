import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'base_api_service.dart';
import 'secure_storage_service.dart';

/// Модель непрочитанных комментариев для инцидента
class UnreadCountItem {
  final int incidentId;
  final int unreadCount;
  final int totalComments;
  final int maxCommentId;
  final int lastReadCommentId;

  UnreadCountItem({
    required this.incidentId,
    required this.unreadCount,
    required this.totalComments,
    required this.maxCommentId,
    required this.lastReadCommentId,
  });

  factory UnreadCountItem.fromJson(Map<String, dynamic> json) {
    return UnreadCountItem(
      incidentId: json['incident_id'] as int,
      unreadCount: json['unread_count'] as int,
      totalComments: json['total_comments'] as int,
      maxCommentId: json['max_comment_id'] as int,
      lastReadCommentId: json['last_read_comment_id'] as int,
    );
  }
}

/// Riverpod provider для ChatReadService (API)
final chatReadServiceProvider = Provider<ChatReadService>((ref) {
  final dio = ref.watch(dioProvider);
  return ChatReadService(dio);
});

/// Provider для хранения состояния непрочитанных (Map: incidentId -> unreadCount)
final unreadCountsProvider = NotifierProvider<UnreadCountsNotifier, Map<int, int>>(
  UnreadCountsNotifier.new,
);

class UnreadCountsNotifier extends Notifier<Map<int, int>> {
  @override
  Map<int, int> build() => {};

  /// Загрузить все счётчики с сервера
  Future<void> fetchAll() async {
    try {
      // /chat/unread-counts — staff-only endpoint, жильцам не доступен
      final storage = ref.read(secureStorageServiceProvider);
      if (await storage.isResidentToken()) return;

      final service = ref.read(chatReadServiceProvider);
      final items = await service.getUnreadCounts();
      
      final Map<int, int> counts = {};
      for (final item in items) {
        if (item.unreadCount > 0) {
          counts[item.incidentId] = item.unreadCount;
        }
      }
      state = counts;
    } catch (e) {
      // ignore: avoid_print
      print('❌ [ChatRead] Failed to fetch unread counts: $e');
    }
  }
  
  /// Пометить инцидент как прочитанный
  Future<void> markAsRead(int incidentId) async {
    // Staff-only endpoint — жильцам не доступен
    final storage = ref.read(secureStorageServiceProvider);
    if (await storage.isResidentToken()) return;

    // Оптимистичное обновление UI
    final newState = Map<int, int>.from(state);
    newState.remove(incidentId);
    state = newState;
    
    try {
      final service = ref.read(chatReadServiceProvider);
      await service.markAsRead(incidentId);
    } catch (e) {
      // ignore: avoid_print
      print('❌ [ChatRead] Failed to mark as read: $e');
      await fetchAll();
    }
  }
  
  /// Увеличить счётчик (при получении нового комментария через WebSocket)
  void incrementUnread(int incidentId) {
    final newState = Map<int, int>.from(state);
    newState[incidentId] = (newState[incidentId] ?? 0) + 1;
    state = newState;
  }
}

/// API-сервис для работы с read cursor
class ChatReadService {
  final Dio _dio;

  ChatReadService(this._dio);

  /// Получить непрочитанные для всех инцидентов
  Future<List<UnreadCountItem>> getUnreadCounts() async {
    final response = await _dio.get('/chat/unread-counts');
    return (response.data as List)
        .map((e) => UnreadCountItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Пометить все комментарии инцидента как прочитанные
  Future<void> markAsRead(int incidentId) async {
    await _dio.post('/incidents/$incidentId/chat/mark-read');
  }
}
