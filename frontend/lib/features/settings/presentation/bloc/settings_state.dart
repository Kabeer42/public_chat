import 'package:equatable/equatable.dart';
import '../../../../core/storage/storage_manager_service.dart';
import '../../../auth/domain/entities/user_entity.dart';

class SettingsState extends Equatable {
  final UserEntity? user;
  final StorageBreakdown storageBreakdown;
  final bool isLoading;
  final bool isStorageLoading;
  final String? successMessage;
  final String? errorMessage;
  final String? referenceCode;

  const SettingsState({
    this.user,
    this.storageBreakdown = const StorageBreakdown(),
    this.isLoading = false,
    this.isStorageLoading = false,
    this.successMessage,
    this.errorMessage,
    this.referenceCode,
  });

  SettingsState copyWith({
    UserEntity? user,
    StorageBreakdown? storageBreakdown,
    bool? isLoading,
    bool? isStorageLoading,
    String? successMessage,
    String? errorMessage,
    String? referenceCode,
    bool clearMessages = false,
  }) {
    return SettingsState(
      user: user ?? this.user,
      storageBreakdown: storageBreakdown ?? this.storageBreakdown,
      isLoading: isLoading ?? this.isLoading,
      isStorageLoading: isStorageLoading ?? this.isStorageLoading,
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      referenceCode: clearMessages ? null : (referenceCode ?? this.referenceCode),
    );
  }

  @override
  List<Object?> get props => [
        user,
        storageBreakdown,
        isLoading,
        isStorageLoading,
        successMessage,
        errorMessage,
        referenceCode,
      ];
}
