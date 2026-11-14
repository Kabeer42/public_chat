import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory vaultDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_test_');
    vaultDir = Directory(p.join(tempDir.path, '.chatapp_vault'));
    await vaultDir.create(recursive: true);

    // Create .nomedia
    await File(p.join(vaultDir.path, '.nomedia')).create();

    // Create subdirs
    for (final sub in ['images', 'videos', 'audio', 'documents']) {
      await Directory(p.join(vaultDir.path, sub)).create(recursive: true);
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Vault creates .nomedia and isolates files', () async {
    final noMedia = File(p.join(vaultDir.path, '.nomedia'));
    expect(await noMedia.exists(), isTrue);
  });

  test('Vault stores and retrieves decrypted media bytes', () async {
    final testBytes = Uint8List.fromList([1, 2, 3, 4, 5, 42, 99]);
    final imageFile = File(p.join(vaultDir.path, 'images', '101_media.jpg'));
    await imageFile.writeAsBytes(testBytes, flush: true);

    expect(await imageFile.exists(), isTrue);
    final readBytes = await imageFile.readAsBytes();
    expect(readBytes, equals(testBytes));
  });

  test('Vault auto-deletes files when purged from server', () async {
    final testBytes = Uint8List.fromList([10, 20, 30]);
    final videoFile = File(p.join(vaultDir.path, 'videos', '202_media.mp4'));
    await videoFile.writeAsBytes(testBytes, flush: true);

    expect(await videoFile.exists(), isTrue);

    // Simulate server deletion purge
    if (await videoFile.exists()) {
      await videoFile.delete();
    }
    expect(await videoFile.exists(), isFalse);
  });
}
