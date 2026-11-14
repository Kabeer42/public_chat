import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/crypto/safety_number_helper.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../call/presentation/pages/video_call_page.dart';
import '../../../call/presentation/pages/voice_call_page.dart';
import '../../../chat/domain/repositories/chat_repository.dart';
import '../../../chat/presentation/pages/chat_page.dart';
import '../../../chat/presentation/pages/shared_media_gallery_page.dart';

class UserProfilePage extends StatefulWidget {
  final UserEntity currentUser;
  final UserEntity peerUser;

  const UserProfilePage({
    super.key,
    required this.currentUser,
    required this.peerUser,
  });

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  String _safetyNumber = 'Calculating...';
  bool _isLoadingSafetyNumber = true;
  int _disappearingDurationSeconds = 0;
  bool _isLoadingDisappearing = true;
  bool _isUpdatingDisappearing = false;

  @override
  void initState() {
    super.initState();
    _computeSafetyNumber();
    _loadDisappearingDuration();
  }

  Future<void> _loadDisappearingDuration() async {
    try {
      final duration = await sl<ChatRepository>().getDisappearingDuration(widget.peerUser.id);
      if (mounted) {
        setState(() {
          _disappearingDurationSeconds = duration;
          _isLoadingDisappearing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingDisappearing = false);
      }
    }
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

  Future<void> _updateDisappearingDuration(int seconds) async {
    Navigator.pop(context);
    setState(() => _isUpdatingDisappearing = true);
    try {
      final updated = await sl<ChatRepository>().setDisappearingDuration(widget.peerUser.id, seconds);
      if (mounted) {
        setState(() {
          _disappearingDurationSeconds = updated;
          _isUpdatingDisappearing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              seconds == 0
                  ? 'Disappearing messages turned off'
                  : 'Disappearing messages set to ${_getDurationLabel(seconds)}',
            ),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdatingDisappearing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update timer: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showDisappearingDurationPicker() {
    showModalBottomSheet(
      context: context,
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
                  final isSelected = _disappearingDurationSeconds == seconds;

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
                    onTap: () => _updateDisappearingDuration(seconds),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _computeSafetyNumber() async {
    final localKey = widget.currentUser.publicIdentityKey ?? '';
    final peerKey = widget.peerUser.publicIdentityKey ?? '';

    final number = await SafetyNumberHelper.generateSafetyNumber(
      localPublicKeyBase64: localKey,
      peerPublicKeyBase64: peerKey,
    );

    if (mounted) {
      setState(() {
        _safetyNumber = number;
        _isLoadingSafetyNumber = false;
      });
    }
  }

  void _copySafetyNumber() {
    Clipboard.setData(ClipboardData(text: _safetyNumber));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Safety number copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.peerUser.isOnline;
    final initial = widget.peerUser.name.isNotEmpty
        ? widget.peerUser.name[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Contact Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // Profile Avatar with Status Ring
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 54,
                    backgroundColor: AppColors.primaryLight,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isOnline ? AppColors.accent : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.backgroundDark, width: 3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // User Name & Email
            Text(
              widget.peerUser.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.peerUser.email,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isOnline ? AppColors.accent : Colors.white24).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isOnline
                    ? 'Online'
                    : (widget.peerUser.lastSeenAt != null
                        ? 'Away • Last seen ${_formatLastSeen(widget.peerUser.lastSeenAt!)}'
                        : 'Away'),
                style: TextStyle(
                  color: isOnline ? AppColors.accent : Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons Row (Chat, Audio Call, Video Call)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'Message',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(
                            currentUser: widget.currentUser,
                            peerUser: widget.peerUser,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.call_outlined,
                    label: 'Voice Call',
                    onTap: () {
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
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.videocam_outlined,
                    label: 'Video Call',
                    onTap: () {
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
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Shared Media, Docs & Audio Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTile(
                icon: Icons.perm_media_outlined,
                iconColor: AppColors.accent,
                title: 'Media, Links, and Docs',
                subtitle: 'Photos, videos, documents, and voice messages',
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SharedMediaGalleryPage(
                        peerUser: widget.peerUser,
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Disappearing Messages Tile
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTile(
                icon: Icons.timer_outlined,
                iconColor: Colors.amberAccent,
                title: 'Disappearing Messages',
                subtitle: _isLoadingDisappearing
                    ? 'Loading...'
                    : _getDurationLabel(_disappearingDurationSeconds),
                trailing: _isUpdatingDisappearing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                      )
                    : const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: _showDisappearingDurationPicker,
              ),
            ),

            const SizedBox(height: 12),

            // E2EE Safety Number Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'End-to-End Encryption',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Messages and calls with this contact are encrypted end-to-end. Compare the safety number below with your contact to verify security.',
                      style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: _isLoadingSafetyNumber
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              ),
                            )
                          : SelectableText(
                              _safetyNumber,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                                height: 1.6,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _copySafetyNumber,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.copy_outlined, size: 16, color: AppColors.primary),
                            SizedBox(width: 6),
                            Text(
                              'Copy Safety Number',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minWidth: 76),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
