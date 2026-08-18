import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/resident_auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/event_service.dart';
import '../utils/constants.dart';

part 'auth_providers.g.dart';

enum AuthStatus {
  initial,
  authenticated,
  unauthenticated,
}

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final bool isLoading;

  AuthState({
    required this.status,
    this.errorMessage,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

@riverpod
class Auth extends _$Auth {
  StreamSubscription? _eventSubscription;

  @override
  AuthState build() {
    final eventService = ref.watch(eventServiceProvider);
    _eventSubscription?.cancel();
    _eventSubscription = eventService.events.listen((event) {
      if (event == AppEvent.logout) {
        state = AuthState(status: AuthStatus.unauthenticated);
      }
    });
    ref.onDispose(() => _eventSubscription?.cancel());
    
    _checkAuth();
    return AuthState(status: AuthStatus.initial, isLoading: true);
  }

  Future<void> _checkAuth() async {
    final storage = ref.watch(secureStorageServiceProvider);
    final token = await storage.getAccessToken();
    if (token == null) {
      state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
      return;
    }

    // Проверяем, не истёк ли access token
    bool tokenExpired = false;
    try {
      final parts = token.split('.');
      if (parts.length == 3) {
        String payload = parts[1];
        switch (payload.length % 4) {
          case 2: payload += '=='; break;
          case 3: payload += '='; break;
        }
        final decoded = utf8.decode(base64Url.decode(payload));
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final exp = json['exp'] as int?;
        if (exp != null) {
          final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
          tokenExpired = DateTime.now().toUtc().isAfter(expiresAt);
        }
      }
    } catch (_) {}

    if (tokenExpired) {
      print('⚠️ [Auth] Access token expired — trying refresh...');
      // Пробуем обновить токен
      final refreshToken = await storage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
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
            final newAccess = response.data['access_token'] as String?;
            final newRefresh = response.data['refresh_token'] as String?;
            if (newAccess != null) await storage.saveAccessToken(newAccess);
            if (newRefresh != null) await storage.saveRefreshToken(newRefresh);
            print('✅ [Auth] Token refreshed at startup');
            state = state.copyWith(status: AuthStatus.authenticated, isLoading: false);
            return;
          }
        } catch (e) {
          print('❌ [Auth] Refresh failed at startup: $e');
        }
      }
      // Refresh не помог — очищаем и на логин
      print('❌ [Auth] Token expired and refresh failed — forcing login');
      await storage.clearAuthData();
      state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
      return;
    }

    // Токен есть и не истёк
    state = state.copyWith(status: AuthStatus.authenticated, isLoading: false);
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final authService = ref.read(residentAuthServiceProvider);
      await authService.login(username, password);
      state = state.copyWith(status: AuthStatus.authenticated, isLoading: false);
    } catch (e) {
      print('🔥 [AuthProvider] Caught error: $e, type: ${e.runtimeType}');
      String errorMessage = 'Произошла непредвиденная ошибка: $e';
      
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout || 
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          errorMessage = 'Ошибка сети. Проверьте подключение к интернету.';
        } else if (e.response != null) {
          final statusCode = e.response!.statusCode;
          if (statusCode == 401) {
            errorMessage = 'Неверный логин или пароль.';
          } else if (statusCode == 403) {
            errorMessage = e.response?.data['detail'] ?? 'Доступ запрещён.';
          } else if (statusCode == 400) {
            errorMessage = e.response?.data['detail'] ?? 'Неверный запрос.';
          } else if (statusCode != null && statusCode >= 500) {
            errorMessage = 'Ошибка сервера. Попробуйте позже.';
          } else {
             errorMessage = 'Ошибка: ${e.response?.statusMessage}';
          }
        }
      }

      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        isLoading: false,
        errorMessage: errorMessage,
      );
    }
  }

  Future<void> logout() async {
    final authService = ref.read(residentAuthServiceProvider);
    await authService.logout();
    state = AuthState(status: AuthStatus.unauthenticated);
  }
}
