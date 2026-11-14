import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp/features/call/data/services/call_audio_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallAudioService Tests', () {
    late CallAudioService audioService;

    setUp(() {
      audioService = CallAudioService();
    });

    tearDown(() async {
      await audioService.dispose();
    });

    test('Initial state is not playing', () {
      expect(audioService.isPlaying, false);
    });

    test('generateIncomingRingtoneWav creates valid RIFF WAVE bytes', () {
      final wav = audioService.generateIncomingRingtoneWav();
      expect(wav.length, greaterThan(44));
      // "RIFF"
      expect(wav.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]);
      // "WAVE"
      expect(wav.sublist(8, 12), [0x57, 0x41, 0x56, 0x45]);
    });

    test('generateOutgoingRingbackWav creates valid RIFF WAVE bytes', () {
      final wav = audioService.generateOutgoingRingbackWav();
      expect(wav.length, greaterThan(44));
      // "RIFF"
      expect(wav.sublist(0, 4), [0x52, 0x49, 0x46, 0x46]);
      // "WAVE"
      expect(wav.sublist(8, 12), [0x57, 0x41, 0x56, 0x45]);
    });

    test('startRingtone and stopRingtone execute safely without uncaught errors', () async {
      await audioService.startRingtone(isIncoming: true);
      await audioService.startRingtone(isIncoming: false);
      await audioService.stopRingtone();
      expect(audioService.isPlaying, false);
    });

    test('dispose executes cleanly', () async {
      await audioService.dispose();
      expect(audioService.isPlaying, false);
    });
  });
}
