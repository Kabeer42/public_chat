import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class RegisterUseCase {
  final AuthRepository _repository;

  RegisterUseCase(this._repository);

  Future<UserEntity> call({
    required String name,
    required String email,
    required String password,
    String? publicIdentityKey,
    String? publicSignedPrekey,
  }) {
    return _repository.register(
      name: name,
      email: email,
      password: password,
      publicIdentityKey: publicIdentityKey,
      publicSignedPrekey: publicSignedPrekey,
    );
  }
}
