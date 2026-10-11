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

  /// Получение инцидентов по адресу жильца (все статусы).
  Future<List<Map<String, dynamic>>> getMyIncidents() async {
    final response = await _dio.get(
      AppConstants.residentIncidents,
    );
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

  /// Текущий долг жильца и история платежей по периодам.
  ///
  /// null — лицевой счёт не привязан (404). Это не ошибка: оператор мог
  /// ещё не указать номер счёта в профиле жильца, и экран обязан
  /// показать подсказку, а не «ошибка сети».
  Future<ResidentDebt?> getMyDebt() async {
    try {
      final response = await _dio.get(AppConstants.residentDebt);
      return ResidentDebt.fromJson((response.data as Map).cast());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Данные чека по платёжному документу жильца.
  ///
  /// Тот же ответ, что получает касса: чек собирается на бэкенде
  /// (`build_receipt_data`), клиент его только печатает.
  Future<Map<String, dynamic>> getMyReceipt(int docId) async {
    final response = await _dio.get('${AppConstants.residentReceipt}/$docId');
    return (response.data as Map).cast<String, dynamic>();
  }
}

/// Один период в истории платежей.
class DebtPeriod {
  final int? docId;
  final String periodLabel;
  final double charged;
  final double paid;
  final double balance;
  final bool isDebt;
  final bool isOverpayment;

  const DebtPeriod({
    this.docId,
    required this.periodLabel,
    required this.charged,
    required this.paid,
    required this.balance,
    required this.isDebt,
    required this.isOverpayment,
  });

  factory DebtPeriod.fromJson(Map<String, dynamic> json) => DebtPeriod(
        docId: json['doc_id'] as int?,
        periodLabel: json['period_label']?.toString() ?? '',
        charged: (json['charged'] as num?)?.toDouble() ?? 0,
        paid: (json['paid'] as num?)?.toDouble() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        isDebt: json['is_debt'] as bool? ?? false,
        isOverpayment: json['is_overpayment'] as bool? ?? false,
      );
}

/// Долг жильца: сумма, периоды и история.
class ResidentDebt {
  final double debt;
  final double overpayment;
  final bool hasDebt;

  /// За какие месяцы долг — подпись готовит бэкенд тем же кодом, что
  /// печатает её в чеке.
  final String debtPeriodLabel;
  final String? fio;
  final String? address;
  final String? apartment;

  /// Номер счёта и последний документ — для кнопки «Получить чек».
  final String? accountNumber;
  final int? lastDocId;
  final List<DebtPeriod> history;

  const ResidentDebt({
    required this.debt,
    required this.overpayment,
    required this.hasDebt,
    required this.debtPeriodLabel,
    this.fio,
    this.address,
    this.apartment,
    this.accountNumber,
    this.lastDocId,
    this.history = const [],
  });

  factory ResidentDebt.fromJson(Map<String, dynamic> json) {
    final accounts = ((json['accounts'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    // Счетов может быть несколько (отопление, ГВС). Для чека берём тот,
    // по которому есть долг, иначе первый: у остальных история та же.
    final primary = accounts.isEmpty
        ? null
        : accounts.firstWhere(
            (a) => a['has_debt'] == true,
            orElse: () => accounts.first,
          );
    return ResidentDebt(
      debt: (json['debt'] as num?)?.toDouble() ?? 0,
      overpayment: (json['overpayment'] as num?)?.toDouble() ?? 0,
      hasDebt: json['has_debt'] as bool? ?? false,
      debtPeriodLabel: json['debt_period_label']?.toString() ?? '',
      fio: json['fio']?.toString(),
      address: json['address']?.toString(),
      apartment: json['apartment']?.toString(),
      accountNumber: primary?['account_number']?.toString(),
      lastDocId: primary?['last_doc_id'] as int?,
      history: ((primary?['history'] as List?) ?? const [])
          .map((e) => DebtPeriod.fromJson((e as Map).cast()))
          .toList(),
    );
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
