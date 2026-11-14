import '../repositories/chat_repository.dart';

class DeleteMessagesUseCase {
  final ChatRepository _repository;

  DeleteMessagesUseCase(this._repository);

  Future<List<int>> call({
    required List<int> messageIds,
    required String type,
  }) {
    return _repository.deleteMessages(
      messageIds: messageIds,
      type: type,
    );
  }
}
