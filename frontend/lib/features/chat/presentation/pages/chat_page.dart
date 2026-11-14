import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/audio/voice_record_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../call/presentation/pages/voice_call_page.dart';
import '../../../call/presentation/pages/video_call_page.dart';
import '../../domain/entities/message_entity.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_input_field.dart';
import '../widgets/contact_picker_dialog.dart';
import '../../../users/presentation/pages/user_profile_page.dart';
import 'shared_media_gallery_page.dart';

class ChatPage extends StatefulWidget {
  final UserEntity currentUser;
  final UserEntity peerUser;

  const ChatPage({
    super.key,
    required this.currentUser,
    required this.peerUser,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatBloc _chatBloc;
  final ScrollController _scrollController = ScrollController();
  final Set<int> _selectedMessageIds = {};
  MessageEntity? _replyingToMessage;
  int _previousMessageCount = 0;
  double? _lastMaxScrollExtent;

  @override
  void initState() {
    super.initState();
    _chatBloc = sl<ChatBloc>();
    _scrollController.addListener(_onScroll);

    // Subscribe to current user's private WebSocket channel for real-time messages
    sl<WebSocketService>().connect();
    sl<WebSocketService>().subscribeToUserChannel(widget.currentUser.id);

    // Load encrypted chat history
    _chatBloc.add(LoadChatHistoryEvent(
      peerId: widget.peerUser.id,
      peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
    ));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <= 100 &&
        _chatBloc.state.hasMore &&
        !_chatBloc.state.isLoadingMore) {
      _lastMaxScrollExtent = _scrollController.position.maxScrollExtent;
      _chatBloc.add(LoadMoreMessagesEvent(
        peerId: widget.peerUser.id,
        peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
      ));
    }
  }

  String _getReplyPreviewSnippet(MessageEntity msg) {
    if (msg.messageType == 'image') return '📷 Photo';
    if (msg.messageType == 'video') return '🎥 Video';
    if (msg.messageType == 'audio') return '🎤 Voice message';
    if (msg.messageType == 'document') return '📄 ${msg.fileName ?? 'Document'}';
    if (msg.messageType == 'contact') return '👤 Contact card';
    final text = msg.plaintext?.trim() ?? '';
    if (text.length > 50) return '${text.substring(0, 50)}...';
    return text.isEmpty ? '[Encrypted Message]' : text;
  }

  String _getDurationLabel(int seconds) {
    switch (seconds) {
      case 3600:
        return '1 hour';
      case 43200:
        return '12 hours';
      case 86400:
        return '24 hours';
      case 604800:
        return '7 days';
      default:
        return 'Off';
    }
  }

  void _showDisappearingPicker(int currentDuration) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        final options = [
          {'seconds': 0, 'label': 'Off', 'desc': 'Messages remain in chat indefinitely'},
          {'seconds': 3600, 'label': '1 hour', 'desc': 'Messages auto-delete 1 hour after send'},
          {'seconds': 43200, 'label': '12 hours', 'desc': 'Messages auto-delete 12 hours after send'},
          {'seconds': 86400, 'label': '24 hours', 'desc': 'Messages auto-delete 24 hours after send'},
          {'seconds': 604800, 'label': '7 days', 'desc': 'Messages auto-delete 7 days after send'},
        ];

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined, color: Colors.amberAccent, size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Disappearing Messages',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'When turned on, new messages sent in this chat disappear after the chosen duration for both users.',
                      style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.3),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12),
                  ...options.map((opt) {
                    final seconds = opt['seconds'] as int;
                    final isSelected = currentDuration == seconds;

                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: isSelected ? AppColors.primary : Colors.white38,
                      ),
                      title: Text(
                        opt['label'] as String,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        opt['desc'] as String,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        _chatBloc.add(SetDisappearingDurationEvent(
                          peerId: widget.peerUser.id,
                          durationSeconds: seconds,
                        ));
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAttachmentBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Share End-to-End Encrypted Media',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Media files are encrypted on your device with AES-256 before leaving.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.accent.withOpacity(0.2),
                    child: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
                  ),
                  title: const Text('Photo Gallery', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Send an encrypted image from gallery', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAndSendMedia(ImageSource.gallery, isVideo: false);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primaryLight.withOpacity(0.2),
                    child: const Icon(Icons.camera_alt_outlined, color: AppColors.primaryLight),
                  ),
                  title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Capture and encrypt photo', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAndSendMedia(ImageSource.camera, isVideo: false);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.amberAccent.withOpacity(0.2),
                    child: const Icon(Icons.videocam_outlined, color: Colors.amberAccent),
                  ),
                  title: const Text('Video Gallery', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Send an encrypted video file', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAndSendMedia(ImageSource.gallery, isVideo: true);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.tealAccent.withOpacity(0.2),
                    child: const Icon(Icons.insert_drive_file_outlined, color: Colors.tealAccent),
                  ),
                  title: const Text('Document', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Send encrypted document (PDF, Word, zip up to 25MB)', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAndSendDocument();
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                    child: const Icon(Icons.person_add_alt_1_outlined, color: Colors.purpleAccent),
                  ),
                  title: const Text('Share Contact', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Send encrypted contact card', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    Navigator.pop(bottomSheetContext);
                    _pickAndSendContact();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      },
    );
  }

  Future<void> _pickAndSendMedia(ImageSource source, {required bool isVideo}) async {
    try {
      final picker = ImagePicker();
      XFile? pickedFile;

      if (isVideo) {
        pickedFile = await picker.pickVideo(source: source);
      } else {
        pickedFile = await picker.pickImage(source: source, imageQuality: 85);
      }

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();

        final replyId = _replyingToMessage?.id;
        final replyPreview = _replyingToMessage != null
            ? _getReplyPreviewSnippet(_replyingToMessage!)
            : null;

        setState(() {
          _replyingToMessage = null;
        });

        _chatBloc.add(SendMediaMessageEvent(
          peerId: widget.peerUser.id,
          peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
          fileBytes: bytes,
          messageType: isVideo ? 'video' : 'image',
          replyToId: replyId,
          replyPreview: replyPreview,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to select media: $e'),
            backgroundColor: AppColors.accentRose,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedFile = result.files.first;
        Uint8List? bytes = pickedFile.bytes;
        if (bytes == null && pickedFile.path != null) {
          bytes = await File(pickedFile.path!).readAsBytes();
        }

        if (bytes == null || bytes.isEmpty) return;

        if (bytes.length > 25 * 1024 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('File exceeds maximum size limit of 25MB.'),
                backgroundColor: AppColors.accentRose,
              ),
            );
          }
          return;
        }

        final replyId = _replyingToMessage?.id;
        final replyPreview = _replyingToMessage != null
            ? _getReplyPreviewSnippet(_replyingToMessage!)
            : null;

        setState(() {
          _replyingToMessage = null;
        });

        _chatBloc.add(SendMediaMessageEvent(
          peerId: widget.peerUser.id,
          peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
          fileBytes: bytes,
          messageType: 'document',
          fileName: pickedFile.name,
          fileSize: pickedFile.size,
          replyToId: replyId,
          replyPreview: replyPreview,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick document: $e'),
            backgroundColor: AppColors.accentRose,
          ),
        );
      }
    }
  }

  Future<void> _pickAndSendContact() async {
    final contact = await ContactPickerDialog.show(context);
    if (contact != null) {
      final replyId = _replyingToMessage?.id;
      final replyPreview = _replyingToMessage != null
          ? _getReplyPreviewSnippet(_replyingToMessage!)
          : null;

      setState(() {
        _replyingToMessage = null;
      });

      final jsonPayload = jsonEncode(contact);

      _chatBloc.add(SendMessageEvent(
        peerId: widget.peerUser.id,
        peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
        text: jsonPayload,
        messageType: 'contact',
        replyToId: replyId,
        replyPreview: replyPreview,
      ));
    }
  }

  void _handleVoiceRecorded(VoiceRecordingResult result) {
    try {
      final replyId = _replyingToMessage?.id;
      final replyPreview = _replyingToMessage != null
          ? _getReplyPreviewSnippet(_replyingToMessage!)
          : null;

      setState(() {
        _replyingToMessage = null;
      });

      _chatBloc.add(SendMediaMessageEvent(
        peerId: widget.peerUser.id,
        peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
        fileBytes: result.bytes,
        messageType: 'audio',
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        fileSize: result.bytes.length,
        replyToId: replyId,
        replyPreview: replyPreview,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice note: $e'),
            backgroundColor: AppColors.accentRose,
          ),
        );
      }
    }
  }

  void _confirmDeleteMessages(List<MessageEntity> allMessages) {
    final selected = allMessages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    if (selected.isEmpty) return;

    // RULE SPECIFIED BY USER:
    // 1. If sender deletes their own messages/images -> Both "Delete for Everyone" and "Delete for Me"
    // 2. If receiver deletes -> Only "Delete for Me"
    // 3. If mixed selection (own messages + peer messages) -> Only "Delete for Me"
    // 4. If all selected messages are sent by current user -> Both options
    final allMine = selected.every(
      (m) => m.senderId == widget.currentUser.id || m.senderId == 0,
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _selectedMessageIds.length == 1
              ? 'Delete Message?'
              : 'Delete ${_selectedMessageIds.length} Messages?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          allMine
              ? 'Do you want to delete selected message(s) for everyone in this chat or only for yourself?'
              : 'Do you want to delete selected message(s) from your chat?',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () {
              final ids = _selectedMessageIds.toList();
              Navigator.pop(dialogCtx);
              setState(() => _selectedMessageIds.clear());
              _chatBloc.add(DeleteMessagesEvent(
                messageIds: ids,
                type: 'for_me',
              ));
            },
            child: const Text(
              'Delete for Me',
              style: TextStyle(
                color: AppColors.accentRose,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (allMine)
            TextButton(
              onPressed: () {
                final ids = _selectedMessageIds.toList();
                Navigator.pop(dialogCtx);
                setState(() => _selectedMessageIds.clear());
                _chatBloc.add(DeleteMessagesEvent(
                  messageIds: ids,
                  type: 'for_everyone',
                ));
              },
              child: const Text(
                'Delete for Everyone',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyBanner() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    final isReplyingToMe = _replyingToMessage!.senderId == widget.currentUser.id ||
        _replyingToMessage!.senderId == 0;
    final authorName = isReplyingToMe ? 'You' : widget.peerUser.name;
    final snippet = _getReplyPreviewSnippet(_replyingToMessage!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withOpacity(0.96),
        border: const Border(
          top: BorderSide(color: Colors.white12, width: 1),
          left: BorderSide(color: AppColors.accent, width: 4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $authorName',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white60),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() => _replyingToMessage = null);
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = _selectedMessageIds.isNotEmpty;

    return BlocProvider.value(
      value: _chatBloc,
      child: PopScope(
        canPop: !isSelectionMode,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && isSelectionMode) {
            setState(() => _selectedMessageIds.clear());
          }
        },
        child: BlocConsumer<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state.messages.length > _previousMessageCount) {
              if (_lastMaxScrollExtent != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients && _lastMaxScrollExtent != null) {
                    final diff = _scrollController.position.maxScrollExtent - _lastMaxScrollExtent!;
                    _scrollController.jumpTo(_scrollController.position.pixels + diff);
                    _lastMaxScrollExtent = null;
                  }
                });
              } else {
                _scrollToBottom();
              }
            }
            _previousMessageCount = state.messages.length;

            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: AppColors.accentRose,
                ),
              );
            }
          },
          builder: (context, state) {
            return Scaffold(
              appBar: isSelectionMode
                  ? AppBar(
                      elevation: 1,
                      backgroundColor: AppColors.surfaceDark,
                      leading: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _selectedMessageIds.clear()),
                      ),
                      title: Text(
                        '${_selectedMessageIds.length} Selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.accentRose),
                          tooltip: 'Delete Selected',
                          onPressed: () => _confirmDeleteMessages(state.messages),
                        ),
                      ],
                    )
                  : AppBar(
                      elevation: 1,
                      titleSpacing: 0,
                      title: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserProfilePage(
                                currentUser: widget.currentUser,
                                peerUser: widget.peerUser,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: AppColors.primary.withOpacity(0.2),
                              child: Text(
                                widget.peerUser.name.isNotEmpty
                                    ? widget.peerUser.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.peerUser.name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: widget.peerUser.isOnline ? AppColors.accent : Colors.amber,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        widget.peerUser.isOnline ? 'Online' : 'Away',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: widget.peerUser.isOnline ? AppColors.accent : Colors.amber,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text('•', style: TextStyle(color: Colors.white24, fontSize: 10)),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.lock, size: 10, color: AppColors.accent),
                                      const SizedBox(width: 2),
                                      const Text(
                                        'Encrypted',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        if (state.disappearingDurationSeconds > 0)
                          IconButton(
                            icon: const Icon(Icons.timer_outlined, color: Colors.amberAccent),
                            tooltip: 'Disappearing Messages: ${_getDurationLabel(state.disappearingDurationSeconds)}',
                            onPressed: () => _showDisappearingPicker(state.disappearingDurationSeconds),
                          ),
                        IconButton(
                          icon: const Icon(Icons.call_outlined, color: AppColors.accent),
                          tooltip: 'Voice Call',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VoiceCallPage(
                                  peerUser: widget.peerUser,
                                  isOutgoing: true,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.videocam_outlined, color: AppColors.primaryLight),
                          tooltip: 'Video Call',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VideoCallPage(
                                  peerUser: widget.peerUser,
                                  isOutgoing: true,
                                ),
                              ),
                            );
                          },
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white70),
                          color: AppColors.surfaceDark,
                          onSelected: (value) {
                            if (value == 'disappearing') {
                              _showDisappearingPicker(state.disappearingDurationSeconds);
                            } else if (value == 'profile') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => UserProfilePage(
                                    currentUser: widget.currentUser,
                                    peerUser: widget.peerUser,
                                  ),
                                ),
                              );
                            } else if (value == 'media') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SharedMediaGalleryPage(
                                    peerUser: widget.peerUser,
                                  ),
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'disappearing',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 18,
                                    color: state.disappearingDurationSeconds > 0
                                        ? Colors.amberAccent
                                        : Colors.white70,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Disappearing messages (${_getDurationLabel(state.disappearingDurationSeconds)})',
                                    style: const TextStyle(color: Colors.white, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'media',
                              child: Row(
                                children: [
                                  Icon(Icons.perm_media_outlined, size: 18, color: Colors.white70),
                                  SizedBox(width: 10),
                                  Text('Shared media', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'profile',
                              child: Row(
                                children: [
                                  Icon(Icons.person_outline, size: 18, color: Colors.white70),
                                  SizedBox(width: 10),
                                  Text('View contact', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
              body: Column(
                children: [
                  // Disappearing Messages Banner (if active)
                  if (state.disappearingDurationSeconds > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      color: Colors.amber.withOpacity(0.12),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 15, color: Colors.amberAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Disappearing messages active: New messages vanish after ${_getDurationLabel(state.disappearingDurationSeconds)}.',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _showDisappearingPicker(state.disappearingDurationSeconds),
                            child: const Text(
                              'Change',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // E2EE Security Notification Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppColors.surfaceDark.withOpacity(0.8),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, size: 16, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Messages are client-side encrypted with X25519 & AES-256-GCM. The server never sees plaintext.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondaryDark.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Messages List
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (state.status == ChatStatus.loading && state.messages.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          );
                        }

                        if (state.messages.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_clock_outlined,
                                  size: 54,
                                  color: AppColors.textSecondaryDark.withOpacity(0.6),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No messages here yet.',
                                  style: TextStyle(
                                    color: AppColors.textSecondaryDark,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Send an encrypted message to ${widget.peerUser.name}!',
                                  style: TextStyle(
                                    color: AppColors.textSecondaryDark.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: state.messages.length + (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (state.isLoadingMore && index == 0) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final messageIndex = state.isLoadingMore ? index - 1 : index;
                            final message = state.messages[messageIndex];
                            final isMe = message.senderId == widget.currentUser.id ||
                                message.senderId == 0;
                            final isSelected = _selectedMessageIds.contains(message.id);

                            return ChatBubble(
                              message: message,
                              isMe: isMe,
                              peerId: widget.peerUser.id,
                              peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
                              isSelected: isSelected,
                              isSelectionMode: isSelectionMode,
                              onTap: () {
                                if (isSelectionMode) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedMessageIds.remove(message.id);
                                    } else {
                                      _selectedMessageIds.add(message.id);
                                    }
                                  });
                                }
                              },
                              onLongPress: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedMessageIds.remove(message.id);
                                  } else {
                                    _selectedMessageIds.add(message.id);
                                  }
                                });
                              },
                              onSwipeReply: (msg) {
                                setState(() {
                                  _replyingToMessage = msg;
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Replying To Preview Banner
                  _buildReplyBanner(),

                  // Bottom Chat Input Bar
                  ChatInputField(
                    isSending: state.isSending,
                    onVoiceRecorded: _handleVoiceRecorded,
                    onSend: (text) {
                      final replyId = _replyingToMessage?.id;
                      final replyPreview = _replyingToMessage != null
                          ? _getReplyPreviewSnippet(_replyingToMessage!)
                          : null;

                      setState(() {
                        _replyingToMessage = null;
                      });

                      _chatBloc.add(SendMessageEvent(
                        peerId: widget.peerUser.id,
                        peerPublicKey: widget.peerUser.publicIdentityKey ?? '',
                        text: text,
                        replyToId: replyId,
                        replyPreview: replyPreview,
                      ));
                    },
                    onAttachmentPressed: () => _showAttachmentBottomSheet(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
