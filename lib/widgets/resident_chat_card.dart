import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../services/base_api_service.dart';
import '../services/realtime_service.dart';
import 'dart:developer' as dev;

/// Простая карточка чата для жильца.
/// Использует резидентские endpoints: GET/POST /residents/me/incidents/{id}/comments
/// Подключается к WebSocket для realtime обновлений.
class ResidentChatCard extends ConsumerStatefulWidget {
  final int incidentId;

  const ResidentChatCard({super.key, required this.incidentId});

  @override
  ConsumerState<ResidentChatCard> createState() => _ResidentChatCardState();
}

class _ResidentChatCardState extends ConsumerState<ResidentChatCard> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  String? _error;
  bool _isSending = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  @override
  void initState() {
    super.initState();
    _loadComments();
    // Connect WebSocket for realtime updates
    final realtime = ref.read(realtimeServiceProvider);
    realtime.connect();
    // Listen for incident_comment messages
    _wsSub = realtime.messages.listen(_handleWsMessage);
    // Polling every 10 seconds as fallback
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleWsMessage(Map<String, dynamic> message) {
    // Check for incident_comment related events
    final type = message['type'];
    if (type == 'action_sync') {
      final data = message['data'] as Map<String, dynamic>?;
      if (data != null) {
        final entityType = data['entity_type'];
        final actionType = data['action_type'];
        if (entityType == 'incident_comment' && actionType == 'create') {
          // Check if this comment belongs to our incident
          final entityData = data['entity_data'] as Map<String, dynamic>?;
          if (entityData != null && entityData['incident_id'] == widget.incidentId) {
            dev.log('ResidentChat: WS received new comment for incident ${widget.incidentId}', name: 'Chat');
            _silentRefresh();
          } else {
            // Refresh anyway — might be our incident
            _silentRefresh();
          }
        }
      }
    }
  }

  Future<void> _loadComments() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/residents/me/incidents/${widget.incidentId}/comments');
      final data = response.data as List;
      setState(() {
        _comments = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      dev.log('ResidentChat: Error loading comments: $e', name: 'Chat');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Silent refresh — no loading spinner, just update if new comments
  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/residents/me/incidents/${widget.incidentId}/comments');
      final data = response.data as List;
      final newComments = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (newComments.length != _comments.length && mounted) {
        setState(() => _comments = newComments);
        _scrollToBottom();
      }
    } catch (_) {
      // Silently ignore polling errors
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    _controller.clear();
    setState(() => _isSending = true);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/residents/me/incidents/${widget.incidentId}/comments',
        data: {'text': text},
      );
      final newComment = Map<String, dynamic>.from(response.data as Map);
      setState(() {
        // Guard against duplicate: while awaiting POST, the WS echo may have
        // already triggered _silentRefresh() which added this comment.
        final newId = newComment['id'];
        final alreadyExists = newId != null &&
            _comments.any((c) => c['id'] == newId || c['id'].toString() == newId.toString());
        if (!alreadyExists) {
          _comments.add(newComment);
        }
        _isSending = false;
      });
      _scrollToBottom();
    } catch (e) {
      dev.log('ResidentChat: Error sending comment: $e', name: 'Chat');
      setState(() => _isSending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка отправки: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final dt = DateTime.parse(createdAt).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ЧАТ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadComments,
                  tooltip: 'Обновить',
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Chat messages area
            Container(
              height: 300,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Ошибка: $_error',
                                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              TextButton(onPressed: _loadComments, child: const Text('Повторить')),
                            ],
                          ),
                        )
                      : _comments.isEmpty
                          ? Center(
                              child: Text('Нет сообщений',
                                  style: TextStyle(
                                      color: theme.colorScheme.onSurface.withAlpha(100), fontSize: 14)),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount: _comments.length,
                              itemBuilder: (context, index) {
                                final c = _comments[index];
                                return _buildCommentItem(c, theme);
                              },
                            ),
            ),
            const SizedBox(height: 12),

            // Input row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Написать сообщение...',
                      hintStyle:
                          TextStyle(color: theme.colorScheme.onSurface.withAlpha(77)),
                      filled: true,
                      fillColor: theme.colorScheme.onSurface.withAlpha(13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _send,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Colors.blue),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.withAlpha(25),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> c, ThemeData theme) {
    final author = c['author'] as Map<String, dynamic>?;
    final residentAuthor = c['resident_author'] as Map<String, dynamic>?;
    final senderName = c['sender_name'] as String?;
    final authorName = residentAuthor?['full_name'] ?? author?['full_name'] ?? senderName ?? 'Система';
    final text = c['text'] ?? '';
    final createdAt = c['created_at'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.blue.withAlpha(50),
            child: Text(
              authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        authorName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(createdAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
