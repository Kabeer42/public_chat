import '../entities/message_entity.dart';
import '../repositories/chat_repository.dart';

class GetChatHistoryUseCase {
  final ChatRepository _repository;

  GetChatHistoryUseCase(this._repository);

  Future<({List<MessageEntity> messages, bool hasMore})> call({
    required int peerId,
    required String peerPublicKey,
    int? beforeId,
    int page = 1,
    int perPage = 50,
  }) {
    return _repository.getChatHistory(
      peerId: peerId,
      peerPublicKey: peerPublicKey,
      beforeId: beforeId,
      page: page,
      perPage: perPage,
    );
  }
}
