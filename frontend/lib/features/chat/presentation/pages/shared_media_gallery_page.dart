import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/storage/local_database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/entities/message_entity.dart';

class SharedMediaGalleryPage extends StatefulWidget {
  final UserEntity peerUser;

  const SharedMediaGalleryPage({
    super.key,
    required this.peerUser,
  });

  @override
  State<SharedMediaGalleryPage> createState() => _SharedMediaGalleryPageState();
}

class _SharedMediaGalleryPageState extends State<SharedMediaGalleryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final LocalDatabaseService _localDb = sl<LocalDatabaseService>();

  List<MessageEntity> _mediaList = [];
  List<MessageEntity> _docList = [];
  List<MessageEntity> _audioList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllSharedItems();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSharedItems() async {
    setState(() => _isLoading = true);
    try {
      final media = await _localDb.getMediaMessagesForPeer(
        widget.peerUser.id,
        messageTypes: ['image', 'video'],
      );
      final docs = await _localDb.getMediaMessagesForPeer(
        widget.peerUser.id,
        messageTypes: ['document'],
      );
      final audio = await _localDb.getMediaMessagesForPeer(
        widget.peerUser.id,
        messageTypes: ['audio'],
      );

      if (mounted) {
        setState(() {
          _mediaList = media;
          _docList = docs;
          _audioList = audio;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Shared Content',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              widget.peerUser.name,
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: 'Media (${_mediaList.length})'),
            Tab(text: 'Docs (${_docList.length})'),
            Tab(text: 'Audio (${_audioList.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMediaTab(),
                _buildDocsTab(),
                _buildAudioTab(),
              ],
            ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTab() {
    if (_mediaList.isEmpty) {
      return _buildEmptyState(Icons.photo_library_outlined, 'No shared photos or videos yet');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _mediaList.length,
      itemBuilder: (context, index) {
        final item = _mediaList[index];
        final isVideo = item.messageType == 'video';

        return GestureDetector(
          onTap: () => _openMediaViewer(item),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              color: AppColors.surfaceDark,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.localFilePath != null && File(item.localFilePath!).existsSync())
                    Image.file(
                      File(item.localFilePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white38),
                    )
                  else
                    const Center(
                      child: Icon(Icons.lock_clock, color: Colors.white38),
                    ),
                  if (isVideo)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openMediaViewer(MessageEntity item) {
    if (item.localFilePath == null || !File(item.localFilePath!).existsSync()) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: Image.file(
                File(item.localFilePath!),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocsTab() {
    if (_docList.isEmpty) {
      return _buildEmptyState(Icons.insert_drive_file_outlined, 'No shared documents yet');
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _docList.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final doc = _docList[index];
        final name = doc.fileName ?? doc.plaintext?.replaceFirst('[Document] ', '') ?? 'Document';
        final sizeFormatted = _formatFileSize(doc.fileSize ?? 0);
        final dateFormatted = DateFormat('MMM d, yyyy').format(doc.createdAt);

        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.description, color: AppColors.primaryLight, size: 24),
          ),
          title: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            '$sizeFormatted • $dateFormatted',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.open_in_new, color: Colors.white38, size: 20),
          onTap: () async {
            if (doc.localFilePath != null && File(doc.localFilePath!).existsSync()) {
              await OpenFilex.open(doc.localFilePath!);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document not cached locally.')),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildAudioTab() {
    if (_audioList.isEmpty) {
      return _buildEmptyState(Icons.mic_none_outlined, 'No shared voice notes yet');
    }

    final playerService = sl<AudioPlayerService>();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _audioList.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (context, index) {
        final audio = _audioList[index];
        final dateFormatted = DateFormat('MMM d, yyyy – h:mm a').format(audio.createdAt);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.accent.withOpacity(0.15),
            child: const Icon(Icons.multitrack_audio, color: AppColors.accent),
          ),
          title: const Text(
            'Voice Note',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            dateFormatted,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.play_circle_fill, color: AppColors.primary, size: 36),
            onPressed: () async {
              if (audio.localFilePath != null && File(audio.localFilePath!).existsSync()) {
                final bytes = await File(audio.localFilePath!).readAsBytes();
                await playerService.playBytes(id: audio.id.toString(), bytes: bytes);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice note file not found locally.')),
                );
              }
            },
          ),
        );
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
