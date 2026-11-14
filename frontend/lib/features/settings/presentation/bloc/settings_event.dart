import 'package:equatable/equatable.dart';
import '../../../auth/domain/entities/user_entity.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettingsEvent extends SettingsEvent {
  final UserEntity user;

  const LoadSettingsEvent(this.user);

  @override
  List<Object?> get props => [user];
}

class UpdateProfileEvent extends SettingsEvent {
  final String name;
  final String email;

  const UpdateProfileEvent({
    required this.name,
    required this.email,
  });

  @override
  List<Object?> get props => [name, email];
}

class UpdatePasswordEvent extends SettingsEvent {
  final String currentPassword;
  final String newPassword;
  final String confirmPassword;

  const UpdatePasswordEvent({
    required this.currentPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  @override
  List<Object?> get props => [currentPassword, newPassword, confirmPassword];
}

class ToggleLastSeenPrivacyEvent extends SettingsEvent {
  final bool showLastSeen;

  const ToggleLastSeenPrivacyEvent(this.showLastSeen);

  @override
  List<Object?> get props => [showLastSeen];
}

class LoadStorageBreakdownEvent extends SettingsEvent {
  const LoadStorageBreakdownEvent();
}

class ClearMediaCacheEvent extends SettingsEvent {
  const ClearMediaCacheEvent();
}
