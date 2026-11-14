import '../repositories/call_repository.dart';

class AnswerCallUseCase {
  final CallRepository _repository;

  AnswerCallUseCase(this._repository);

  Future<void> call({
    required int callerId,
    required String sdpOffer,
    String callType = 'voice',
    String? callId,
  }) {
    return _repository.answerCall(
      callerId: callerId,
      sdpOffer: sdpOffer,
      callType: callType,
      callId: callId,
    );
  }
}
