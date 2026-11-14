import '../../../../core/storage/storage_manager_service.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_remote_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsRemoteDataSource _remoteDataSource;
  final StorageManagerService _storageManagerService;

  SettingsRepositoryImpl({
    required SettingsRemoteDataSource remoteDataSource,
    required StorageManagerService storageManagerService,
  })  : _remoteDataSource = remoteDataSource,
        _storageManagerService = storageManagerService;

  @override
  Future<UserEntity> updateProfile({
    required String name,
    required String email,
  }) {
    return _remoteDataSource.updateProfile(name: name, email: email);
  }

  @override
  Future<String> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _remoteDataSource.updatePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  @override
  Future<UserEntity> updatePrivacy({
    required bool showLastSeen,
  }) {
    return _remoteDataSource.updatePrivacy(showLastSeen: showLastSeen);
  }

  @override
  Future<StorageBreakdown> getStorageBreakdown() {
    return _storageManagerService.getStorageBreakdown();
  }

  @override
  Future<int> clearMediaCache() {
    return _storageManagerService.clearMediaCache();
  }
}
