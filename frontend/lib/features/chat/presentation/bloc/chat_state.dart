import 'package:equatable/equatable.dart';
import '../../domain/entities/message_entity.dart';

enum ChatStatus { initial, loading, loaded, error }

class ChatState extends Equatable {
  final ChatStatus status;
  final List<MessageEntity> messages;
  final bool isSending;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
  final int disappearingDurationSeconds;
  final bool isUpdatingDisappearing;

  const ChatState({
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.isSending = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
    this.disappearingDurationSeconds = 0,
    this.isUpdatingDisappearing = false,
  });

  ChatState copyWith({
    ChatStatus? status,
    List<MessageEntity>? messages,
    bool? isSending,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    int? disappearingDurationSeconds,
    bool? isUpdatingDisappearing,
  }) {
    return ChatState(
      status: status ?? this.status,
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      disappearingDurationSeconds:
          disappearingDurationSeconds ?? this.disappearingDurationSeconds,
      isUpdatingDisappearing:
          isUpdatingDisappearing ?? this.isUpdatingDisappearing,
    );
  }

  @override
  List<Object?> get props => [
        status,
        messages,
        isSending,
        isLoadingMore,
        hasMore,
        errorMessage,
        disappearingDurationSeconds,
        isUpdatingDisappearing,
      ];
}
