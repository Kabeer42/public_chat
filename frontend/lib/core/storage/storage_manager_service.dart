import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../utils/app_logger.dart';
import 'local_database_service.dart';

class StorageBreakdown {
  final int imagesBytes;
  final int videosBytes;
  final int audioBytes;
  final int documentsBytes;
  final int databaseBytes;

  const StorageBreakdown({
    this.imagesBytes = 0,
    this.videosBytes = 0,
    this.audioBytes = 0,
    this.documentsBytes = 0,
    this.databaseBytes = 0,
  });

  int get mediaBytes => imagesBytes + videosBytes + audioBytes + documentsBytes;
  int get totalBytes => mediaBytes + databaseBytes;

  String get imagesFormatted => formatBytes(imagesBytes);
  String get videosFormatted => formatBytes(videosBytes);
  String get audioFormatted => formatBytes(audioBytes);
  String get documentsFormatted => formatBytes(documentsBytes);
  String get databaseFormatted => formatBytes(databaseBytes);
  String get mediaFormatted => formatBytes(mediaBytes);
  String get totalFormatted => formatBytes(totalBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
}

class StorageManagerService {
  final LocalDatabaseService _localDb;

  StorageManagerService({
    required LocalDatabaseService localDb,
  }) : _localDb = localDb;

  /// Inspect storage usage across all vault media categories and SQLite database
  Future<StorageBreakdown> getStorageBreakdown() async {
    int imagesBytes = 0;
    int videosBytes = 0;
    int audioBytes = 0;
    int documentsBytes = 0;
    int databaseBytes = 0;

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(appDocDir.path, '.chatapp_vault'));

      if (await vaultDir.exists()) {
        imagesBytes = await _calculateDirSize(Directory(p.join(vaultDir.path, 'images')));
        videosBytes = await _calculateDirSize(Directory(p.join(vaultDir.path, 'videos')));
        audioBytes = await _calculateDirSize(Directory(p.join(vaultDir.path, 'audio')));
        documentsBytes = await _calculateDirSize(Directory(p.join(vaultDir.path, 'documents')));
      }

      // SQLite database size
      final dbPath = p.join(await getDatabasesPath(), 'chatapp_local.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        databaseBytes = await dbFile.length();
      }
    } catch (e) {
      AppLogger.e('Error calculating storage breakdown: $e');
    }

    return StorageBreakdown(
      imagesBytes: imagesBytes,
      videosBytes: videosBytes,
      audioBytes: audioBytes,
      documentsBytes: documentsBytes,
      databaseBytes: databaseBytes,
    );
  }

  /// Delete cached decrypted media files in vault to free up device space
  /// Retains text chat message history in SQLite
  Future<int> clearMediaCache() async {
    int bytesFreed = 0;
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(appDocDir.path, '.chatapp_vault'));

      if (await vaultDir.exists()) {
        for (final sub in ['images', 'videos', 'audio', 'documents']) {
          final subDir = Directory(p.join(vaultDir.path, sub));
          if (await subDir.exists()) {
            final entities = subDir.listSync(recursive: true);
            for (final entity in entities) {
              if (entity is File && !entity.path.endsWith('.nomedia')) {
                final len = await entity.length();
                await entity.delete();
                bytesFreed += len;
              }
            }
          }
        }
      }

      // Nullify local_file_path references in SQLite so future taps re-download seamlessly
      final db = await _localDb.database;
      await db.update(
        LocalDatabaseService.tableMessages,
        {'local_file_path': null},
      );

      AppLogger.i('Cleared media cache: freed ${StorageBreakdown.formatBytes(bytesFreed)}');
    } catch (e) {
      AppLogger.e('Error clearing media cache: $e');
    }
    return bytesFreed;
  }

  Future<int> _calculateDirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int size = 0;
    try {
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is File && !entity.path.endsWith('.nomedia')) {
          size += await entity.length();
        }
      }
    } catch (e) {
      AppLogger.w('Failed to calculate size for ${dir.path}: $e');
    }
    return size;
  }
}
