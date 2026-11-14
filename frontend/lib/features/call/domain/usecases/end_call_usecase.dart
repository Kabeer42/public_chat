import '../repositories/call_repository.dart';

class EndCallUseCase {
  final CallRepository _repository;

  EndCallUseCase(this._repository);

  Future<void> call({
    required int targetUserId,
    String? reason,
  }) {
    return _repository.endCall(
      targetUserId: targetUserId,
      reason: reason,
    );
  }
}
