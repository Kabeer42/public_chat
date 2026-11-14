import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    required super.name,
    required super.email,
    super.publicIdentityKey,
    super.publicSignedPrekey,
    super.isOnline,
    super.showLastSeen,
    super.lastSeenAt,
    super.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      publicIdentityKey: json['public_identity_key'] as String?,
      publicSignedPrekey: json['public_signed_prekey'] as String?,
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      showLastSeen: json['show_last_seen'] == null ? true : (json['show_last_seen'] == true || json['show_last_seen'] == 1),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'].toString())
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'public_identity_key': publicIdentityKey,
      'public_signed_prekey': publicSignedPrekey,
      'is_online': isOnline,
      'show_last_seen': showLastSeen,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
