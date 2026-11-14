import 'package:chatapp/core/storage/storage_manager_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageManagerService & StorageBreakdown Tests', () {
    test('formatBytes formats byte values accurately', () {
      expect(StorageBreakdown.formatBytes(0), '0 B');
      expect(StorageBreakdown.formatBytes(512), '512 B');
      expect(StorageBreakdown.formatBytes(1024), '1.0 KB');
      expect(StorageBreakdown.formatBytes(1536), '1.5 KB');
      expect(StorageBreakdown.formatBytes(1048576), '1.0 MB');
      expect(StorageBreakdown.formatBytes(52428800), '50.0 MB');
      expect(StorageBreakdown.formatBytes(1073741824), '1.0 GB');
    });

    test('StorageBreakdown correctly calculates mediaBytes and totalBytes', () {
      const breakdown = StorageBreakdown(
        imagesBytes: 10485760, // 10 MB
        videosBytes: 20971520, // 20 MB
        audioBytes: 5242880,   // 5 MB
        documentsBytes: 1048576, // 1 MB
        databaseBytes: 2097152,  // 2 MB
      );

      expect(breakdown.mediaBytes, 37748736); // 36 MB
      expect(breakdown.totalBytes, 39845888); // 38 MB
      expect(breakdown.imagesFormatted, '10.0 MB');
      expect(breakdown.videosFormatted, '20.0 MB');
      expect(breakdown.audioFormatted, '5.0 MB');
      expect(breakdown.documentsFormatted, '1.0 MB');
      expect(breakdown.databaseFormatted, '2.0 MB');
      expect(breakdown.mediaFormatted, '36.0 MB');
      expect(breakdown.totalFormatted, '38.0 MB');
    });
  });
}
