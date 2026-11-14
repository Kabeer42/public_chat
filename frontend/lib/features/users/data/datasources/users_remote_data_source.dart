import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/api_client.dart';
import '../../../auth/data/models/user_model.dart';

abstract class UsersRemoteDataSource {
  Future<List<UserModel>> getUsers();
  Future<Map<String, dynamic>> getUserPublicKey(int userId);
}

class UsersRemoteDataSourceImpl implements UsersRemoteDataSource {
  final ApiClient _apiClient;

  UsersRemoteDataSourceImpl(this._apiClient);

  @override
  Future<List<UserModel>> getUsers() async {
    final response = await _apiClient.get(ApiEndpoints.users);
    final data = response.data as Map<String, dynamic>;
    final usersList = data['users'] as List<dynamic>;

    return usersList
        .map((json) => UserModel.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Map<String, dynamic>> getUserPublicKey(int userId) async {
    final response = await _apiClient.get(ApiEndpoints.getPublicKey(userId));
    return response.data as Map<String, dynamic>;
  }
}
