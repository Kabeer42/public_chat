import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../../../../core/crypto/e2ee_manager.dart';
import '../../../../core/crypto/models/encrypted_payload.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../../core/storage/local_database_service.dart';
import '../../../../core/storage/local_vault_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_datasource.dart';
import '../models/message_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource _remoteDataSource;
  final E2eeManager _e2eeManager;
  final WebSocketService _webSocketService;
  final LocalDatabaseService _localDb;
  final LocalVaultService _localVault;

  // Local in-memory cache to prevent re-decrypting messages repeatedly in the current session
  final Map<int, String> _decryptedPlaintextCache = {};
  final Map<int, Uint8List> _decryptedMediaCache = {};
  final Map<int, String> _peerPublicKeyCache = {};

  final _incomingMessagesController = StreamController<MessageEntity>.broadcast();
  final _messageDeliveredController = StreamController<Map<String, dynamic>>.broadcast();
  final _messageReadController = StreamController<Map<String, dynamic>>.broadcast();
  final _messagesDeletedController = StreamController<List<int>>.broadcast();
  final _disappearingUpdatedController = StreamController<Map<String, dynamic>>.broadcast();

  ChatRepositoryImpl({
    required ChatRemoteDataSource remoteDataSource,
    required E2eeManager e2eeManager,
    required WebSocketService webSocketService,
    required LocalDatabaseService localDb,
    required LocalVaultService localVault,
  })  : _remoteDataSource = remoteDataSource,
        _e2eeManager = e2eeManager,
        _webSocketService = webSocketService,
        _localDb = localDb,
        _localVault = localVault {
    _listenToWebSocket();
  }

  Future<String> _resolvePeerPublicKey(int peerId, [String? candidateKey]) async {
    if (candidateKey != null && candidateKey.trim().isNotEmpty) {
      final key = candidateKey.trim();
      _peerPublicKeyCache[peerId] = key;
      return key;
    }
    if (_peerPublicKeyCache.containsKey(peerId) && _peerPublicKeyCache[peerId]!.isNotEmpty) {
      return _peerPublicKeyCache[peerId]!;
    }
    try {
      final fetched = await _remoteDataSource.getPublicKey(peerId);
      if (fetched != null && fetched.trim().isNotEmpty) {
        final key = fetched.trim();
        _peerPublicKeyCache[peerId] = key;
        return key;
      }
    } catch (e) {
      AppLogger.w('Failed to fetch public key for peer #$peerId: $e');
    }
    return '';
  }

  void _listenToWebSocket() {
    _webSocketService.eventStream.listen((eventData) async {
      try {
        final event = eventData['event'] as String?;
        final rawData = eventData['data'];

        if (event == 'message.deleted') {
          if (rawData is Map<String, dynamic>) {
            final List idsRaw = rawData['message_ids'] ?? [];
            final ids = idsRaw
                .map((e) => (e is int ? e : int.tryParse(e.toString())))
                .whereType<int>()
                .toList();
            if (ids.isNotEmpty) {
              for (final id in ids) {
                _decryptedPlaintextCache.remove(id);
                _decryptedMediaCache.remove(id);
              }
              // Delete from local SQLite database and physical vault
              final filePaths = await _localDb.deleteMessagesByIds(ids);
              await _localVault.deleteFiles(filePaths);

              _messagesDeletedController.add(ids);
            }
          }
        } else if (event == 'message.sent') {
          final messageJson = rawData is Map<String, dynamic>
              ? (rawData['message'] ?? rawData)
              : null;

          if (messageJson != null && messageJson is Map<String, dynamic>) {
            final model = MessageModel.fromJson(messageJson);

            // Attempt to decrypt incoming message
            String? decryptedText;
            try {
              final payload = EncryptedPayload(
                ciphertext: model.ciphertext,
                iv: model.iv,
                mac: model.mac,
              );

              final peerPublicKey = await _resolvePeerPublicKey(
                model.senderId,
                model.senderPublicKey,
              );

              if (peerPublicKey.isNotEmpty) {
                decryptedText = await _e2eeManager.cipherService.decryptText(
                  payload: payload,
                  secretKey: await _e2eeManager.keyExchangeService.getSessionKeyForPeer(
                    peerId: model.senderId,
                    peerPublicKeyBase64: peerPublicKey,
                  ),
                );
              }
            } catch (e) {
              if (model.messageType == 'audio') {
                decryptedText = '[Voice Note]';
              } else if (model.messageType == 'document') {
                decryptedText = model.fileName != null ? '[Document] ${model.fileName}' : '[Document]';
              } else if (model.messageType == 'image') {
                decryptedText = '[Encrypted Image]';
              } else if (model.messageType == 'video') {
                decryptedText = '[Encrypted Video]';
              } else if (model.messageType == 'contact') {
                decryptedText = '[Contact Card]';
              } else {
                AppLogger.w('Could not immediately decrypt incoming message #${model.id}: $e');
                decryptedText = null;
              }
            }

            if (decryptedText != null) {
              _decryptedPlaintextCache[model.id] = decryptedText;
            }

            final entity = model.copyWith(plaintext: decryptedText);

            // Save incoming message in local persistent SQLite database
            await _localDb.insertOrUpdateMessage(entity);

            _incomingMessagesController.add(entity);

            // Acknowledge delivery to backend so sender receives double grey tick
            unawaited(_remoteDataSource.markAsDelivered(model.id).catchError((_) => false));
          }
        } else if (event == 'message.delivered') {
          if (rawData is Map<String, dynamic>) {
            final List idsRaw = rawData['message_ids'] ?? [];
            final ids = idsRaw
                .map((e) => (e is int ? e : int.tryParse(e.toString())))
                .whereType<int>()
                .toList();
            if (ids.isNotEmpty) {
              await _localDb.markMessagesAsDelivered(ids);
            }
            _messageDeliveredController.add(rawData);
          }
        } else if (event == 'message.read') {
          if (rawData is Map<String, dynamic>) {
            final messageId = rawData['message_id'] as int?;
            if (messageId != null) {
              await _localDb.markMessageAsRead(messageId);
            }
            _messageReadController.add(rawData);
          }
        } else if (event == 'conversation.disappearing_updated') {
          if (rawData is Map<String, dynamic>) {
            _disappearingUpdatedController.add(rawData);
          }
        }
      } catch (e) {
        AppLogger.e('Error processing WebSocket chat event', e);
      }
    });
  }

  @override
  Stream<MessageEntity> get incomingMessagesStream =>
      _incomingMessagesController.stream;

  @override
  Stream<Map<String, dynamic>> get messageDeliveredStream =>
      _messageDeliveredController.stream;

  @override
  Stream<Map<String, dynamic>> get messageReadStream =>
      _messageReadController.stream;

  @override
  Stream<List<int>> get messagesDeletedStream =>
      _messagesDeletedController.stream;

  @override
  Stream<Map<String, dynamic>> get disappearingUpdatedStream =>
      _disappearingUpdatedController.stream;

  @override
  Future<int> getDisappearingDuration(int peerId) {
    return _remoteDataSource.getDisappearingDuration(peerId);
  }

  @override
  Future<int> setDisappearingDuration(int peerId, int durationSeconds) {
    return _remoteDataSource.setDisappearingDuration(peerId, durationSeconds);
  }

  @override
  Future<MessageEntity> sendMessage({
    required int receiverId,
    required String peerPublicKey,
    required String plaintext,
    String messageType = 'text',
    String? mediaUrl,
    String? encryptedMediaKey,
    int? replyToId,
    String? replyPreview,
  }) async {
    final resolvedKey = await _resolvePeerPublicKey(receiverId, peerPublicKey);

    // 1. Encrypt message locally using recipient's public key & X25519/AES-256-GCM
    final encryptedPayload = await _e2eeManager.encryptMessage(
      peerId: receiverId,
      peerPublicKeyBase64: resolvedKey,
      plaintext: plaintext,
    );

    // 2. Transmit only ciphertext and crypto metadata to backend (Zero-Knowledge)
    final sentModel = await _remoteDataSource.sendMessage({
      'receiver_id': receiverId,
      'message_type': messageType,
      'ciphertext': encryptedPayload.ciphertext,
      'iv': encryptedPayload.iv,
      'mac': encryptedPayload.mac,
      'media_url': mediaUrl,
      'encrypted_media_key': encryptedMediaKey,
      'reply_to_id': replyToId,
      'reply_preview': replyPreview,
    });

    // 3. Cache the plaintext locally on sender device and save to SQLite
    _decryptedPlaintextCache[sentModel.id] = plaintext;
    final entityWithPlaintext = sentModel.copyWith(plaintext: plaintext);
    await _localDb.insertOrUpdateMessage(entityWithPlaintext);

    return entityWithPlaintext;
  }

  @override
  @override
  Future<({List<MessageEntity> messages, bool hasMore})> getChatHistory({
    required int peerId,
    required String peerPublicKey,
    int? beforeId,
    int page = 1,
    int perPage = 50,
  }) async {
    final resolvedPeerKey = await _resolvePeerPublicKey(peerId, peerPublicKey);

    // 1. Fetch remote messages from backend
    final remoteResult = await _remoteDataSource.getMessages(
      peerId,
      beforeId: beforeId,
      page: page,
      perPage: perPage,
    );
    final remoteModels = remoteResult.messages;
    final hasMore = remoteResult.hasMore;

    // 2. Server Deletion Reconciliation:
    // Only reconcile on initial page (beforeId == null && page == 1)
    final serverIds = remoteModels.map((m) => m.id).toList();
    if (beforeId == null && page == 1 && serverIds.isNotEmpty) {
      final purgedFiles = await _localDb.reconcileAndPurgeMissing(peerId, serverIds);
      await _localVault.deleteFiles(purgedFiles);
      // Acknowledge delivery of peer messages to backend so sender receives double ticks
      unawaited(_remoteDataSource.markConversationAsDelivered(peerId).catchError((_) => 0));
    }

    final List<MessageEntity> decryptedList = [];

    for (final model in remoteModels) {
      // Check memory cache first
      if (_decryptedPlaintextCache.containsKey(model.id)) {
        final localExisting = await _localDb.getMessageById(model.id);
        decryptedList.add(model.copyWith(
          plaintext: _decryptedPlaintextCache[model.id],
          localFilePath: localExisting?.localFilePath,
        ));
        continue;
      }

      // Check SQLite persistent storage second
      final localExisting = await _localDb.getMessageById(model.id);
      if (localExisting != null &&
          localExisting.plaintext != null &&
          localExisting.plaintext != '[Encrypted Message]' &&
          localExisting.plaintext != '[Encrypted Payload]') {
        _decryptedPlaintextCache[model.id] = localExisting.plaintext!;
        decryptedList.add(model.copyWith(
          plaintext: localExisting.plaintext,
          localFilePath: localExisting.localFilePath,
        ));
        continue;
      }

      // Decrypt message using E2EE session key
      String? decryptedText;
      try {
        final payload = EncryptedPayload(
          ciphertext: model.ciphertext,
          iv: model.iv,
          mac: model.mac,
        );

        final keyToUse = (model.senderId == peerId &&
                model.senderPublicKey != null &&
                model.senderPublicKey!.isNotEmpty)
            ? model.senderPublicKey!
            : resolvedPeerKey;

        decryptedText = await _e2eeManager.decryptMessage(
          peerId: peerId,
          peerPublicKeyBase64: keyToUse,
          payload: payload,
        );
      } catch (e) {
        AppLogger.w('Decryption failed for message #${model.id}: $e');
        decryptedText = null;
      }

      // If message cannot be decrypted (e.g. user reset keys after forgotten PIN),
      // omit it so broken encrypted placeholders are not shown.
      if (decryptedText == null) {
        continue;
      }

      _decryptedPlaintextCache[model.id] = decryptedText;

      final entity = model.copyWith(
        plaintext: decryptedText,
        localFilePath: localExisting?.localFilePath,
      );

      // Persist decrypted message into local SQLite database
      await _localDb.insertOrUpdateMessage(entity);

      decryptedList.add(entity);
    }

    return (messages: decryptedList, hasMore: hasMore);
  }

  @override
  Future<MessageEntity> sendMediaMessage({
    required int receiverId,
    required String peerPublicKey,
    required Uint8List fileBytes,
    required String messageType,
    String? fileName,
    int? fileSize,
    int? replyToId,
    String? replyPreview,
  }) async {
    final resolvedKey = await _resolvePeerPublicKey(receiverId, peerPublicKey);

    // 1. Encrypt file with one-time AES key and wrap the key for peer
    final encryptedMedia = await _e2eeManager.encryptMediaForPeer(
      peerId: receiverId,
      peerPublicKeyBase64: resolvedKey,
      fileBytes: fileBytes,
    );

    final encryptedBytes = encryptedMedia['encryptedBytes'] as Uint8List;
    final wrappedKeyPayload = encryptedMedia['wrappedKeyPayload'] as EncryptedPayload;
    final fileIv = encryptedMedia['fileIv'] as String;
    final fileMac = encryptedMedia['fileMac'] as String;

    // 2. Upload ciphertext bytes to backend
    final mediaResult = await _remoteDataSource.uploadEncryptedMedia(encryptedBytes);
    final mediaUrl = mediaResult['url'] as String;

    // 3. Send message payload with encrypted media key & ciphertext
    final sentModel = await _remoteDataSource.sendMessage({
      'receiver_id': receiverId,
      'message_type': messageType,
      'ciphertext': wrappedKeyPayload.ciphertext,
      'iv': fileIv,
      'mac': fileMac,
      'media_url': mediaUrl,
      'encrypted_media_key': jsonEncode(wrappedKeyPayload.toJson()),
      'file_name': fileName,
      'file_size': fileSize ?? fileBytes.length,
      'reply_to_id': replyToId,
      'reply_preview': replyPreview,
    });

    // 4. Save decrypted media locally into the hidden sandboxed vault
    String category = 'images';
    String ext = 'jpg';
    String fallbackPlaintext = '[Encrypted Image]';

    if (messageType == 'video') {
      category = 'videos';
      ext = 'mp4';
      fallbackPlaintext = '[Encrypted Video]';
    } else if (messageType == 'audio') {
      category = 'audio';
      ext = 'm4a';
      fallbackPlaintext = '[Voice Note]';
    } else if (messageType == 'document') {
      category = 'documents';
      ext = fileName != null && fileName.contains('.') ? fileName.split('.').last : 'bin';
      fallbackPlaintext = fileName != null ? '[Document] $fileName' : '[Document]';
    }

    final localPath = await _localVault.saveMediaFile(
      category: category,
      fileName: fileName ?? '${sentModel.id}_media.$ext',
      bytes: fileBytes,
    );

    // 5. Cache decrypted media in memory and local SQLite
    _decryptedMediaCache[sentModel.id] = fileBytes;

    final entity = sentModel.copyWith(
      plaintext: fallbackPlaintext,
      fileName: fileName,
      fileSize: fileSize ?? fileBytes.length,
      localFilePath: localPath,
    );

    await _localDb.insertOrUpdateMessage(entity, localFilePath: localPath);

    return entity;
  }

  @override
  Future<Uint8List> downloadAndDecryptMedia({
    required int peerId,
    required String peerPublicKey,
    required MessageEntity message,
  }) async {
    // Check in-memory cache first
    if (_decryptedMediaCache.containsKey(message.id)) {
      return _decryptedMediaCache[message.id]!;
    }

    // Check persistent sandboxed vault on device
    if (message.localFilePath != null) {
      final cachedBytes = await _localVault.getMediaBytes(message.localFilePath);
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        _decryptedMediaCache[message.id] = cachedBytes;
        return cachedBytes;
      }
    }

    // Also check standard vault path if localFilePath was not populated on entity
    String category = 'images';
    String ext = 'jpg';
    if (message.messageType == 'video') {
      category = 'videos';
      ext = 'mp4';
    } else if (message.messageType == 'audio') {
      category = 'audio';
      ext = 'm4a';
    } else if (message.messageType == 'document') {
      category = 'documents';
      ext = message.fileName != null && message.fileName!.contains('.')
          ? message.fileName!.split('.').last
          : 'bin';
    }
    final standardFileName = message.fileName ?? '${message.id}_media.$ext';

    final localRecord = await _localDb.getMessageById(message.id);
    if (localRecord?.localFilePath != null) {
      final cachedBytes = await _localVault.getMediaBytes(localRecord!.localFilePath);
      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        _decryptedMediaCache[message.id] = cachedBytes;
        return cachedBytes;
      }
    }

    if (message.mediaUrl == null || message.encryptedMediaKey == null) {
      throw Exception('Message does not contain media payload or encrypted key.');
    }

    // 1. Download encrypted ciphertext bytes from backend
    final encryptedBytes = await _remoteDataSource.downloadEncryptedMedia(message.mediaUrl!);

    // 2. Parse wrapped key payload
    final keyJson = jsonDecode(message.encryptedMediaKey!) as Map<String, dynamic>;
    final wrappedKeyPayload = EncryptedPayload.fromJson(keyJson);

    // 3. Decrypt media bytes using recovered one-time key
    final keyToUse = (message.senderId == peerId &&
            message.senderPublicKey != null &&
            message.senderPublicKey!.isNotEmpty)
        ? message.senderPublicKey!
        : peerPublicKey;
    final resolvedKey = await _resolvePeerPublicKey(peerId, keyToUse);

    Uint8List decryptedBytes;
    try {
      decryptedBytes = await _e2eeManager.decryptMediaFromPeer(
        peerId: peerId,
        peerPublicKeyBase64: resolvedKey,
        encryptedBytes: encryptedBytes,
        wrappedKeyPayload: wrappedKeyPayload,
        fileIv: message.iv,
        fileMac: message.mac,
      );
    } catch (e) {
      // If decryption failed (e.g. outdated peer key cache), re-fetch latest key from backend and retry
      final freshKey = await _remoteDataSource.getPublicKey(peerId);
      if (freshKey != null && freshKey.trim().isNotEmpty && freshKey.trim() != resolvedKey) {
        final newResolvedKey = freshKey.trim();
        _peerPublicKeyCache[peerId] = newResolvedKey;
        decryptedBytes = await _e2eeManager.decryptMediaFromPeer(
          peerId: peerId,
          peerPublicKeyBase64: newResolvedKey,
          encryptedBytes: encryptedBytes,
          wrappedKeyPayload: wrappedKeyPayload,
          fileIv: message.iv,
          fileMac: message.mac,
        );
      } else {
        rethrow;
      }
    }

    // 4. Save decrypted media into sandboxed local vault
    final savedPath = await _localVault.saveMediaFile(
      category: category,
      fileName: standardFileName,
      bytes: decryptedBytes,
    );

    // 5. Update local SQLite database record with local file path
    await _localDb.updateLocalFilePath(message.id, savedPath);

    _decryptedMediaCache[message.id] = decryptedBytes;
    return decryptedBytes;
  }

  @override
  Future<bool> markAsRead(int messageId) async {
    final result = await _remoteDataSource.markAsRead(messageId);
    if (result) {
      await _localDb.markMessageAsRead(messageId);
    }
    return result;
  }

  @override
  Future<int> markConversationAsRead(int peerId) async {
    final count = await _remoteDataSource.markConversationAsRead(peerId);
    await _localDb.markConversationAsRead(peerId);
    return count;
  }

  @override
  Future<List<int>> deleteMessages({
    required List<int> messageIds,
    required String type,
  }) async {
    final deleted = await _remoteDataSource.deleteMessages(
      messageIds: messageIds,
      type: type,
    );

    for (final id in deleted) {
      _decryptedPlaintextCache.remove(id);
      _decryptedMediaCache.remove(id);
    }

    // Hard-delete from local SQLite and wipe physical media files from vault
    final filePaths = await _localDb.deleteMessagesByIds(deleted);
    await _localVault.deleteFiles(filePaths);

    return deleted;
  }

  @override
  Future<bool> markAsDelivered(int messageId) async {
    final result = await _remoteDataSource.markAsDelivered(messageId);
    if (result) {
      await _localDb.markMessageAsDelivered(messageId);
    }
    return result;
  }

  @override
  Future<int> markConversationAsDelivered(int peerId) async {
    final count = await _remoteDataSource.markConversationAsDelivered(peerId);
    await _localDb.markConversationAsDelivered(peerId);
    return count;
  }

  void dispose() {
    _incomingMessagesController.close();
    _messageDeliveredController.close();
    _messageReadController.close();
    _messagesDeletedController.close();
    _disappearingUpdatedController.close();
  }
}
