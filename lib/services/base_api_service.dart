import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage_service.dart';
import 'event_service.dart';
import 'device_id_service.dart';
import 'server_manager.dart';
import '../utils/constants.dart';

final dioProvider = Provider<Dio>((ref) {
  // КРИТИЧНО: Наблюдаем за serverStateProvider, чтобы Dio пересоздавался при смене сервера
  final serverState = ref.watch(serverStateProvider).value ?? ref.read(serverManagerProvider).state;
  final currentBaseUrl = serverState.currentBaseUrl;
  
  final dio = Dio(
    BaseOptions(
      baseUrl: currentBaseUrl,
      connectTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );

  final storageService = ref.watch(secureStorageServiceProvider);
  final eventService = ref.watch(eventServiceProvider);
  final deviceIdService = ref.watch(deviceIdServiceProvider);
  
  dio.interceptors.add(AuthInterceptor(storageService, eventService, deviceIdService));

  return dio;
});


class AuthInterceptor extends Interceptor {
  final SecureStorageService _storageService;
  final EventService _eventService;
  final DeviceIdService _deviceIdService;

  /// Mutex: if a refresh is already in progress, other 401 handlers wait for it.
  Completer<bool>? _refreshCompleter;

  AuthInterceptor(this._storageService, this._eventService, this._deviceIdService);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storageService.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    final deviceId = await _deviceIdService.getDeviceId();
    options.headers['X-Device-Id'] = deviceId;
    
    // Many backend endpoints require device_id as a query parameter
    final queryParams = Map<String, dynamic>.from(options.queryParameters);
    queryParams['device_id'] = deviceId;
    options.queryParameters = queryParams;

    return handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // Don't try to refresh if we didn't send a token (unauthenticated request)
      final sentToken = err.requestOptions.headers['Authorization'];
      if (sentToken == null) {
        return handler.next(err);
      }

      // Don't refresh for the refresh endpoint itself (avoid infinite loop)
      if (err.requestOptions.path == AppConstants.refresh) {
        await _storageService.clearAuthData();
        _eventService.fire(AppEvent.logout);
        return handler.next(err);
      }

      // Try silent refresh
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        // Retry the original request with the new token
        try {
          final newToken = await _storageService.getAccessToken();
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newToken';

          final dio = Dio(BaseOptions(
            baseUrl: opts.baseUrl,
            connectTimeout: opts.connectTimeout,
            receiveTimeout: opts.receiveTimeout,
          ));
          final response = await dio.fetch(opts);
          return handler.resolve(response);
        } catch (retryError) {
          // Retry also failed — if still 401 after fresh token, force logout
          // (token type mismatch: e.g. staff token on resident endpoint)
          if (retryError is DioException && retryError.response?.statusCode == 401) {
            print('❌ [AuthInterceptor] Retry after refresh still 401 — forcing logout');
            await _storageService.clearAuthData();
            _eventService.fire(AppEvent.logout);
            return handler.next(retryError);
          }
          if (retryError is DioException) {
            return handler.next(retryError);
          }
          return handler.next(err);
        }
      } else {
        // Refresh failed — session is truly expired, log out
        await _storageService.clearAuthData();
        _eventService.fire(AppEvent.logout);
        return handler.next(err);
      }
    }
    return handler.next(err);
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true on success (new tokens saved), false on failure.
  /// Uses a Completer mutex so concurrent 401s trigger only one refresh call.
  Future<bool> _tryRefreshToken() async {
    // If another request is already refreshing, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        _refreshCompleter!.complete(false);
        return false;
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
          await _storageService.saveAccessToken(newAccessToken);
        }
        if (newRefreshToken != null) {
          await _storageService.saveRefreshToken(newRefreshToken);
        }

        print('🔄 [AuthInterceptor] Token refreshed successfully');
        _refreshCompleter!.complete(true);
        return true;
      }

      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      print('❌ [AuthInterceptor] Token refresh failed: $e');
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }
}
