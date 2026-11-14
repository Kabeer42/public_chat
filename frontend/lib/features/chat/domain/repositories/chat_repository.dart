import 'dart:typed_data';
import '../entities/message_entity.dart';

abstract class ChatRepository {
  /// Send an encrypted message to a peer user
  Future<MessageEntity> sendMessage({
    required int receiverId,
    required String peerPublicKey,
    required String plaintext,
    String messageType = 'text',
    String? mediaUrl,
    String? encryptedMediaKey,
    int? replyToId,
    String? replyPreview,
  });

  /// Encrypt and send a media binary blob (image, video, audio, document)
  Future<MessageEntity> sendMediaMessage({
    required int receiverId,
    required String peerPublicKey,
    required Uint8List fileBytes,
    required String messageType, // 'image', 'video', 'audio', 'document'
    String? fileName,
    int? fileSize,
    int? replyToId,
    String? replyPreview,
  });

  /// Download and decrypt an encrypted media file for a message
  Future<Uint8List> downloadAndDecryptMedia({
    required int peerId,
    required String peerPublicKey,
    required MessageEntity message,
  });

  /// Fetch chat history between current user and peer
  Future<({List<MessageEntity> messages, bool hasMore})> getChatHistory({
    required int peerId,
    required String peerPublicKey,
    int? beforeId,
    int page = 1,
    int perPage = 50,
  });

  /// Mark a specific message as delivered
  Future<bool> markAsDelivered(int messageId);

  /// Mark all undelivered messages from a peer as delivered
  Future<int> markConversationAsDelivered(int peerId);

  /// Mark a specific message as read
  Future<bool> markAsRead(int messageId);

  /// Mark all unread messages from a peer as read
  Future<int> markConversationAsRead(int peerId);

  /// Delete selected messages (for_everyone or for_me)
  Future<List<int>> deleteMessages({
    required List<int> messageIds,
    required String type,
  });

  /// Stream of incoming real-time messages received over WebSocket
  Stream<MessageEntity> get incomingMessagesStream;

  /// Stream of message delivery receipts received over WebSocket
  Stream<Map<String, dynamic>> get messageDeliveredStream;

  /// Stream of message read receipts received over WebSocket
  Stream<Map<String, dynamic>> get messageReadStream;

  /// Stream of message IDs deleted by peers in real-time over WebSocket
  Stream<List<int>> get messagesDeletedStream;

  /// Get disappearing duration for conversation with peer
  Future<int> getDisappearingDuration(int peerId);

  /// Set disappearing duration for conversation with peer
  Future<int> setDisappearingDuration(int peerId, int durationSeconds);

  /// Stream of disappearing duration updates received over WebSocket
  Stream<Map<String, dynamic>> get disappearingUpdatedStream;
}
