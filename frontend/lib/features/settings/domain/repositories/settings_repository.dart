import '../../../../core/storage/storage_manager_service.dart';
import '../../../auth/domain/entities/user_entity.dart';

abstract class SettingsRepository {
  Future<UserEntity> updateProfile({
    required String name,
    required String email,
  });

  Future<String> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  });

  Future<UserEntity> updatePrivacy({
    required bool showLastSeen,
  });

  Future<StorageBreakdown> getStorageBreakdown();

  Future<int> clearMediaCache();
}
