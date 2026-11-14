import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/models/user_model.dart';

abstract class SettingsRemoteDataSource {
  Future<UserModel> updateProfile({
    required String name,
    required String email,
  });

  Future<String> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  });

  Future<UserModel> updatePrivacy({
    required bool showLastSeen,
  });
}

class SettingsRemoteDataSourceImpl implements SettingsRemoteDataSource {
  final ApiClient _apiClient;

  SettingsRemoteDataSourceImpl({
    required ApiClient apiClient,
  }) : _apiClient = apiClient;

  @override
  Future<UserModel> updateProfile({
    required String name,
    required String email,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.updateProfile,
      data: {
        'name': name,
        'email': email,
      },
    );

    return UserModel.fromJson(response.data['user']);
  }

  @override
  Future<String> updatePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.updatePassword,
      data: {
        'current_password': currentPassword,
        'new_password': newPassword,
        'new_password_confirmation': confirmPassword,
      },
    );

    return response.data['message'] as String? ?? 'Password updated successfully';
  }

  @override
  Future<UserModel> updatePrivacy({
    required bool showLastSeen,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.updatePrivacy,
      data: {
        'show_last_seen': showLastSeen,
      },
    );

    return UserModel.fromJson(response.data['user']);
  }
}
