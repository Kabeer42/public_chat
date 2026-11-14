import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/message_entity.dart';
import 'audio_bubble.dart';
import 'contact_bubble.dart';
import 'document_bubble.dart';
import 'media_bubble.dart';


class ChatBubble extends StatelessWidget {
  final MessageEntity message;
  final bool isMe;
  final int peerId;
  final String peerPublicKey;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(MessageEntity message)? onSwipeReply;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.peerId,
    required this.peerPublicKey,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onSwipeReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeStr = DateFormat('HH:mm').format(message.createdAt.toLocal());
    final isMedia = message.messageType == 'image' || message.messageType == 'video';

    final Widget bubbleContent = InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.18)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (isSelectionMode && isSelected) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: isMedia
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isMe
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      offset: const Offset(0, 1),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Replying banner quote if replyPreview is attached
                    if (message.replyPreview != null &&
                        message.replyPreview!.isNotEmpty)
                      _buildReplyQuote(context, theme),

                    // Render based on messageType
                    if (isMedia) ...[
                      MediaBubble(
                        message: message,
                        peerId: peerId,
                        peerPublicKey: peerPublicKey,
                        isMe: isMe,
                      ),
                      const SizedBox(height: 4),
                    ] else if (message.messageType == 'audio') ...[
                      AudioBubble(
                        message: message,
                        peerId: peerId,
                        peerPublicKey: peerPublicKey,
                        isMe: isMe,
                      ),
                      const SizedBox(height: 4),
                    ] else if (message.messageType == 'document') ...[
                      DocumentBubble(
                        message: message,
                        peerId: peerId,
                        peerPublicKey: peerPublicKey,
                        isMe: isMe,
                      ),
                      const SizedBox(height: 4),
                    ] else if (message.messageType == 'contact') ...[
                      ContactBubble(
                        message: message,
                        isMe: isMe,
                      ),
                      const SizedBox(height: 4),
                    ] else ...[
                      // Text message (Decrypted plaintext)
                      Text(
                        message.plaintext ?? '[Encrypted Payload]',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isMe ? Colors.white : theme.colorScheme.onSurface,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],


                    // Metadata row: Lock icon + Timestamp + Status ticks
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock,
                          size: 11,
                          color: isMe
                              ? Colors.white.withOpacity(0.7)
                              : theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 11,
                            color: isMe
                                ? Colors.white.withOpacity(0.75)
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (message.expiresAt != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.timer_outlined,
                            size: 12,
                            color: isMe
                                ? Colors.white.withOpacity(0.9)
                                : Colors.amberAccent,
                          ),
                        ],
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _buildStatusIcon(context),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (isSelectionMode) {
      return bubbleContent;
    }

    // Swipe-to-Reply from Left to Right
    return Dismissible(
      key: ValueKey('dismiss_msg_${message.id}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (direction) async {
        onSwipeReply?.call(message);
        return false; // Return false so the bubble springs back to position
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.reply_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
      ),
      child: bubbleContent,
    );
  }

  Widget _buildReplyQuote(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.black.withOpacity(0.18)
            : theme.colorScheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white : theme.colorScheme.primary,
            width: 3.5,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.reply_rounded,
            size: 14,
            color: isMe ? Colors.white70 : theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              message.replyPreview ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: isMe
                    ? Colors.white.withOpacity(0.9)
                    : theme.colorScheme.onSurface.withOpacity(0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    if (message.hasFailed) {
      return const Icon(
        Icons.error_outline,
        size: 14,
        color: Colors.redAccent,
      );
    }

    if (message.isSending) {
      return SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Colors.white.withOpacity(0.8),
        ),
      );
    }

    if (message.isRead) {
      return const Icon(
        Icons.done_all,
        size: 15,
        color: Color(0xFF34B7F1), // Double blue tick when seen
      );
    }

    if (message.isDelivered) {
      return const Icon(
        Icons.done_all,
        size: 15,
        color: Colors.white70, // Double grey tick when received
      );
    }

    // Sent to server but not yet delivered to recipient device
    return const Icon(
      Icons.check,
      size: 15,
      color: Colors.white70, // Single grey tick when sent
    );
  }
}
