import '../repositories/call_repository.dart';

class SendIceCandidateUseCase {
  final CallRepository _repository;

  SendIceCandidateUseCase(this._repository);

  Future<void> call({
    required int targetUserId,
    required Map<String, dynamic> candidate,
  }) {
    return _repository.sendIceCandidate(
      targetUserId: targetUserId,
      candidate: candidate,
    );
  }
}
