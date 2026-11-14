import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/usecases/download_media_usecase.dart';

class AudioBubble extends StatefulWidget {
  final MessageEntity message;
  final int peerId;
  final String peerPublicKey;
  final bool isMe;

  const AudioBubble({
    super.key,
    required this.message,
    required this.peerId,
    required this.peerPublicKey,
    required this.isMe,
  });

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final _playerService = sl<AudioPlayerService>();
  Uint8List? _audioBytes;
  bool _isLoading = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _subscribeToPlayer();
  }

  void _subscribeToPlayer() {
    _posSub = _playerService.onPositionChanged.listen((pos) {
      if (_playerService.currentlyPlayingId == widget.message.id.toString()) {
        if (mounted) setState(() => _position = pos);
      }
    });

    _durSub = _playerService.onDurationChanged.listen((dur) {
      if (_playerService.currentlyPlayingId == widget.message.id.toString()) {
        if (mounted) setState(() => _duration = dur);
      }
    });

    _stateSub = _playerService.onPlayerStateChanged.listen((state) {
      final isMyAudio = _playerService.currentlyPlayingId == widget.message.id.toString();
      if (mounted) {
        setState(() {
          _isPlaying = isMyAudio && state == PlayerState.playing;
          if (state == PlayerState.completed && isMyAudio) {
            _position = Duration.zero;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final msgIdStr = widget.message.id.toString();

    if (_isPlaying) {
      await _playerService.pause();
      return;
    }

    if (_playerService.currentlyPlayingId == msgIdStr) {
      await _playerService.resume();
      return;
    }

    // Load and decrypt bytes if not in memory
    if (_audioBytes == null) {
      setState(() => _isLoading = true);
      try {
        final bytes = await sl<DownloadMediaUseCase>()(
          peerId: widget.peerId,
          peerPublicKey: widget.peerPublicKey,
          message: widget.message,
        );
        _audioBytes = bytes;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load audio: $e')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }
    }

    setState(() => _isLoading = false);

    if (_audioBytes != null) {
      await _playerService.playBytes(id: msgIdStr, bytes: _audioBytes!);
      await _playerService.setPlaybackRate(_playbackSpeed);
    }
  }

  void _cycleSpeed() {
    double nextSpeed = 1.0;
    if (_playbackSpeed == 1.0) {
      nextSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      nextSpeed = 2.0;
    } else {
      nextSpeed = 1.0;
    }

    setState(() => _playbackSpeed = nextSpeed);
    if (_isPlaying) {
      _playerService.setPlaybackRate(nextSpeed);
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final maxDurMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final posMs = _position.inMilliseconds.toDouble().clamp(0.0, maxDurMs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Play/Pause/Loading Button
              GestureDetector(
                onTap: _isLoading ? null : _togglePlay,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.isMe ? AppColors.primary : AppColors.surfaceDark,
                    shape: BoxShape.circle,
                  ),
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
              const SizedBox(width: 8),

              // Waveform / Seekbar Slider
              Expanded(
                child: Column(
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 3,
                        activeTrackColor: widget.isMe ? Colors.white : AppColors.primary,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: widget.isMe ? Colors.white : AppColors.primary,
                      ),
                      child: Slider(
                        value: posMs,
                        min: 0.0,
                        max: maxDurMs,
                        onChanged: (val) {
                          _playerService.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                          Text(
                            _duration.inSeconds > 0
                                ? _formatDuration(_duration)
                                : 'Voice Note',
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Speed Multiplier Pill
              GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
