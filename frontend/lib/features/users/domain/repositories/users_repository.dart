import '../../../auth/domain/entities/user_entity.dart';

abstract class UsersRepository {
  Future<List<UserEntity>> getUsers();

  Future<Map<String, dynamic>> getUserPublicKey(int userId);
}
