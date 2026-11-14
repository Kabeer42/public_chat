import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'models/encrypted_payload.dart';

class CipherService {
  final AesGcm _aesGcm = AesGcm.with256bits();

  AesGcm get aesGcm => _aesGcm;

  // ==========================================
  // TEXT MESSAGE ENCRYPTION / DECRYPTION
  // ==========================================

  /// Encrypt a plaintext string using AES-256-GCM
  Future<EncryptedPayload> encryptText({
    required String plaintext,
    required SecretKey secretKey,
  }) async {
    final plainBytes = utf8.encode(plaintext);
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: secretKey,
    );

    return EncryptedPayload(
      ciphertext: base64Encode(secretBox.cipherText),
      iv: base64Encode(secretBox.nonce),
      mac: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Decrypt an EncryptedPayload back to a plaintext string using AES-256-GCM
  Future<String> decryptText({
    required EncryptedPayload payload,
    required SecretKey secretKey,
  }) async {
    final cipherTextBytes = base64Decode(payload.ciphertext);
    final nonceBytes = base64Decode(payload.iv);
    final macBytes = base64Decode(payload.mac);

    final secretBox = SecretBox(
      cipherTextBytes,
      nonce: nonceBytes,
      mac: Mac(macBytes),
    );

    final plainBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(plainBytes);
  }

  // ==========================================
  // MEDIA FILE ENCRYPTION / DECRYPTION (Images & Videos)
  // ==========================================

  /// Encrypt binary media file bytes using a freshly generated one-time AES-256 key
  Future<Map<String, dynamic>> encryptFile({
    required Uint8List fileBytes,
  }) async {
    // 1. Generate one-time random AES-256 key for this specific file
    final oneTimeFileKey = await _aesGcm.newSecretKey();
    final fileKeyBytes = await oneTimeFileKey.extractBytes();

    // 2. Encrypt file binary stream
    final secretBox = await _aesGcm.encrypt(
      fileBytes,
      secretKey: oneTimeFileKey,
    );

    return {
      'encryptedBytes': Uint8List.fromList(secretBox.cipherText),
      'fileKey': oneTimeFileKey,
      'fileKeyBytes': Uint8List.fromList(fileKeyBytes),
      'fileKeyBase64': base64Encode(fileKeyBytes),
      'iv': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypt encrypted binary media bytes using the recovered one-time file key
  Future<Uint8List> decryptFile({
    required Uint8List encryptedBytes,
    required SecretKey fileKey,
    required String ivBase64,
    required String macBase64,
  }) async {
    final nonceBytes = base64Decode(ivBase64);
    final macBytes = base64Decode(macBase64);

    final secretBox = SecretBox(
      encryptedBytes,
      nonce: nonceBytes,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: fileKey,
    );

    return Uint8List.fromList(decryptedBytes);
  }

  /// Encrypt a raw file key using the recipient's session key
  Future<EncryptedPayload> wrapFileKey({
    required String fileKeyBase64,
    required SecretKey sessionKey,
  }) async {
    return await encryptText(
      plaintext: fileKeyBase64,
      secretKey: sessionKey,
    );
  }

  /// Decrypt a wrapped file key using our session key
  Future<SecretKey> unwrapFileKey({
    required EncryptedPayload wrappedPayload,
    required SecretKey sessionKey,
  }) async {
    final rawBase64 = await decryptText(
      payload: wrappedPayload,
      secretKey: sessionKey,
    );
    final keyBytes = base64Decode(rawBase64);
    return SecretKey(keyBytes);
  }
}
