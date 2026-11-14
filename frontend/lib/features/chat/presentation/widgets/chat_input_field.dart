import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/audio/voice_record_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';

class ChatInputField extends StatefulWidget {
  final ValueChanged<String> onSend;
  final VoidCallback? onAttachmentPressed;
  final void Function(VoiceRecordingResult result)? onVoiceRecorded;
  final bool isSending;

  const ChatInputField({
    super.key,
    required this.onSend,
    this.onAttachmentPressed,
    this.onVoiceRecorded,
    this.isSending = false,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  final TextEditingController _controller = TextEditingController();
  final VoiceRecordService _voiceService = sl<VoiceRecordService>();

  bool _canSend = false;
  bool _isRecordingVoice = false;
  bool _isPaused = false;
  Duration _recordingDuration = Duration.zero;
  StreamSubscription? _durationSub;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final canSend = _controller.text.trim().isNotEmpty;
      if (canSend != _canSend) {
        setState(() => _canSend = canSend);
      }
    });

    _durationSub = _voiceService.durationStream.listen((dur) {
      if (mounted && _isRecordingVoice && !_isPaused) {
        setState(() => _recordingDuration = dur);
      }
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.isSending) {
      widget.onSend(text);
      _controller.clear();
    }
  }

  Future<void> _startRecording() async {
    final started = await _voiceService.startRecording();
    if (started) {
      if (mounted) {
        setState(() {
          _isRecordingVoice = true;
          _isPaused = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> _togglePauseResume() async {
    if (!_isRecordingVoice) return;
    if (_isPaused) {
      await _voiceService.resumeRecording();
      if (mounted) setState(() => _isPaused = false);
    } else {
      await _voiceService.pauseRecording();
      if (mounted) setState(() => _isPaused = true);
    }
  }

  Future<void> _sendRecording() async {
    if (!_isRecordingVoice) return;
    setState(() {
      _isRecordingVoice = false;
      _isPaused = false;
    });

    final result = await _voiceService.stopRecording();
    if (result != null) {
      if (result.durationSeconds < 1 && result.bytes.length < 5000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Voice message was too short'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }
      widget.onVoiceRecorded?.call(result);
    }
  }

  Future<void> _cancelRecording() async {
    setState(() {
      _isRecordingVoice = false;
      _isPaused = false;
    });
    await _voiceService.cancelRecording();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 16,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.4),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: _isRecordingVoice ? _buildRecordingBar() : _buildNormalInputBar(theme),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isPaused
              ? Colors.amberAccent.withOpacity(0.5)
              : AppColors.accentRose.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          // Delete / Cancel Button
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.accentRose, size: 22),
            onPressed: _cancelRecording,
            tooltip: 'Delete recording',
          ),
          const SizedBox(width: 4),

          // Blinking Red Dot or Pause Icon
          if (_isPaused)
            const Icon(Icons.pause, size: 16, color: Colors.amberAccent)
          else
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.accentRose,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),

          // Duration
          Text(
            _formatDuration(_recordingDuration),
            style: TextStyle(
              color: _isPaused ? Colors.amberAccent : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const Spacer(),

          // Pause / Resume Button
          IconButton(
            icon: Icon(
              _isPaused ? Icons.mic_none_outlined : Icons.pause_circle_outline,
              color: _isPaused ? AppColors.accent : Colors.white70,
              size: 24,
            ),
            onPressed: _togglePauseResume,
            tooltip: _isPaused ? 'Resume recording' : 'Pause recording',
          ),
          const SizedBox(width: 4),

          // Send Recording Button
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sendRecording,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.send,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalInputBar(ThemeData theme) {
    return Row(
      children: [
        // Attachment Button
        IconButton(
          icon: Icon(
            Icons.attach_file,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: widget.onAttachmentPressed,
          tooltip: 'Attach Media or Document',
        ),

        // Text Input Box
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'Type an encrypted message...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Action Button: Send if text entered, else Push-to-Talk Mic
        if (_canSend)
          Material(
            color: theme.colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _handleSend,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: widget.isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send,
                        size: 20,
                        color: Colors.white,
                      ),
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () => _startRecording(),
            onLongPressStart: (_) => _startRecording(),
            onLongPressMoveUpdate: (details) {
              if (details.localOffsetFromOrigin.dx < -70) {
                _cancelRecording();
              }
            },
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _startRecording(),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.mic,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
