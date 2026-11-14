import 'package:chatapp/core/network/api_exceptions.dart';
import 'package:chatapp/core/widgets/error_diagnostic_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Error Diagnostics & ApiException Tests', () {
    test('ApiException includes reference code in toString()', () {
      final exception = ApiException(
        message: 'The sdp field is required.',
        statusCode: 422,
        referenceCode: 'ERR-7B3A-9F1C',
      );

      expect(exception.message, 'The sdp field is required.');
      expect(exception.statusCode, 422);
      expect(exception.referenceCode, 'ERR-7B3A-9F1C');
      expect(exception.toString(), contains('ERR-7B3A-9F1C'));
      expect(exception.toString(), contains('422'));
    });

    test('ValidationException preserves reference code and errors map', () {
      final validation = ValidationException(
        message: 'Validation failed',
        errors: {
          'sdp': ['The sdp field is required.']
        },
        referenceCode: 'ERR-VAL-0001',
      );

      expect(validation.statusCode, 422);
      expect(validation.referenceCode, 'ERR-VAL-0001');
      expect(validation.errors['sdp'], isNotEmpty);
      expect(validation.toString(), contains('ERR-VAL-0001'));
    });

    testWidgets('ErrorDiagnosticDialog renders reference code, error code, and copy button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ErrorDiagnosticDialog.show(
                      context,
                      message: 'WebRTC Signaling Failed to establish DTLS session.',
                      referenceCode: 'ERR-WBR-1234',
                      errorCode: 'WEBRTC_500',
                      details: 'SDP offer invalid or null',
                    );
                  },
                  child: const Text('Trigger Error'),
                );
              },
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Trigger Error'));
      await tester.pumpAndSettle();

      // Verify dialog elements
      expect(find.text('Error Encountered'), findsOneWidget);
      expect(find.text('WebRTC Signaling Failed to establish DTLS session.'), findsOneWidget);
      expect(find.text('ERR-WBR-1234'), findsOneWidget);
      expect(find.text('WEBRTC_500'), findsOneWidget);
      expect(find.text('Copy Details'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      // Tap Copy Details
      await tester.tap(find.text('Copy Details'));
      await tester.pump();

      // Tap Dismiss
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('Error Encountered'), findsNothing);
    });
  });
}
