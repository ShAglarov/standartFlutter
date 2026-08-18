import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage_service.dart';
import '../utils/constants.dart';

/// Сервис проактивного обновления токена.
///
/// - Запускает периодический таймер (каждые 50 минут) для обновления access token
///   ДО его истечения (access token живёт 60 минут).
/// - Обновляет токен при возврате приложения из фона (AppLifecycleState.resumed).
/// - Проверяет JWT exp claim и обновляет если до истечения меньше 10 минут.
class TokenRefreshService with WidgetsBindingObserver {
  final SecureStorageService _storage;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  TokenRefreshService(this._storage);

  /// Запустить проактивное обновление
  void start() {
    // Периодический таймер — каждые 45 минут
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 45), (_) {
      _silentRefreshIfNeeded();
    });

    // Слушаем lifecycle приложения
    WidgetsBinding.instance.addObserver(this);

    // Сразу проверим при старте
    _silentRefreshIfNeeded();
  }

  /// Остановить
  void stop() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Приложение вернулось из фона — проверяем токен
      print('🔄 [TokenRefresh] App resumed — checking token freshness');
      _silentRefreshIfNeeded();
    }
  }

  /// Проверяет exp claim токена. Если до истечения < 10 минут — обновляет.
  Future<void> _silentRefreshIfNeeded() async {
    if (_isRefreshing) return;

    try {
      final accessToken = await _storage.getAccessToken();
      if (accessToken == null || accessToken.isEmpty) return;

      final expiresAt = _getTokenExpiration(accessToken);
      if (expiresAt == null) {
        // Не удалось прочитать exp — обновим на всякий случай
        print('⚠️ [TokenRefresh] Cannot read exp claim — refreshing proactively');
        await _doRefresh();
        return;
      }

      final now = DateTime.now().toUtc();
      final timeLeft = expiresAt.difference(now);

      if (timeLeft.inMinutes < 10) {
        print('🔄 [TokenRefresh] Token expires in ${timeLeft.inMinutes}m — refreshing proactively');
        await _doRefresh();
      } else {
        print('✅ [TokenRefresh] Token is fresh — expires in ${timeLeft.inMinutes}m');
      }
    } catch (e) {
      print('⚠️ [TokenRefresh] Check failed: $e');
    }
  }

  /// Декодирует JWT и возвращает exp как DateTime (UTC)
  DateTime? _getTokenExpiration(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // Base64 decode payload (second part)
      String payload = parts[1];
      // Добавляем padding
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = json['exp'] as int?;
      if (exp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Выполняет refresh token запрос
  Future<void> _doRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      final refreshToken = await _storage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        print('⚠️ [TokenRefresh] No refresh token available');
        return;
      }

      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));

      final response = await dio.post(
        AppConstants.refresh,
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final newAccessToken = response.data['access_token'] as String?;
        final newRefreshToken = response.data['refresh_token'] as String?;

        if (newAccessToken != null) {
          await _storage.saveAccessToken(newAccessToken);
        }
        if (newRefreshToken != null) {
          await _storage.saveRefreshToken(newRefreshToken);
        }

        print('✅ [TokenRefresh] Token refreshed proactively');
      }
    } catch (e) {
      print('❌ [TokenRefresh] Proactive refresh failed: $e');
    } finally {
      _isRefreshing = false;
    }
  }
}

/// Provider для TokenRefreshService
final tokenRefreshServiceProvider = Provider<TokenRefreshService>((ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  final service = TokenRefreshService(storage);
  ref.onDispose(() => service.stop());
  return service;
});
