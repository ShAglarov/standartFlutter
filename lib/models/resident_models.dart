import 'package:json_annotation/json_annotation.dart';

part 'resident_models.g.dart';

@JsonSerializable()
class ResidentResponse {
  final int id;
  final String username;
  final String email;
  @JsonKey(name: 'last_name')
  final String? lastName;
  @JsonKey(name: 'first_name')
  final String? firstName;
  @JsonKey(name: 'middle_name')
  final String? middleName;
  @JsonKey(name: 'phone_number')
  final String? phoneNumber;
  final String? address;
  final String? apartment;
  @JsonKey(name: 'account_number')
  final String? accountNumber;
  final String? notes;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'is_blocked')
  final bool? isBlocked;
  @JsonKey(name: 'is_deleted')
  final bool? isDeleted;
  @JsonKey(name: 'created_at')
  final String? createdAt;
  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  ResidentResponse({
    required this.id,
    required this.username,
    required this.email,
    this.lastName,
    this.firstName,
    this.middleName,
    this.phoneNumber,
    this.address,
    this.apartment,
    this.accountNumber,
    this.notes,
    this.isActive = true,
    this.isBlocked,
    this.isDeleted,
    this.createdAt,
    this.updatedAt,
  });

  factory ResidentResponse.fromJson(Map<String, dynamic> json) => _$ResidentResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ResidentResponseToJson(this);

  String get fullName {
    final parts = [lastName, firstName, middleName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .toList();
    if (parts.isNotEmpty) return parts.join(' ');
    return username;
  }

  String get displayAddress {
    final parts = <String>[];
    if (address != null && address!.isNotEmpty) parts.add(address!);
    if (apartment != null && apartment!.isNotEmpty) parts.add('кв. $apartment');
    return parts.isNotEmpty ? parts.join(', ') : 'Адрес не указан';
  }
}
