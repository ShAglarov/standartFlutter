import 'dart:async';
import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/resident_auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/event_service.dart';

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
    if (token != null) {
      state = state.copyWith(status: AuthStatus.authenticated, isLoading: false);
    } else {
      state = state.copyWith(status: AuthStatus.unauthenticated, isLoading: false);
    }
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
