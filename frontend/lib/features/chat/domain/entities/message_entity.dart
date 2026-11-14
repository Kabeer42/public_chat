import 'package:equatable/equatable.dart';

class MessageEntity extends Equatable {
  final int id;
  final int senderId;
  final int receiverId;
  final String messageType;
  final String ciphertext;
  final String iv;
  final String mac;
  final String? plaintext;
  final String? mediaUrl;
  final String? encryptedMediaKey;
  final int? replyToId;
  final String? replyPreview;
  final String? localFilePath;
  final String? fileName;
  final int? fileSize;
  final bool isDelivered;
  final DateTime? deliveredAt;
  final bool isRead;
  final DateTime? readAt;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final bool isSending;
  final bool hasFailed;
  final String? senderPublicKey;

  const MessageEntity({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageType,
    required this.ciphertext,
    required this.iv,
    required this.mac,
    this.plaintext,
    this.mediaUrl,
    this.encryptedMediaKey,
    this.fileName,
    this.fileSize,
    this.localFilePath,
    this.replyToId,
    this.replyPreview,
    this.isDelivered = false,
    this.deliveredAt,
    this.isRead = false,
    this.readAt,
    this.expiresAt,
    required this.createdAt,
    this.isSending = false,
    this.hasFailed = false,
    this.senderPublicKey,
  });

  MessageEntity copyWith({
    int? id,
    int? senderId,
    int? receiverId,
    String? messageType,
    String? ciphertext,
    String? iv,
    String? mac,
    String? plaintext,
    String? mediaUrl,
    String? encryptedMediaKey,
    String? fileName,
    int? fileSize,
    String? localFilePath,
    int? replyToId,
    String? replyPreview,
    bool? isDelivered,
    DateTime? deliveredAt,
    bool? isRead,
    DateTime? readAt,
    DateTime? expiresAt,
    DateTime? createdAt,
    bool? isSending,
    bool? hasFailed,
    String? senderPublicKey,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      messageType: messageType ?? this.messageType,
      ciphertext: ciphertext ?? this.ciphertext,
      iv: iv ?? this.iv,
      mac: mac ?? this.mac,
      plaintext: plaintext ?? this.plaintext,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      encryptedMediaKey: encryptedMediaKey ?? this.encryptedMediaKey,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      localFilePath: localFilePath ?? this.localFilePath,
      replyToId: replyToId ?? this.replyToId,
      replyPreview: replyPreview ?? this.replyPreview,
      isDelivered: isDelivered ?? this.isDelivered,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      isSending: isSending ?? this.isSending,
      hasFailed: hasFailed ?? this.hasFailed,
      senderPublicKey: senderPublicKey ?? this.senderPublicKey,
    );
  }

  @override
  List<Object?> get props => [
        id,
        senderId,
        receiverId,
        messageType,
        ciphertext,
        iv,
        mac,
        plaintext,
        mediaUrl,
        encryptedMediaKey,
        fileName,
        fileSize,
        localFilePath,
        replyToId,
        replyPreview,
        isDelivered,
        deliveredAt,
        isRead,
        readAt,
        expiresAt,
        createdAt,
        isSending,
        hasFailed,
        senderPublicKey,
      ];
}

