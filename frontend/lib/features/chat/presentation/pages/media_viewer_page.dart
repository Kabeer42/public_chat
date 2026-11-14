import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class MediaViewerPage extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;

  const MediaViewerPage({
    super.key,
    required this.imageBytes,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            const Row(
              children: [
                Icon(Icons.lock, size: 11, color: AppColors.accent),
                SizedBox(width: 4),
                Text(
                  'End-to-End Encrypted Photo',
                  style: TextStyle(fontSize: 11, color: AppColors.accent),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
