import 'package:equatable/equatable.dart';
import '../../domain/entities/message_entity.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class LoadChatHistoryEvent extends ChatEvent {
  final int peerId;
  final String peerPublicKey;

  const LoadChatHistoryEvent({
    required this.peerId,
    required this.peerPublicKey,
  });

  @override
  List<Object?> get props => [peerId, peerPublicKey];
}

class LoadMoreMessagesEvent extends ChatEvent {
  final int peerId;
  final String peerPublicKey;

  const LoadMoreMessagesEvent({
    required this.peerId,
    required this.peerPublicKey,
  });

  @override
  List<Object?> get props => [peerId, peerPublicKey];
}

class SendMessageEvent extends ChatEvent {
  final int peerId;
  final String peerPublicKey;
  final String text;
  final String messageType;
  final int? replyToId;
  final String? replyPreview;

  const SendMessageEvent({
    required this.peerId,
    required this.peerPublicKey,
    required this.text,
    this.messageType = 'text',
    this.replyToId,
    this.replyPreview,
  });

  @override
  List<Object?> get props => [peerId, peerPublicKey, text, messageType, replyToId, replyPreview];
}


class MessageReceivedEvent extends ChatEvent {
  final MessageEntity message;

  const MessageReceivedEvent(this.message);

  @override
  List<Object?> get props => [message];
}

class MessageReadReceiptEvent extends ChatEvent {
  final int messageId;
  final DateTime? readAt;

  const MessageReadReceiptEvent({
    required this.messageId,
    this.readAt,
  });

  @override
  List<Object?> get props => [messageId, readAt];
}

class MessageDeliveredReceiptEvent extends ChatEvent {
  final List<int> messageIds;
  final DateTime? deliveredAt;

  const MessageDeliveredReceiptEvent({
    required this.messageIds,
    this.deliveredAt,
  });

  @override
  List<Object?> get props => [messageIds, deliveredAt];
}

class MarkConversationAsReadEvent extends ChatEvent {
  final int peerId;

  const MarkConversationAsReadEvent(this.peerId);

  @override
  List<Object?> get props => [peerId];
}

class SendMediaMessageEvent extends ChatEvent {
  final int peerId;
  final String peerPublicKey;
  final dynamic fileBytes; // Uint8List
  final String messageType; // 'image', 'video', 'audio', 'document'
  final String? fileName;
  final int? fileSize;
  final int? replyToId;
  final String? replyPreview;

  const SendMediaMessageEvent({
    required this.peerId,
    required this.peerPublicKey,
    required this.fileBytes,
    required this.messageType,
    this.fileName,
    this.fileSize,
    this.replyToId,
    this.replyPreview,
  });

  @override
  List<Object?> get props => [peerId, peerPublicKey, fileBytes, messageType, fileName, fileSize, replyToId, replyPreview];
}

class DeleteMessagesEvent extends ChatEvent {
  final List<int> messageIds;
  final String type; // 'for_everyone' or 'for_me'

  const DeleteMessagesEvent({
    required this.messageIds,
    required this.type,
  });

  @override
  List<Object?> get props => [messageIds, type];
}

class MessagesDeletedRemotelyEvent extends ChatEvent {
  final List<int> messageIds;

  const MessagesDeletedRemotelyEvent(this.messageIds);

  @override
  List<Object?> get props => [messageIds];
}

class LoadDisappearingDurationEvent extends ChatEvent {
  final int peerId;

  const LoadDisappearingDurationEvent(this.peerId);

  @override
  List<Object?> get props => [peerId];
}

class SetDisappearingDurationEvent extends ChatEvent {
  final int peerId;
  final int durationSeconds;

  const SetDisappearingDurationEvent({
    required this.peerId,
    required this.durationSeconds,
  });

  @override
  List<Object?> get props => [peerId, durationSeconds];
}

class DisappearingDurationUpdatedRemoteEvent extends ChatEvent {
  final int peerId;
  final int durationSeconds;

  const DisappearingDurationUpdatedRemoteEvent({
    required this.peerId,
    required this.durationSeconds,
  });

  @override
  List<Object?> get props => [peerId, durationSeconds];
}

class PurgeExpiredMessagesEvent extends ChatEvent {
  const PurgeExpiredMessagesEvent();
}


