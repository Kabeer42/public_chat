import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/repositories/users_repository.dart';
import '../datasources/users_remote_data_source.dart';

class UsersRepositoryImpl implements UsersRepository {
  final UsersRemoteDataSource _remoteDataSource;

  UsersRepositoryImpl({
    required UsersRemoteDataSource remoteDataSource,
  }) : _remoteDataSource = remoteDataSource;

  @override
  Future<List<UserEntity>> getUsers() async {
    return await _remoteDataSource.getUsers();
  }

  @override
  Future<Map<String, dynamic>> getUserPublicKey(int userId) async {
    return await _remoteDataSource.getUserPublicKey(userId);
  }
}
