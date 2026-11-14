import '../repositories/chat_repository.dart';

class MarkMessageReadUseCase {
  final ChatRepository _repository;

  MarkMessageReadUseCase(this._repository);

  Future<bool> call(int messageId) {
    return _repository.markAsRead(messageId);
  }

  Future<int> markConversation(int peerId) {
    return _repository.markConversationAsRead(peerId);
  }
}
