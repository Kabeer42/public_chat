import '../../../auth/domain/entities/user_entity.dart';
import '../repositories/users_repository.dart';

class GetUsersUseCase {
  final UsersRepository _repository;

  GetUsersUseCase(this._repository);

  Future<List<UserEntity>> call() {
    return _repository.getUsers();
  }
}
