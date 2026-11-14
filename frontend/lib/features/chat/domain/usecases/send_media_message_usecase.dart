import 'dart:typed_data';
import '../entities/message_entity.dart';
import '../repositories/chat_repository.dart';

class SendMediaMessageUseCase {
  final ChatRepository _repository;

  SendMediaMessageUseCase(this._repository);

  Future<MessageEntity> call({
    required int receiverId,
    required String peerPublicKey,
    required Uint8List fileBytes,
    required String messageType,
    String? fileName,
    int? fileSize,
    int? replyToId,
    String? replyPreview,
  }) {
    return _repository.sendMediaMessage(
      receiverId: receiverId,
      peerPublicKey: peerPublicKey,
      fileBytes: fileBytes,
      messageType: messageType,
      fileName: fileName,
      fileSize: fileSize,
      replyToId: replyToId,
      replyPreview: replyPreview,
    );
  }
}
