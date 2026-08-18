import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../utils/constants.dart';

const String _deviceIdKey = 'device_unique_id';

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

class SecureStorageService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      print('⚠️ [SecureStorageService] Write failed ($key): ${e.message}.');
    }
  }

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      print('⚠️ [SecureStorageService] Read failed ($key): ${e.message}.');
      return null;
    }
  }

  Future<void> _safeDelete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (e) {
      print('⚠️ [SecureStorageService] Delete failed ($key): ${e.message}.');
    }
  }

  Future<void> saveAccessToken(String token) async {
    await _safeWrite(AppConstants.accessTokenKey, token);
  }

  Future<String?> getAccessToken() async {
    return await _safeRead(AppConstants.accessTokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _safeWrite(AppConstants.refreshTokenKey, token);
  }

  Future<String?> getRefreshToken() async {
    return await _safeRead(AppConstants.refreshTokenKey);
  }

  /// Очищает только аутентификационные данные (токены).
  /// КРИТИЧНО: НЕ удаляет device_unique_id — он должен переживать logout.
  /// Раньше использовался clearAll() → deleteAll(), который стирал device_id
  /// при каждом logout, генерируя новый UUID при следующем login.
  Future<void> clearAuthData() async {
    await deleteAccessToken();
    await deleteRefreshToken();
  }

  /// Полная очистка хранилища (включая device_id).
  /// Использовать ТОЛЬКО при полном сбросе данных приложения.
  Future<void> clearEverything() async {
    try {
      await _storage.deleteAll();
    } on PlatformException catch (_) {
      // Ignored
    }
  }

  Future<void> deleteAccessToken() async {
    await _safeDelete(AppConstants.accessTokenKey);
  }

  Future<void> deleteRefreshToken() async {
    await _safeDelete(AppConstants.refreshTokenKey);
  }

  Future<void> saveDeviceId(String id) async {
    await _safeWrite(_deviceIdKey, id);
  }

  Future<String?> getDeviceId() async {
    return await _safeRead(_deviceIdKey);
  }

  /// Проверяет, является ли текущий токен резидентским (жильца).
  /// JWT sub='resident:<id>' — жилец, sub=<number> — сотрудник.
  Future<bool> isResidentToken() async {
    final token = await getAccessToken();
    if (token == null) {
      print('ℹ️ [Storage] isResidentToken: no token');
      return false;
    }
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      String payload = parts[1];
      switch (payload.length % 4) {
        case 2: payload += '=='; break;
        case 3: payload += '='; break;
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final sub = json['sub'];
      final isResident = sub != null && sub.toString().startsWith('resident:');
      print('ℹ️ [Storage] isResidentToken: sub=$sub (${sub.runtimeType}), isResident=$isResident');
      return isResident;
    } catch (e) {
      print('⚠️ [Storage] isResidentToken error: $e');
      return false;
    }
  }
}
