import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/usecases/download_media_usecase.dart';
import '../pages/media_viewer_page.dart';

class MediaBubble extends StatefulWidget {
  final MessageEntity message;
  final int peerId;
  final String peerPublicKey;
  final bool isMe;

  const MediaBubble({
    super.key,
    required this.message,
    required this.peerId,
    required this.peerPublicKey,
    required this.isMe,
  });

  @override
  State<MediaBubble> createState() => _MediaBubbleState();
}

class _MediaBubbleState extends State<MediaBubble> {
  Uint8List? _decryptedBytes;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAndDecryptMedia();
  }

  @override
  void didUpdateWidget(covariant MediaBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaUrl != widget.message.mediaUrl ||
        oldWidget.message.id != widget.message.id ||
        (_decryptedBytes == null &&
            !_isLoading &&
            widget.message.mediaUrl != null)) {
      _loadAndDecryptMedia();
    }
  }

  Future<void> _loadAndDecryptMedia() async {
    if (widget.message.mediaUrl == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final bytes = await sl<DownloadMediaUseCase>()(
        peerId: widget.peerId,
        peerPublicKey: widget.peerPublicKey,
        message: widget.message,
      );

      if (mounted) {
        setState(() {
          _decryptedBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e(
          'Media decryption failed for message #${widget.message.id}', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Decryption failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVideo = widget.message.messageType == 'video';

    return Container(
      constraints: const BoxConstraints(
        maxWidth: 260,
        minWidth: 160,
        minHeight: 160,
        maxHeight: 260,
      ),
      decoration: BoxDecoration(
        color: widget.isMe
            ? theme.colorScheme.primary.withOpacity(0.15)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_decryptedBytes != null) ...[
            if (!isVideo)
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MediaViewerPage(
                        imageBytes: _decryptedBytes!,
                        title: widget.isMe ? 'Sent Photo' : 'Received Photo',
                      ),
                    ),
                  );
                },
                child: Image.memory(
                  _decryptedBytes!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              )
            else
              Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Encrypted Video',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ] else if (_isLoading) ...[
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(height: 8),
                  Text(
                    'Decrypting...',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ] else if (_errorMessage != null) ...[
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image, size: 36, color: Colors.grey),
                  const SizedBox(height: 6),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: _loadAndDecryptMedia,
                    child: const Text('Retry', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
