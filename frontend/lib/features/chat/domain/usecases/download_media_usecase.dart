import 'dart:typed_data';
import '../entities/message_entity.dart';
import '../repositories/chat_repository.dart';

class DownloadMediaUseCase {
  final ChatRepository _repository;

  DownloadMediaUseCase(this._repository);

  Future<Uint8List> call({
    required int peerId,
    required String peerPublicKey,
    required MessageEntity message,
  }) {
    return _repository.downloadAndDecryptMedia(
      peerId: peerId,
      peerPublicKey: peerPublicKey,
      message: message,
    );
  }
}
