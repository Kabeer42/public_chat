import 'dart:io' as io;
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/app_logger.dart';

class CallAudioService {
  static const MethodChannel _ringtoneChannel = MethodChannel('com.chatapp.app/ringtone');

  AudioPlayer? _player;
  bool _isPlaying = false;
  bool _isNativeRingtonePlaying = false;

  CallAudioService([this._player]);

  AudioPlayer get player => _player ??= AudioPlayer();

  bool get isPlaying => _isPlaying;

  /// Start playing either incoming ringtone or outgoing ringback tone.
  Future<void> startRingtone({required bool isIncoming}) async {
    try {
      await stopRingtone();
      _isPlaying = true;

      // On Android devices, play actual system default ringtone for incoming calls
      if (isIncoming && !kIsWeb && io.Platform.isAndroid) {
        try {
          await _ringtoneChannel.invokeMethod('playRingtone');
          _isNativeRingtonePlaying = true;
          AppLogger.i('CallAudioService started native Android system ringtone');
          return;
        } catch (e) {
          AppLogger.w('Native ringtone failed, falling back to generated audio: $e');
        }
      }

      final wavBytes = isIncoming
          ? generateIncomingRingtoneWav()
          : generateOutgoingRingbackWav();

      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(BytesSource(wavBytes));
      AppLogger.i('CallAudioService started ringing (isIncoming: $isIncoming)');
    } catch (e) {
      _isPlaying = false;
      AppLogger.w('CallAudioService could not play ringtone (likely headless or uninitialized): $e');
    }
  }

  /// Stop playing ringtone immediately.
  Future<void> stopRingtone() async {
    _isPlaying = false;
    if (_isNativeRingtonePlaying && !kIsWeb && io.Platform.isAndroid) {
      try {
        await _ringtoneChannel.invokeMethod('stopRingtone');
      } catch (_) {}
      _isNativeRingtonePlaying = false;
    }

    if (_player != null) {
      try {
        await _player!.stop();
      } catch (_) {}
    }
  }

  /// Play an urgent busy / away buzzer sound (reorder tone).
  Future<void> playBuzzer() async {
    try {
      await stopRingtone();
      _isPlaying = true;
      final wavBytes = generateBuzzerWav();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(BytesSource(wavBytes));
      AppLogger.i('CallAudioService playing buzzer sound');
    } catch (e) {
      _isPlaying = false;
      AppLogger.w('CallAudioService failed to play buzzer: $e');
    }
  }

  /// Generate 1.2s busy / away buzzer sound (480Hz + 620Hz dual frequency buzzer).
  Uint8List generateBuzzerWav() {
    const int sampleRate = 22050;
    const double totalDuration = 1.2;
    final int totalSamples = (sampleRate * totalDuration).toInt();
    final int dataSize = totalSamples * 2;
    final int chunkSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final pcmBytes = Uint8List(dataSize);
    final pcmView = ByteData.view(pcmBytes.buffer);

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      final double cycle = t % 0.4;
      if (cycle < 0.28) {
        final double wave = 0.5 * math.sin(2 * math.pi * 480.0 * t) +
            0.5 * math.sin(2 * math.pi * 620.0 * t);
        final int sampleValue = (wave * 0.6 * 32767).toInt().clamp(-32768, 32767);
        pcmView.setInt16(i * 2, sampleValue, Endian.little);
      } else {
        pcmView.setInt16(i * 2, 0, Endian.little);
      }
    }

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataSize, pcmBytes);
    return out;
  }

  /// Release audio player resources.
  Future<void> dispose() async {
    await stopRingtone();
    if (_player != null) {
      try {
        await _player!.dispose();
      } catch (_) {}
      _player = null;
    }
  }

  /// Generate pleasant 3.0s looping incoming ringtone (C5 523Hz + E5 659Hz + G5 784Hz chime + silence).
  Uint8List generateIncomingRingtoneWav() {
    const int sampleRate = 22050;
    const double totalDuration = 3.0;
    const double activeDuration = 1.6;

    final int totalSamples = (sampleRate * totalDuration).toInt();
    final int activeSamples = (sampleRate * activeDuration).toInt();
    final int dataSize = totalSamples * 2; // 16-bit mono
    final int chunkSize = 36 + dataSize;

    final header = ByteData(44);
    // "RIFF"
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, chunkSize, Endian.little);
    // "WAVE"
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // "fmt "
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little); // PCM subchunk size
    header.setUint16(20, 1, Endian.little);  // Audio format 1 = PCM
    header.setUint16(22, 1, Endian.little);  // Mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    header.setUint16(32, 2, Endian.little);  // Block align
    header.setUint16(34, 16, Endian.little); // Bits per sample
    // "data"
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final pcmBytes = Uint8List(dataSize);
    final pcmView = ByteData.view(pcmBytes.buffer);

    for (int i = 0; i < totalSamples; i++) {
      if (i < activeSamples) {
        final double t = i / sampleRate;
        // Dual ring cadence: two pulses of 0.6s separated by 0.2s pause
        final double pulseTime = t % 0.8;
        double amplitude = 0.0;

        if (pulseTime < 0.6) {
          final double envelope = math.sin((pulseTime / 0.6) * math.pi);
          // Harmonic chime chord: C5 (523.25) + E5 (659.25) + G5 (783.99)
          final double wave = 0.4 * math.sin(2 * math.pi * 523.25 * t) +
              0.35 * math.sin(2 * math.pi * 659.25 * t) +
              0.25 * math.sin(2 * math.pi * 783.99 * t);
          amplitude = wave * envelope * 0.75;
        }

        final int sampleValue = (amplitude * 32767).toInt().clamp(-32768, 32767);
        pcmView.setInt16(i * 2, sampleValue, Endian.little);
      } else {
        pcmView.setInt16(i * 2, 0, Endian.little); // Silence between ring cycles
      }
    }

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataSize, pcmBytes);
    return out;
  }

  /// Generate standard 3.5s supervisory ringback tone (440Hz + 480Hz PBX ringback tone for caller).
  Uint8List generateOutgoingRingbackWav() {
    const int sampleRate = 22050;
    const double totalDuration = 3.5;
    const double activeDuration = 1.4;

    final int totalSamples = (sampleRate * totalDuration).toInt();
    final int activeSamples = (sampleRate * activeDuration).toInt();
    final int dataSize = totalSamples * 2;
    final int chunkSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6D);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final pcmBytes = Uint8List(dataSize);
    final pcmView = ByteData.view(pcmBytes.buffer);

    for (int i = 0; i < totalSamples; i++) {
      if (i < activeSamples) {
        final double t = i / sampleRate;
        final double wave = 0.5 * math.sin(2 * math.pi * 440.0 * t) +
            0.5 * math.sin(2 * math.pi * 480.0 * t);
        final int sampleValue = (wave * 0.5 * 32767).toInt().clamp(-32768, 32767);
        pcmView.setInt16(i * 2, sampleValue, Endian.little);
      } else {
        pcmView.setInt16(i * 2, 0, Endian.little);
      }
    }

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataSize, pcmBytes);
    return out;
  }
}
