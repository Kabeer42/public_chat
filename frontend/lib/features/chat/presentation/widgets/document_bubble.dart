import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../../../../core/di/injection_container.dart';
import '../../../../core/storage/local_vault_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/usecases/download_media_usecase.dart';

class DocumentBubble extends StatefulWidget {
  final MessageEntity message;
  final int peerId;
  final String peerPublicKey;
  final bool isMe;

  const DocumentBubble({
    super.key,
    required this.message,
    required this.peerId,
    required this.peerPublicKey,
    required this.isMe,
  });

  @override
  State<DocumentBubble> createState() => _DocumentBubbleState();
}

class _DocumentBubbleState extends State<DocumentBubble> {
  bool _isLoading = false;

  String _getFileName() {
    final text = widget.message.plaintext ?? '';
    if (text.startsWith('[Document] ')) {
      return text.replaceFirst('[Document] ', '').trim();
    }
    if (text.isNotEmpty && !text.startsWith('[')) {
      return text;
    }
    return 'Document_${widget.message.id}';
  }

  IconData _getFileIcon(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.zip':
      case '.rar':
      case '.7z':
        return Icons.folder_zip;
      case '.txt':
        return Icons.text_snippet;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getIconColor(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.pdf':
        return Colors.redAccent;
      case '.doc':
      case '.docx':
        return Colors.blueAccent;
      case '.xls':
      case '.xlsx':
        return Colors.greenAccent;
      case '.zip':
      case '.rar':
      case '.7z':
        return Colors.amberAccent;
      default:
        return AppColors.primaryLight;
    }
  }

  Future<void> _openOrDownloadDocument() async {
    final vault = sl<LocalVaultService>();
    final localPath = widget.message.localFilePath;

    if (localPath != null && await vault.fileExists(localPath)) {
      await OpenFilex.open(localPath);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bytes = await sl<DownloadMediaUseCase>()(
        peerId: widget.peerId,
        peerPublicKey: widget.peerPublicKey,
        message: widget.message,
      );

      final fileName = _getFileName();
      final savedPath = await vault.saveMediaFile(
        category: 'documents',
        fileName: '${widget.message.id}_$fileName',
        bytes: bytes,
      );

      await OpenFilex.open(savedPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open document: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _getFileName();
    final iconData = _getFileIcon(fileName);
    final iconColor = _getIconColor(fileName);

    return InkWell(
      onTap: _isLoading ? null : _openOrDownloadDocument,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 250),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: iconColor, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 10, color: Colors.white60),
                      const SizedBox(width: 3),
                      Text(
                        _isLoading ? 'Decrypting...' : 'Encrypted Document',
                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            else
              const Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: 22),
          ],
        ),
      ),
    );
  }
}
