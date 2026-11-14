import '../repositories/call_repository.dart';

class InitiateCallUseCase {
  final CallRepository _repository;

  InitiateCallUseCase(this._repository);

  Future<void> call({
    required int receiverId,
    required String callType,
  }) {
    return _repository.initiateCall(
      receiverId: receiverId,
      callType: callType,
    );
  }
}
