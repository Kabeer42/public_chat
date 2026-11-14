import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';

class LocalVaultService {
  Directory? _vaultDir;

  Future<void> initialize() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      _vaultDir = Directory(p.join(appDocDir.path, '.chatapp_vault'));

      if (!await _vaultDir!.exists()) {
        await _vaultDir!.create(recursive: true);
      }

      // Create .nomedia file so Android media scanner completely ignores this directory
      final noMediaFile = File(p.join(_vaultDir!.path, '.nomedia'));
      if (!await noMediaFile.exists()) {
        await noMediaFile.create();
      }

      // Ensure subdirectories exist
      for (final sub in ['images', 'videos', 'audio', 'documents']) {
        final subDir = Directory(p.join(_vaultDir!.path, sub));
        if (!await subDir.exists()) {
          await subDir.create(recursive: true);
        }
      }

      AppLogger.i('LocalVaultService initialized at: ${_vaultDir!.path}');
    } catch (e) {
      AppLogger.e('Failed to initialize LocalVaultService', e);
    }
  }

  Future<Directory> _getVaultDir() async {
    if (_vaultDir == null) {
      await initialize();
    }
    return _vaultDir!;
  }

  /// Save raw decrypted media bytes into the sandboxed vault and return absolute file path
  Future<String> saveMediaFile({
    required String category,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final vault = await _getVaultDir();
    final targetDir = Directory(p.join(vault.path, category));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final filePath = p.join(targetDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    AppLogger.d('Saved decrypted media in vault: $filePath (${bytes.length} bytes)');
    return filePath;
  }

  /// Check if file exists in vault
  Future<bool> fileExists(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return false;
    final file = File(filePath);
    return await file.exists();
  }

  /// Read decrypted bytes from local file path
  Future<Uint8List?> getMediaBytes(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return null;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      AppLogger.w('Could not read media file $filePath: $e');
    }
    return null;
  }

  /// Delete a specific media file from the vault
  Future<bool> deleteFile(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return false;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        AppLogger.d('Deleted local vault file: $filePath');
        return true;
      }
    } catch (e) {
      AppLogger.w('Failed to delete vault file $filePath: $e');
    }
    return false;
  }

  /// Delete multiple media files
  Future<void> deleteFiles(List<String?> filePaths) async {
    for (final path in filePaths) {
      await deleteFile(path);
    }
  }

  /// Completely wipe the local vault (e.g. on user logout)
  Future<void> clearVault() async {
    try {
      if (_vaultDir != null && await _vaultDir!.exists()) {
        final entities = _vaultDir!.listSync();
        for (final entity in entities) {
          if (p.basename(entity.path) == '.nomedia') continue;
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        }
        AppLogger.i('Local vault cleared successfully');
      }
    } catch (e) {
      AppLogger.e('Error clearing local vault', e);
    }
  }
}
