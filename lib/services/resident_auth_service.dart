import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'base_api_service.dart';
import 'secure_storage_service.dart';
import '../models/resident_models.dart';
import '../utils/constants.dart';

final residentAuthServiceProvider = Provider<ResidentAuthService>((ref) {
  final dio = ref.watch(dioProvider);
  final storage = ref.watch(secureStorageServiceProvider);
  return ResidentAuthService(dio, storage);
});

class ResidentAuthService {
  final Dio _dio;
  final SecureStorageService _storage;

  ResidentAuthService(this._dio, this._storage);

  /// Авторизация жильца через POST /residents/login
  Future<ResidentLoginResponse> login(String username, String password) async {
    // Clear old tokens before login attempt
    await _storage.deleteAccessToken();
    await _storage.deleteRefreshToken();

    try {
      print('🚀 [ResidentAuth] Login to: ${AppConstants.baseUrl}${AppConstants.residentLogin}');
      final response = await _dio.post(
        AppConstants.residentLogin,
        data: {
          'username': username,
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      print('✅ [ResidentAuth] Login successful for: $username');
      final loginResponse = ResidentLoginResponse.fromJson(response.data);

      await _storage.saveAccessToken(loginResponse.accessToken);
      if (loginResponse.refreshToken != null) {
        await _storage.saveRefreshToken(loginResponse.refreshToken!);
      }

      return loginResponse;
    } on DioException catch (e) {
      print('❌ [ResidentAuth] Login failed: ${e.message}');
      if (e.response != null) {
        print('    Status: ${e.response?.statusCode}');
        print('    Data: ${e.response?.data}');
      }
      rethrow;
    }
  }

  /// Получение профиля текущего жильца
  Future<ResidentResponse> getMyProfile() async {
    final response = await _dio.get(AppConstants.residentMe);
    return ResidentResponse.fromJson(response.data);
  }

  /// Получение инцидентов по адресу жильца
  Future<List<Map<String, dynamic>>> getMyIncidents() async {
    final response = await _dio.get(AppConstants.residentIncidents);
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  /// Получение фото инцидента
  Future<List<Map<String, dynamic>>> getIncidentPhotos(int incidentId) async {
    final response = await _dio.get('${AppConstants.residentIncidents}/$incidentId/photos');
    return (response.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> logout() async {
    await _storage.clearAuthData();
  }

  /// Получение управляющей компании дома жильца
  Future<Map<String, dynamic>?> getMyManagementCompany() async {
    try {
      final response = await _dio.get(AppConstants.residentManagementCompany);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // УК не найдена — это нормально
      }
      rethrow;
    }
  }

  /// Получение лицевых счетов жильца
  Future<List<Map<String, dynamic>>?> getMyAccount() async {
    try {
      final response = await _dio.get(AppConstants.residentAccount);
      return (response.data as List).cast<Map<String, dynamic>>();
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // Счёт не найден — это нормально
      }
      rethrow;
    }
  }
}

/// Ответ от POST /residents/login
class ResidentLoginResponse {
  final String accessToken;
  final String? refreshToken;
  final String tokenType;
  final ResidentResponse resident;

  ResidentLoginResponse({
    required this.accessToken,
    this.refreshToken,
    required this.tokenType,
    required this.resident,
  });

  factory ResidentLoginResponse.fromJson(Map<String, dynamic> json) {
    return ResidentLoginResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      tokenType: json['token_type'] as String,
      resident: ResidentResponse.fromJson(json['resident'] as Map<String, dynamic>),
    );
  }
}
