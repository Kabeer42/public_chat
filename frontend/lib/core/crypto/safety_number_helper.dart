import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class SafetyNumberHelper {
  /// Generate a 60-digit E2EE safety number from two X25519 identity keys.
  /// Keys are sorted alphabetically before hashing so both parties produce
  /// the identical fingerprint regardless of who initiated the conversation.
  static Future<String> generateSafetyNumber({
    required String localPublicKeyBase64,
    required String peerPublicKeyBase64,
  }) async {
    if (localPublicKeyBase64.isEmpty || peerPublicKeyBase64.isEmpty) {
      return '00000 00000 00000 00000 00000 00000 00000 00000 00000 00000 00000 00000';
    }

    final keys = [localPublicKeyBase64.trim(), peerPublicKeyBase64.trim()]..sort();
    final combined = '${keys[0]}:${keys[1]}';
    final bytes = utf8.encode(combined);

    final sha256Algorithm = Sha256();
    final hash = await sha256Algorithm.hash(bytes);
    final hashBytes = hash.bytes;

    final chunks = <String>[];
    // Generate 12 chunks of 5-digit numbers using 24 bytes (12 * 2 = 24 <= 32 bytes)
    for (int i = 0; i < 12; i++) {
      final val = (hashBytes[i * 2] << 8) | hashBytes[i * 2 + 1];
      final fiveDigit = (val % 100000).toString().padLeft(5, '0');
      chunks.add(fiveDigit);
    }

    return chunks.join(' ');
  }
}
