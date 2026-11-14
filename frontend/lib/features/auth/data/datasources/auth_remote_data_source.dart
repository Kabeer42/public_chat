import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/api_client.dart';
import '../models/user_model.dart';

abstract class AuthRemoteDataSource {
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? publicIdentityKey,
    String? publicSignedPrekey,
  });

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  });

  Future<void> logout();

  Future<UserModel> getMe();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final ApiClient _apiClient;

  AuthRemoteDataSourceImpl(this._apiClient);

  @override
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? publicIdentityKey,
    String? publicSignedPrekey,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.register,
      data: {
        'name': name,
        'email': email,
        'password': password,
        'public_identity_key': publicIdentityKey,
        'public_signed_prekey': publicSignedPrekey,
      },
    );

    final data = response.data as Map<String, dynamic>;
    return {
      'token': data['token'] as String,
      'user': UserModel.fromJson(data['user'] as Map<String, dynamic>),
    };
  }

  @override
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.login,
      data: {
        'email': email,
        'password': password,
      },
    );

    final data = response.data as Map<String, dynamic>;
    return {
      'token': data['token'] as String,
      'user': UserModel.fromJson(data['user'] as Map<String, dynamic>),
    };
  }

  @override
  Future<void> logout() async {
    await _apiClient.post(ApiEndpoints.logout);
  }

  @override
  Future<UserModel> getMe() async {
    final response = await _apiClient.get(ApiEndpoints.me);
    final data = response.data as Map<String, dynamic>;
    return UserModel.fromJson(data['user'] as Map<String, dynamic>);
  }
}
