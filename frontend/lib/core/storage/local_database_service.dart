import 'dart:async';
import 'dart:io' as io;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../features/chat/domain/entities/message_entity.dart';
import '../utils/app_logger.dart';

class LocalDatabaseService {
  static const String _dbName = 'chatapp_local.db';
  static const int _dbVersion = 4;
  static const String tableMessages = 'local_messages';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = p.join(databasesPath, _dbName);

    AppLogger.i('Initializing Local SQLite Database at: $dbPath');

    return await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableMessages (
            id INTEGER PRIMARY KEY,
            conversation_peer_id INTEGER NOT NULL,
            sender_id INTEGER NOT NULL,
            receiver_id INTEGER NOT NULL,
            message_type TEXT NOT NULL,
            ciphertext TEXT NOT NULL,
            iv TEXT NOT NULL,
            mac TEXT NOT NULL,
            plaintext TEXT,
            media_url TEXT,
            encrypted_media_key TEXT,
            file_name TEXT,
            file_size INTEGER,
            local_file_path TEXT,
            reply_to_id INTEGER,
            reply_preview TEXT,
            is_delivered INTEGER DEFAULT 0,
            delivered_at TEXT,
            is_read INTEGER DEFAULT 0,
            read_at TEXT,
            expires_at TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_peer_id ON $tableMessages (conversation_peer_id)',
        );
        await db.execute(
          'CREATE INDEX idx_created_at ON $tableMessages (created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_expires_at ON $tableMessages (expires_at)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE $tableMessages ADD COLUMN file_name TEXT');
            await db.execute('ALTER TABLE $tableMessages ADD COLUMN file_size INTEGER');
          } catch (e) {
            AppLogger.w('Upgrade to v2 columns already present: $e');
          }
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE $tableMessages ADD COLUMN expires_at TEXT');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expires_at ON $tableMessages (expires_at)');
          } catch (e) {
            AppLogger.w('Upgrade to v3 columns already present: $e');
          }
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE $tableMessages ADD COLUMN delivered_at TEXT');
          } catch (e) {
            AppLogger.w('Upgrade to v4 columns already present: $e');
          }
        }
      },
    );
  }

  /// Insert or update a single decrypted message
  Future<void> insertOrUpdateMessage(MessageEntity message, {String? localFilePath}) async {
    final db = await database;
    final peerId = message.receiverId != 0 ? message.receiverId : message.senderId;

    final existing = await getMessageById(message.id);
    final savedFilePath = localFilePath ?? existing?.localFilePath;

    await db.insert(
      tableMessages,
      {
        'id': message.id,
        'conversation_peer_id': peerId,

        'sender_id': message.senderId,
        'receiver_id': message.receiverId,
        'message_type': message.messageType,
        'ciphertext': message.ciphertext,
        'iv': message.iv,
        'mac': message.mac,
        'plaintext': message.plaintext,
        'media_url': message.mediaUrl,
        'encrypted_media_key': message.encryptedMediaKey,
        'file_name': message.fileName,
        'file_size': message.fileSize,
        'local_file_path': savedFilePath,
        'reply_to_id': message.replyToId,
        'reply_preview': message.replyPreview,
        'is_delivered': message.isDelivered ? 1 : 0,
        'delivered_at': message.deliveredAt?.toIso8601String(),
        'is_read': message.isRead ? 1 : 0,
        'read_at': message.readAt?.toIso8601String(),
        'expires_at': message.expiresAt?.toIso8601String(),
        'created_at': message.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Batch insert or update messages for a conversation
  Future<void> insertOrUpdateMessages(int peerId, List<MessageEntity> messages) async {
    final db = await database;
    final batch = db.batch();

    for (final message in messages) {
      batch.insert(
        tableMessages,
        {
          'id': message.id,
          'conversation_peer_id': peerId,
          'sender_id': message.senderId,
          'receiver_id': message.receiverId,
          'message_type': message.messageType,
          'ciphertext': message.ciphertext,
          'iv': message.iv,
          'mac': message.mac,
          'plaintext': message.plaintext,
          'media_url': message.mediaUrl,
          'encrypted_media_key': message.encryptedMediaKey,
          'file_name': message.fileName,
          'file_size': message.fileSize,
          'local_file_path': message.localFilePath,
          'reply_to_id': message.replyToId,
          'reply_preview': message.replyPreview,
          'is_delivered': message.isDelivered ? 1 : 0,
          'delivered_at': message.deliveredAt?.toIso8601String(),
          'is_read': message.isRead ? 1 : 0,
          'read_at': message.readAt?.toIso8601String(),
          'expires_at': message.expiresAt?.toIso8601String(),
          'created_at': message.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get cached messages for a conversation peer sorted chronologically (excluding expired)
  Future<List<MessageEntity>> getMessagesForPeer(int peerId, {int limit = 100, int offset = 0}) async {
    final db = await database;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final results = await db.query(
      tableMessages,
      where:
          '(conversation_peer_id = ? OR sender_id = ? OR receiver_id = ?) AND (expires_at IS NULL OR expires_at > ?)',
      whereArgs: [peerId, peerId, peerId, nowIso],
      orderBy: 'created_at ASC',
      limit: limit,
      offset: offset,
    );

    return results.map(_rowToEntity).toList();
  }

  /// Get media messages by types for a conversation peer (excluding expired)
  Future<List<MessageEntity>> getMediaMessagesForPeer(
    int peerId, {
    required List<String> messageTypes,
    int limit = 200,
  }) async {
    final db = await database;
    final placeholders = List.filled(messageTypes.length, '?').join(',');
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final results = await db.query(
      tableMessages,
      where:
          '(conversation_peer_id = ? OR sender_id = ? OR receiver_id = ?) AND message_type IN ($placeholders) AND (expires_at IS NULL OR expires_at > ?)',
      whereArgs: [peerId, peerId, peerId, ...messageTypes, nowIso],
      orderBy: 'created_at DESC',
      limit: limit,
    );

    return results.map(_rowToEntity).toList();
  }

  /// Get single message by server ID
  Future<MessageEntity?> getMessageById(int id) async {
    final db = await database;
    final results = await db.query(
      tableMessages,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return _rowToEntity(results.first);
  }

  /// Update local file path for a media message
  Future<void> updateLocalFilePath(int messageId, String localFilePath) async {
    final db = await database;
    await db.update(
      tableMessages,
      {'local_file_path': localFilePath},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  /// Delete messages by IDs and return their local file paths for physical cleanup
  Future<List<String>> deleteMessagesByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;

    final inClause = ids.map((_) => '?').join(',');
    final rows = await db.query(
      tableMessages,
      columns: ['local_file_path'],
      where: 'id IN ($inClause)',
      whereArgs: ids,
    );

    final filePaths = rows
        .map((r) => r['local_file_path'] as String?)
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toList();

    await db.delete(
      tableMessages,
      where: 'id IN ($inClause)',
      whereArgs: ids,
    );

    AppLogger.d('Deleted ${ids.length} messages from local SQLite');
    return filePaths;
  }

  /// Reconcile server messages: if a local message for peerId is NOT in serverMessageIds,
  /// it means it was deleted on the server. Delete it locally and return file paths to purge.
  Future<List<String>> reconcileAndPurgeMissing(int peerId, List<int> serverMessageIds) async {
    if (serverMessageIds.isEmpty) return [];
    final db = await database;

    final inClause = serverMessageIds.map((_) => '?').join(',');
    final minId = serverMessageIds.reduce((a, b) => a < b ? a : b);
    final rows = await db.rawQuery('''
      SELECT local_file_path, id FROM $tableMessages
      WHERE (conversation_peer_id = ? OR sender_id = ? OR receiver_id = ?)
      AND id >= ?
      AND id NOT IN ($inClause)
    ''', [peerId, peerId, peerId, minId, ...serverMessageIds]);

    if (rows.isEmpty) return [];

    final purgedFilePaths = rows
        .map((r) => r['local_file_path'] as String?)
        .where((p) => p != null && p.isNotEmpty)
        .cast<String>()
        .toList();

    final purgedIds = rows.map((r) => r['id'] as int).toList();
    await deleteMessagesByIds(purgedIds);

    AppLogger.i('Reconciliation purged ${purgedIds.length} server-deleted messages from local SQLite');
    return purgedFilePaths;
  }

  /// Mark message delivered
  Future<void> markMessageAsDelivered(int id) async {
    final db = await database;
    await db.update(
      tableMessages,
      {'is_delivered': 1, 'delivered_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark multiple messages delivered
  Future<void> markMessagesAsDelivered(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final inClause = ids.map((_) => '?').join(',');
    await db.update(
      tableMessages,
      {'is_delivered': 1, 'delivered_at': DateTime.now().toIso8601String()},
      where: 'id IN ($inClause)',
      whereArgs: ids,
    );
  }

  /// Mark all messages in a conversation as delivered
  Future<void> markConversationAsDelivered(int peerId) async {
    final db = await database;
    await db.update(
      tableMessages,
      {'is_delivered': 1, 'delivered_at': DateTime.now().toIso8601String()},
      where: '(conversation_peer_id = ? OR sender_id = ?) AND is_delivered = 0',
      whereArgs: [peerId, peerId],
    );
  }

  /// Mark message read
  Future<void> markMessageAsRead(int id) async {
    final db = await database;
    await db.update(
      tableMessages,
      {'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark all messages in a conversation as read
  Future<void> markConversationAsRead(int peerId) async {
    final db = await database;
    await db.update(
      tableMessages,
      {'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: '(conversation_peer_id = ? OR sender_id = ?) AND is_read = 0',
      whereArgs: [peerId, peerId],
    );
  }

  /// Clear entire local messages database
  Future<void> clearAll() async {
    final db = await database;
    await db.delete(tableMessages);
    AppLogger.i('Cleared local_messages table');
  }

  MessageEntity _rowToEntity(Map<String, dynamic> row) {
    return MessageEntity(
      id: row['id'] as int,
      senderId: row['sender_id'] as int,
      receiverId: row['receiver_id'] as int,
      messageType: row['message_type'] as String,
      ciphertext: row['ciphertext'] as String,
      iv: row['iv'] as String,
      mac: row['mac'] as String,
      plaintext: row['plaintext'] as String?,
      mediaUrl: row['media_url'] as String?,
      encryptedMediaKey: row['encrypted_media_key'] as String?,
      fileName: row['file_name'] as String?,
      fileSize: row['file_size'] as int?,
      localFilePath: row['local_file_path'] as String?,
      replyToId: row['reply_to_id'] as int?,
      replyPreview: row['reply_preview'] as String?,
      isDelivered: (row['is_delivered'] as int? ?? 0) == 1,
      deliveredAt: row['delivered_at'] != null ? DateTime.tryParse(row['delivered_at'] as String) : null,
      isRead: (row['is_read'] as int? ?? 0) == 1,
      readAt: row['read_at'] != null ? DateTime.tryParse(row['read_at'] as String) : null,
      expiresAt: row['expires_at'] != null ? DateTime.tryParse(row['expires_at'] as String) : null,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  /// Purge expired disappearing messages from local SQLite and unlinks their decrypted media files
  Future<List<int>> purgeExpiredMessages() async {
    final db = await database;
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final expiredRows = await db.query(
      tableMessages,
      columns: ['id', 'local_file_path'],
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [nowIso],
    );

    if (expiredRows.isEmpty) return [];

    final expiredIds = <int>[];
    final filePathsToPurge = <String>[];

    for (final row in expiredRows) {
      expiredIds.add(row['id'] as int);
      final path = row['local_file_path'] as String?;
      if (path != null && path.isNotEmpty) {
        filePathsToPurge.add(path);
      }
    }

    final inClause = List.filled(expiredIds.length, '?').join(',');
    await db.delete(
      tableMessages,
      where: 'id IN ($inClause)',
      whereArgs: expiredIds,
    );

    // Physical cleanup of decrypted vault media
    for (final path in filePathsToPurge) {
      try {
        final file = io.File(path);
        if (await file.exists()) {
          await file.delete();
          AppLogger.d('Purged decrypted vault media: $path');
        }
      } catch (e) {
        AppLogger.e('Error purging decrypted vault media $path: $e');
      }
    }

    AppLogger.i('Purged ${expiredIds.length} expired disappearing messages locally');
    return expiredIds;
  }
}
