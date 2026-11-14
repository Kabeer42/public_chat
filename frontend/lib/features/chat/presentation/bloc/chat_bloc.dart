import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/storage/local_database_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/usecases/delete_messages_usecase.dart';
import '../../domain/usecases/get_chat_history_usecase.dart';
import '../../domain/usecases/mark_message_read_usecase.dart';
import '../../domain/usecases/send_media_message_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final SendMessageUseCase _sendMessageUseCase;
  final SendMediaMessageUseCase _sendMediaMessageUseCase;
  final GetChatHistoryUseCase _getChatHistoryUseCase;
  final MarkMessageReadUseCase _markMessageReadUseCase;
  final DeleteMessagesUseCase _deleteMessagesUseCase;
  final ChatRepository _chatRepository;
  final LocalDatabaseService _localDb;

  StreamSubscription<MessageEntity>? _incomingMessagesSub;
  StreamSubscription<Map<String, dynamic>>? _deliveredReceiptsSub;
  StreamSubscription<Map<String, dynamic>>? _readReceiptsSub;
  StreamSubscription<List<int>>? _messagesDeletedSub;
  StreamSubscription<Map<String, dynamic>>? _disappearingSub;
  Timer? _periodicPurgeTimer;
  int? _currentPeerId;

  ChatBloc({
    required SendMessageUseCase sendMessageUseCase,
    required SendMediaMessageUseCase sendMediaMessageUseCase,
    required GetChatHistoryUseCase getChatHistoryUseCase,
    required MarkMessageReadUseCase markMessageReadUseCase,
    required DeleteMessagesUseCase deleteMessagesUseCase,
    required ChatRepository chatRepository,
    required LocalDatabaseService localDb,
  })  : _sendMessageUseCase = sendMessageUseCase,
        _sendMediaMessageUseCase = sendMediaMessageUseCase,
        _getChatHistoryUseCase = getChatHistoryUseCase,
        _markMessageReadUseCase = markMessageReadUseCase,
        _deleteMessagesUseCase = deleteMessagesUseCase,
        _chatRepository = chatRepository,
        _localDb = localDb,
        super(const ChatState()) {
    on<LoadChatHistoryEvent>(_onLoadChatHistory);
    on<LoadMoreMessagesEvent>(_onLoadMoreMessages);
    on<SendMessageEvent>(_onSendMessage);
    on<SendMediaMessageEvent>(_onSendMediaMessage);
    on<MessageReceivedEvent>(_onMessageReceived);
    on<MessageDeliveredReceiptEvent>(_onMessageDeliveredReceipt);
    on<MessageReadReceiptEvent>(_onMessageReadReceipt);
    on<MarkConversationAsReadEvent>(_onMarkConversationAsRead);
    on<DeleteMessagesEvent>(_onDeleteMessages);
    on<MessagesDeletedRemotelyEvent>(_onMessagesDeletedRemotely);
    on<LoadDisappearingDurationEvent>(_onLoadDisappearingDuration);
    on<SetDisappearingDurationEvent>(_onSetDisappearingDuration);
    on<DisappearingDurationUpdatedRemoteEvent>(_onDisappearingDurationUpdatedRemote);
    on<PurgeExpiredMessagesEvent>(_onPurgeExpiredMessages);

    _listenToStreams();
  }

  void _listenToStreams() {
    _incomingMessagesSub = _chatRepository.incomingMessagesStream.listen((msg) {
      add(MessageReceivedEvent(msg));
    });

    _deliveredReceiptsSub = _chatRepository.messageDeliveredStream.listen((data) {
      final List idsRaw = data['message_ids'] ?? [];
      final ids = idsRaw
          .map((e) => (e is int ? e : int.tryParse(e.toString())))
          .whereType<int>()
          .toList();
      if (ids.isNotEmpty) {
        final deliveredAt = data['delivered_at'] != null ? DateTime.tryParse(data['delivered_at']) : null;
        add(MessageDeliveredReceiptEvent(messageIds: ids, deliveredAt: deliveredAt));
      }
    });

    _readReceiptsSub = _chatRepository.messageReadStream.listen((data) {
      final messageId = data['message_id'];
      if (messageId != null) {
        final id = messageId is int ? messageId : int.tryParse(messageId.toString());
        if (id != null) {
          final readAt = data['read_at'] != null ? DateTime.tryParse(data['read_at']) : null;
          add(MessageReadReceiptEvent(messageId: id, readAt: readAt));
        }
      }
    });

    _messagesDeletedSub = _chatRepository.messagesDeletedStream.listen((deletedIds) {
      add(MessagesDeletedRemotelyEvent(deletedIds));
    });

    _disappearingSub = _chatRepository.disappearingUpdatedStream.listen((data) {
      final peerId = data['peer_id'] as int?;
      final duration = data['disappearing_duration_seconds'] as int? ?? 0;
      if (peerId != null) {
        add(DisappearingDurationUpdatedRemoteEvent(
          peerId: peerId,
          durationSeconds: duration,
        ));
      }
    });

    _periodicPurgeTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => add(const PurgeExpiredMessagesEvent()),
    );
  }

  Future<void> _onLoadChatHistory(
    LoadChatHistoryEvent event,
    Emitter<ChatState> emit,
  ) async {
    _currentPeerId = event.peerId;
    emit(state.copyWith(status: ChatStatus.loading, hasMore: true));

    try {
      // Purge expired local messages and decrypted cache first
      await _localDb.purgeExpiredMessages();

      // Trigger disappearing settings load
      add(LoadDisappearingDurationEvent(event.peerId));

      final result = await _getChatHistoryUseCase(
        peerId: event.peerId,
        peerPublicKey: event.peerPublicKey,
        perPage: 50,
      );

      emit(state.copyWith(
        status: ChatStatus.loaded,
        messages: result.messages,
        hasMore: result.hasMore,
      ));

      // Mark all incoming messages from this peer as read
      add(MarkConversationAsReadEvent(event.peerId));
    } catch (e) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _onLoadMoreMessages(
    LoadMoreMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state.isLoadingMore || !state.hasMore || state.messages.isEmpty) return;

    emit(state.copyWith(isLoadingMore: true));

    try {
      final oldestId = state.messages.first.id;
      final result = await _getChatHistoryUseCase(
        peerId: event.peerId,
        peerPublicKey: event.peerPublicKey,
        beforeId: oldestId,
        perPage: 30,
      );

      final combined = List<MessageEntity>.from(result.messages)..addAll(state.messages);

      emit(state.copyWith(
        isLoadingMore: false,
        messages: combined,
        hasMore: result.hasMore,
      ));
    } catch (e) {
      AppLogger.e('Failed to load more messages', e);
      emit(state.copyWith(isLoadingMore: false));
    }
  }

  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (event.text.trim().isEmpty) return;

    final tempId = DateTime.now().millisecondsSinceEpoch;
    final optimisticMessage = MessageEntity(
      id: tempId,
      senderId: 0, // Current user
      receiverId: event.peerId,
      messageType: event.messageType,
      ciphertext: '',
      iv: '',
      mac: '',
      plaintext: event.text.trim(),
      replyToId: event.replyToId,
      replyPreview: event.replyPreview,
      createdAt: DateTime.now(),
      isSending: true,
    );

    final updatedList = List<MessageEntity>.from(state.messages)..add(optimisticMessage);
    emit(state.copyWith(messages: updatedList, isSending: true));

    try {
      final sentMessage = await _sendMessageUseCase(
        receiverId: event.peerId,
        peerPublicKey: event.peerPublicKey,
        plaintext: event.text.trim(),
        messageType: event.messageType,
        replyToId: event.replyToId,
        replyPreview: event.replyPreview,
      );

      final finalList = state.messages.map((m) {
        return m.id == tempId ? sentMessage : m;
      }).toList();

      emit(state.copyWith(messages: finalList, isSending: false));
    } catch (e) {
      final failedList = state.messages.map((m) {
        return m.id == tempId ? m.copyWith(isSending: false, hasFailed: true) : m;
      }).toList();

      emit(state.copyWith(
        messages: failedList,
        isSending: false,
        errorMessage: 'Failed to send encrypted message.',
      ));
    }
  }

  Future<void> _onSendMediaMessage(
    SendMediaMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    final tempId = DateTime.now().millisecondsSinceEpoch;

    String optimisticText = '[Sending Encrypted Image...]';
    if (event.messageType == 'video') {
      optimisticText = '[Sending Encrypted Video...]';
    } else if (event.messageType == 'audio') {
      optimisticText = '[Sending Voice Note...]';
    } else if (event.messageType == 'document') {
      optimisticText = event.fileName != null ? '[Document] ${event.fileName}' : '[Sending Document...]';
    }

    final optimisticMessage = MessageEntity(
      id: tempId,
      senderId: 0,
      receiverId: event.peerId,
      messageType: event.messageType,
      ciphertext: '',
      iv: '',
      mac: '',
      plaintext: optimisticText,
      fileName: event.fileName,
      fileSize: event.fileSize,
      replyToId: event.replyToId,
      replyPreview: event.replyPreview,
      createdAt: DateTime.now(),
      isSending: true,
    );

    final updated = List<MessageEntity>.from(state.messages)..add(optimisticMessage);
    emit(state.copyWith(messages: updated, isSending: true));

    try {
      final sentMessage = await _sendMediaMessageUseCase(
        receiverId: event.peerId,
        peerPublicKey: event.peerPublicKey,
        fileBytes: event.fileBytes as Uint8List,
        messageType: event.messageType,
        fileName: event.fileName,
        fileSize: event.fileSize,
        replyToId: event.replyToId,
        replyPreview: event.replyPreview,
      );

      final finalList = state.messages.map((m) {
        return m.id == tempId ? sentMessage : m;
      }).toList();

      emit(state.copyWith(messages: finalList, isSending: false));
    } catch (e) {
      final failedList = state.messages.map((m) {
        return m.id == tempId ? m.copyWith(isSending: false, hasFailed: true) : m;
      }).toList();

      emit(state.copyWith(
        messages: failedList,
        isSending: false,
        errorMessage: 'Failed to upload encrypted media.',
      ));
    }
  }

  void _onMessageReceived(
    MessageReceivedEvent event,
    Emitter<ChatState> emit,
  ) {
    if (_currentPeerId != null &&
        (event.message.senderId == _currentPeerId ||
            event.message.receiverId == _currentPeerId)) {
      // Avoid duplicate insertion
      if (state.messages.any((m) => m.id == event.message.id)) return;

      final updated = List<MessageEntity>.from(state.messages)..add(event.message);
      emit(state.copyWith(messages: updated));

      // If incoming from the active peer, mark read immediately
      if (event.message.senderId == _currentPeerId) {
        _markMessageReadUseCase(event.message.id);
      }
    }
  }

  void _onMessageDeliveredReceipt(
    MessageDeliveredReceiptEvent event,
    Emitter<ChatState> emit,
  ) {
    final idsSet = event.messageIds.toSet();
    final updated = state.messages.map((msg) {
      if (idsSet.contains(msg.id)) {
        return msg.copyWith(
          isDelivered: true,
          deliveredAt: event.deliveredAt ?? msg.deliveredAt ?? DateTime.now(),
        );
      }
      return msg;
    }).toList();

    emit(state.copyWith(messages: updated));
  }

  void _onMessageReadReceipt(
    MessageReadReceiptEvent event,
    Emitter<ChatState> emit,
  ) {
    final updated = state.messages.map((msg) {
      if (msg.id == event.messageId) {
        return msg.copyWith(
          isRead: true,
          isDelivered: true,
          readAt: event.readAt ?? DateTime.now(),
        );
      }
      return msg;
    }).toList();

    emit(state.copyWith(messages: updated));
  }

  Future<void> _onMarkConversationAsRead(
    MarkConversationAsReadEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _markMessageReadUseCase.markConversation(event.peerId);
    } catch (_) {}
  }

  Future<void> _onDeleteMessages(
    DeleteMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    final previousMessages = state.messages;
    final updated = state.messages.where((m) => !event.messageIds.contains(m.id)).toList();
    emit(state.copyWith(messages: updated));

    try {
      await _deleteMessagesUseCase(
        messageIds: event.messageIds,
        type: event.type,
      );
    } catch (e) {
      emit(state.copyWith(
        messages: previousMessages,
        errorMessage: 'Failed to delete messages.',
      ));
    }
  }

  void _onMessagesDeletedRemotely(
    MessagesDeletedRemotelyEvent event,
    Emitter<ChatState> emit,
  ) {
    final updated = state.messages.where((m) => !event.messageIds.contains(m.id)).toList();
    emit(state.copyWith(messages: updated));
  }

  Future<void> _onLoadDisappearingDuration(
    LoadDisappearingDurationEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final duration = await _chatRepository.getDisappearingDuration(event.peerId);
      emit(state.copyWith(disappearingDurationSeconds: duration));
    } catch (_) {}
  }

  Future<void> _onSetDisappearingDuration(
    SetDisappearingDurationEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(state.copyWith(isUpdatingDisappearing: true));
    try {
      final duration = await _chatRepository.setDisappearingDuration(
        event.peerId,
        event.durationSeconds,
      );
      emit(state.copyWith(
        disappearingDurationSeconds: duration,
        isUpdatingDisappearing: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isUpdatingDisappearing: false,
        errorMessage: 'Failed to update disappearing messages timer: $e',
      ));
    }
  }

  void _onDisappearingDurationUpdatedRemote(
    DisappearingDurationUpdatedRemoteEvent event,
    Emitter<ChatState> emit,
  ) {
    if (_currentPeerId == event.peerId) {
      emit(state.copyWith(disappearingDurationSeconds: event.durationSeconds));
    }
  }

  Future<void> _onPurgeExpiredMessages(
    PurgeExpiredMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    final now = DateTime.now().toUtc();
    final hasExpired = state.messages.any(
      (m) => m.expiresAt != null && m.expiresAt!.toUtc().isBefore(now),
    );

    if (hasExpired) {
      final filtered = state.messages
          .where((m) => m.expiresAt == null || m.expiresAt!.toUtc().isAfter(now))
          .toList();
      emit(state.copyWith(messages: filtered));
    }

    try {
      await _localDb.purgeExpiredMessages();
    } catch (_) {}
  }

  @override
  Future<void> close() {
    _incomingMessagesSub?.cancel();
    _deliveredReceiptsSub?.cancel();
    _readReceiptsSub?.cancel();
    _messagesDeletedSub?.cancel();
    _disappearingSub?.cancel();
    _periodicPurgeTimer?.cancel();
    return super.close();
  }
}
