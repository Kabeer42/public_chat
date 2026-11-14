import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../utils/app_logger.dart';

class VoiceRecordService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  DateTime? _lastResumeTime;
  Duration _accumulatedDuration = Duration.zero;
  bool _isPaused = false;
  Timer? _durationTimer;
  final _durationController = StreamController<Duration>.broadcast();

  Stream<Duration> get durationStream => _durationController.stream;
  bool get isPaused => _isPaused;

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }

  /// Start recording voice message to temporary m4a file
  Future<bool> startRecording() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        AppLogger.w('Microphone permission denied for voice recording');
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = 'voice_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = p.join(tempDir.path, fileName);

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _recordingStartTime = DateTime.now();
      _lastResumeTime = _recordingStartTime;
      _accumulatedDuration = Duration.zero;
      _isPaused = false;

      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!_isPaused && _lastResumeTime != null) {
          final elapsed = _accumulatedDuration + DateTime.now().difference(_lastResumeTime!);
          _durationController.add(elapsed);
        }
      });

      AppLogger.i('Voice recording started at: $_currentRecordingPath');
      return true;
    } catch (e) {
      AppLogger.e('Error starting voice recording', e);
      return false;
    }
  }

  /// Pause current recording session
  Future<void> pauseRecording() async {
    try {
      if (_isPaused) return;
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.pause();
        if (_lastResumeTime != null) {
          _accumulatedDuration += DateTime.now().difference(_lastResumeTime!);
        }
        _isPaused = true;
        _durationController.add(_accumulatedDuration);
        AppLogger.i('Voice recording paused');
      }
    } catch (e) {
      AppLogger.w('Error pausing voice recording: $e');
    }
  }

  /// Resume paused recording session
  Future<void> resumeRecording() async {
    try {
      if (!_isPaused) return;
      await _audioRecorder.resume();
      _lastResumeTime = DateTime.now();
      _isPaused = false;
      AppLogger.i('Voice recording resumed');
    } catch (e) {
      AppLogger.w('Error resuming voice recording: $e');
    }
  }

  /// Stop recording and return file bytes and duration in seconds
  Future<VoiceRecordingResult?> stopRecording() async {
    try {
      _durationTimer?.cancel();
      final path = await _audioRecorder.stop();
      if (path == null) return null;

      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      var totalDuration = _accumulatedDuration;
      if (!_isPaused && _lastResumeTime != null) {
        totalDuration += DateTime.now().difference(_lastResumeTime!);
      }
      final duration = totalDuration.inSeconds;

      AppLogger.i('Voice recording stopped: $path (${bytes.length} bytes, duration: ${duration}s)');

      return VoiceRecordingResult(
        filePath: path,
        bytes: bytes,
        durationSeconds: duration > 0 ? duration : 1,
      );
    } catch (e) {
      AppLogger.e('Error stopping voice recording', e);
      return null;
    } finally {
      _recordingStartTime = null;
      _lastResumeTime = null;
      _accumulatedDuration = Duration.zero;
      _isPaused = false;
    }
  }

  /// Cancel and delete current recording
  Future<void> cancelRecording() async {
    try {
      _durationTimer?.cancel();
      await _audioRecorder.cancel();
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      AppLogger.i('Voice recording cancelled');
    } catch (e) {
      AppLogger.w('Error cancelling voice recording: $e');
    } finally {
      _recordingStartTime = null;
      _lastResumeTime = null;
      _accumulatedDuration = Duration.zero;
      _isPaused = false;
      _currentRecordingPath = null;
    }
  }

  void dispose() {
    _durationTimer?.cancel();
    _durationController.close();
    _audioRecorder.dispose();
  }
}

class VoiceRecordingResult {
  final String filePath;
  final Uint8List bytes;
  final int durationSeconds;

  const VoiceRecordingResult({
    required this.filePath,
    required this.bytes,
    required this.durationSeconds,
  });
}
