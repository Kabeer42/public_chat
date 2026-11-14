import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  final int id;
  final String name;
  final String email;
  final String? publicIdentityKey;
  final String? publicSignedPrekey;
  final bool isOnline;
  final bool showLastSeen;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;

  const UserEntity({
    required this.id,
    required this.name,
    required this.email,
    this.publicIdentityKey,
    this.publicSignedPrekey,
    this.isOnline = false,
    this.showLastSeen = true,
    this.lastSeenAt,
    this.createdAt,
  });

  UserEntity copyWith({
    int? id,
    String? name,
    String? email,
    String? publicIdentityKey,
    String? publicSignedPrekey,
    bool? isOnline,
    bool? showLastSeen,
    DateTime? lastSeenAt,
    DateTime? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      publicIdentityKey: publicIdentityKey ?? this.publicIdentityKey,
      publicSignedPrekey: publicSignedPrekey ?? this.publicSignedPrekey,
      isOnline: isOnline ?? this.isOnline,
      showLastSeen: showLastSeen ?? this.showLastSeen,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        email,
        publicIdentityKey,
        publicSignedPrekey,
        isOnline,
        showLastSeen,
        lastSeenAt,
        createdAt,
      ];
}
