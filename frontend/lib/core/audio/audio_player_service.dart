import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import '../utils/app_logger.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  String? _currentlyPlayingId;

  String? get currentlyPlayingId => _currentlyPlayingId;
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  Future<void> playBytes({required String id, required Uint8List bytes}) async {
    try {
      if (_currentlyPlayingId == id && _player.state == PlayerState.paused) {
        await _player.resume();
        return;
      }

      await _player.stop();
      _currentlyPlayingId = id;
      await _player.play(BytesSource(bytes));
      AppLogger.d('Playing audio note #$id (${bytes.length} bytes)');
    } catch (e) {
      AppLogger.e('Error playing audio note from bytes', e);
    }
  }

  Future<void> playFile({required String id, required String filePath}) async {
    try {
      if (_currentlyPlayingId == id && _player.state == PlayerState.paused) {
        await _player.resume();
        return;
      }

      await _player.stop();
      _currentlyPlayingId = id;
      await _player.play(DeviceFileSource(filePath));
      AppLogger.d('Playing audio note #$id from file: $filePath');
    } catch (e) {
      AppLogger.e('Error playing audio note from file', e);
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      AppLogger.w('Error pausing audio: $e');
    }
  }

  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (e) {
      AppLogger.w('Error resuming audio: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _currentlyPlayingId = null;
    } catch (e) {
      AppLogger.w('Error stopping audio: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      AppLogger.w('Error seeking audio: $e');
    }
  }

  Future<void> setPlaybackRate(double speed) async {
    try {
      await _player.setPlaybackRate(speed);
    } catch (e) {
      AppLogger.w('Error setting playback rate: $e');
    }
  }

  void dispose() {
    _player.dispose();
  }
}
