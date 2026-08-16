import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/incident_models.dart';
import '../services/comment_service.dart';
import '../services/data_sync_service.dart';
import '../services/realtime_service.dart';
import '../repositories/sync_repository.dart';
import 'dart:developer' as dev;

part 'chat_providers.g.dart';

@riverpod
class IncidentChat extends _$IncidentChat {
  @override
  Stream<List<IncidentComment>> build(int incidentId) {
    _initialize(incidentId);
    final syncRepo = ref.watch(syncRepositoryProvider);
    return syncRepo.watchComments(incidentId);
  }

  Future<void> _initialize(int incidentId) async {
    try {
      final commentService = ref.read(commentServiceProvider);
      final syncRepo = ref.read(syncRepositoryProvider);
      
      // 1. Fetch initial comments from API
      final comments = await commentService.getComments(incidentId);
      
      // 2. Persist them to the DB (this will trigger the stream above)
      await syncRepo.upsertComments(incidentId, comments);
      
      // 3. Ensure WebSocket is connected (DataSyncService will handle incoming messages)
      ref.read(realtimeServiceProvider).connect();
    } catch (e) {
      dev.log('ChatProvider: Initialization failed: $e', name: 'Chat');
    }
  }

  Future<void> sendComment(String text) async {
    final commentService = ref.read(commentServiceProvider);
    final syncRepo = ref.read(syncRepositoryProvider);
    final dataSync = ref.read(dataSyncServiceProvider);
    
    try {
      final newComment = await commentService.postComment(incidentId, text);
      // Mark as sent BEFORE DB write so the WS echo is suppressed
      dataSync.markCommentAsSent(newComment.id);
      // Persist locally immediately
      await syncRepo.upsertComments(incidentId, [newComment]);
    } catch (e) {
      dev.log('ChatProvider: Failed to send comment: $e', name: 'Chat');
      rethrow;
    }
  }
}
