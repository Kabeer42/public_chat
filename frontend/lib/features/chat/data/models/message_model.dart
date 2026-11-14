import '../../domain/entities/message_entity.dart';

class MessageModel extends MessageEntity {
  const MessageModel({
    required super.id,
    required super.senderId,
    required super.receiverId,
    required super.messageType,
    required super.ciphertext,
    required super.iv,
    required super.mac,
    super.plaintext,
    super.mediaUrl,
    super.encryptedMediaKey,
    super.fileName,
    super.fileSize,
    super.localFilePath,
    super.replyToId,
    super.replyPreview,
    super.isDelivered,
    super.deliveredAt,
    super.isRead,
    super.readAt,
    super.expiresAt,
    required super.createdAt,
    super.isSending,
    super.hasFailed,
    super.senderPublicKey,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      senderId: json['sender_id'] is int
          ? json['sender_id']
          : int.parse(json['sender_id'].toString()),
      receiverId: json['receiver_id'] is int
          ? json['receiver_id']
          : int.parse(json['receiver_id'].toString()),
      messageType: json['message_type'] ?? 'text',
      ciphertext: json['ciphertext'] ?? '',
      iv: json['iv'] ?? '',
      mac: json['mac'] ?? '',
      mediaUrl: json['media_url'],
      encryptedMediaKey: json['encrypted_media_key'],
      fileName: json['file_name'],
      fileSize: json['file_size'] != null
          ? (json['file_size'] is int
              ? json['file_size']
              : int.tryParse(json['file_size'].toString()))
          : null,
      replyToId: json['reply_to_id'] != null
          ? (json['reply_to_id'] is int
              ? json['reply_to_id']
              : int.tryParse(json['reply_to_id'].toString()))
          : null,
      replyPreview: json['reply_preview'],
      isDelivered: json['is_delivered'] == true || json['is_delivered'] == 1,
      deliveredAt: json['delivered_at'] != null ? DateTime.tryParse(json['delivered_at']) : null,
      isRead: json['is_read'] == true || json['is_read'] == 1,
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at']) : null,
      expiresAt: json['expires_at'] != null ? DateTime.tryParse(json['expires_at']) : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      senderPublicKey: json['sender_public_key'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message_type': messageType,
      'ciphertext': ciphertext,
      'iv': iv,
      'mac': mac,
      'media_url': mediaUrl,
      'encrypted_media_key': encryptedMediaKey,
      'file_name': fileName,
      'file_size': fileSize,
      'reply_to_id': replyToId,
      'reply_preview': replyPreview,
      'is_delivered': isDelivered,
      'delivered_at': deliveredAt?.toIso8601String(),
      'is_read': isRead,
      'read_at': readAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'sender_public_key': senderPublicKey,
    };
  }

  factory MessageModel.fromEntity(MessageEntity entity, {String? plaintext}) {
    return MessageModel(
      id: entity.id,
      senderId: entity.senderId,
      receiverId: entity.receiverId,
      messageType: entity.messageType,
      ciphertext: entity.ciphertext,
      iv: entity.iv,
      mac: entity.mac,
      plaintext: plaintext ?? entity.plaintext,
      mediaUrl: entity.mediaUrl,
      encryptedMediaKey: entity.encryptedMediaKey,
      fileName: entity.fileName,
      fileSize: entity.fileSize,
      localFilePath: entity.localFilePath,
      replyToId: entity.replyToId,
      replyPreview: entity.replyPreview,
      isDelivered: entity.isDelivered,
      deliveredAt: entity.deliveredAt,
      isRead: entity.isRead,
      readAt: entity.readAt,
      expiresAt: entity.expiresAt,
      createdAt: entity.createdAt,
      isSending: entity.isSending,
      hasFailed: entity.hasFailed,
      senderPublicKey: entity.senderPublicKey,
    );
  }
}
