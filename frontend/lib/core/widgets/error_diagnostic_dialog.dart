import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorDiagnosticDialog extends StatelessWidget {
  final String message;
  final String? referenceCode;
  final String? errorCode;
  final String? details;

  const ErrorDiagnosticDialog({
    super.key,
    required this.message,
    this.referenceCode,
    this.errorCode,
    this.details,
  });

  /// Displays the modal error diagnostic dialog
  static Future<void> show(
    BuildContext context, {
    required String message,
    String? referenceCode,
    String? errorCode,
    String? details,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ErrorDiagnosticDialog(
        message: message,
        referenceCode: referenceCode,
        errorCode: errorCode,
        details: details,
      ),
    );
  }

  /// Displays a non-blocking diagnostic snackbar with a copy action
  static void showSnackBar(
    BuildContext context, {
    required String message,
    String? referenceCode,
    String? errorCode,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final formattedRef = referenceCode != null ? ' ($referenceCode)' : '';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$message$formattedRef',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.red.shade900,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: referenceCode != null
            ? SnackBarAction(
                label: 'COPY CODE',
                textColor: Colors.yellowAccent,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: referenceCode));
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Reference code copied to clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }

  String _formatDiagnosticReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== ChatAPP Error Diagnostic ===');
    if (referenceCode != null) buffer.writeln('Reference Code: $referenceCode');
    if (errorCode != null) buffer.writeln('Error Code: $errorCode');
    buffer.writeln('Message: $message');
    if (details != null && details!.isNotEmpty) {
      buffer.writeln('Details: $details');
    }
    buffer.writeln('Timestamp: ${DateTime.now().toUtc().toIso8601String()}');
    buffer.writeln('================================');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Error Encountered',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.85),
                height: 1.4,
              ),
            ),
            if (referenceCode != null || errorCode != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (referenceCode != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Reference Code:',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              referenceCode!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (errorCode != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Error Code:',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            errorCode!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      'Please share this code with support or development team for fast diagnosis.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (details != null && details!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                details!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            final report = _formatDiagnosticReport();
            Clipboard.setData(ClipboardData(text: report));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error details and reference code copied to clipboard!'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Details'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
