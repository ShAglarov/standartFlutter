// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'resident_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ResidentResponse _$ResidentResponseFromJson(Map<String, dynamic> json) =>
    ResidentResponse(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      email: json['email'] as String,
      lastName: json['last_name'] as String?,
      firstName: json['first_name'] as String?,
      middleName: json['middle_name'] as String?,
      phoneNumber: json['phone_number'] as String?,
      address: json['address'] as String?,
      apartment: json['apartment'] as String?,
      accountNumber: json['account_number'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isBlocked: json['is_blocked'] as bool?,
      isDeleted: json['is_deleted'] as bool?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );

Map<String, dynamic> _$ResidentResponseToJson(ResidentResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'email': instance.email,
      'last_name': instance.lastName,
      'first_name': instance.firstName,
      'middle_name': instance.middleName,
      'phone_number': instance.phoneNumber,
      'address': instance.address,
      'apartment': instance.apartment,
      'account_number': instance.accountNumber,
      'notes': instance.notes,
      'is_active': instance.isActive,
      'is_blocked': instance.isBlocked,
      'is_deleted': instance.isDeleted,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };
