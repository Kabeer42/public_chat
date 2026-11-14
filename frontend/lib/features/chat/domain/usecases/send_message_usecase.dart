import '../entities/message_entity.dart';
import '../repositories/chat_repository.dart';

class SendMessageUseCase {
  final ChatRepository _repository;

  SendMessageUseCase(this._repository);

  Future<MessageEntity> call({
    required int receiverId,
    required String peerPublicKey,
    required String plaintext,
    String messageType = 'text',
    String? mediaUrl,
    String? encryptedMediaKey,
    int? replyToId,
    String? replyPreview,
  }) {
    return _repository.sendMessage(
      receiverId: receiverId,
      peerPublicKey: peerPublicKey,
      plaintext: plaintext,
      messageType: messageType,
      mediaUrl: mediaUrl,
      encryptedMediaKey: encryptedMediaKey,
      replyToId: replyToId,
      replyPreview: replyPreview,
    );
  }
}
