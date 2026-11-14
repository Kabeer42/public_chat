import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/message_entity.dart';

class ContactBubble extends StatelessWidget {
  final MessageEntity message;
  final bool isMe;

  const ContactBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  Map<String, dynamic> _parseContact() {
    try {
      if (message.plaintext != null && message.plaintext!.startsWith('{')) {
        return jsonDecode(message.plaintext!) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {
      'name': message.plaintext ?? 'Contact Card',
      'phone': '',
      'email': '',
      'organization': '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final contact = _parseContact();
    final name = (contact['name'] as String?)?.trim() ?? 'Contact';
    final phone = (contact['phone'] as String?)?.trim() ?? '';
    final email = (contact['email'] as String?)?.trim() ?? '';
    final org = (contact['organization'] as String?)?.trim() ?? '';

    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primary.withOpacity(0.3) : AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.accent.withOpacity(0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          email,
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (org.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          org,
                          style: const TextStyle(color: Colors.white54, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          InkWell(
            onTap: () {
              if (phone.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: phone));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied $phone to clipboard'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.copy_outlined, size: 14, color: AppColors.accent),
                  SizedBox(width: 6),
                  Text(
                    'Copy Phone Number',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
