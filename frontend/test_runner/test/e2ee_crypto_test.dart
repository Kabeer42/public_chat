import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

// Standalone implementation of payload and cipher service for direct test verification
class EncryptedPayload {
  final String ciphertext;
  final String iv;
  final String mac;

  EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'iv': iv,
    'mac': mac,
  };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) => EncryptedPayload(
    ciphertext: json['ciphertext'] as String,
    iv: json['iv'] as String,
    mac: json['mac'] as String,
  );
}

class TestCipherService {
  final AesGcm _aesGcm = AesGcm.with256bits();

  AesGcm get aesGcm => _aesGcm;

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

  Future<Map<String, dynamic>> encryptFile({
    required Uint8List fileBytes,
  }) async {
    final oneTimeFileKey = await _aesGcm.newSecretKey();
    final fileKeyBytes = await oneTimeFileKey.extractBytes();

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

  Future<EncryptedPayload> wrapFileKey({
    required String fileKeyBase64,
    required SecretKey sessionKey,
  }) async {
    return await encryptText(
      plaintext: fileKeyBase64,
      secretKey: sessionKey,
    );
  }

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

void main() {
  late TestCipherService cipherService;
  late X25519 x25519;
  late Hkdf hkdf;

  setUp(() {
    cipherService = TestCipherService();
    x25519 = X25519();
    hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );
  });

  group('TASK-06: E2EE Cryptographic Engine Tests', () {
    test('1. X25519 KeyPair generation and public key serialization', () async {
      final keyPair = await x25519.newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final pubBase64 = base64Encode(pubKey.bytes);

      expect(pubBase64, isNotEmpty);
      expect(pubKey.bytes.length, 32); // Curve25519 public keys are 32 bytes
    });

    test('2. X25519 Diffie-Hellman + HKDF-SHA256 session key derivation parity', () async {
      final aliceKeyPair = await x25519.newKeyPair();
      final alicePubKey = await aliceKeyPair.extractPublicKey();

      final bobKeyPair = await x25519.newKeyPair();
      final bobPubKey = await bobKeyPair.extractPublicKey();

      // Alice derives session key using Bob's public key
      final aliceSharedSecret = await x25519.sharedSecretKey(
        keyPair: aliceKeyPair,
        remotePublicKey: bobPubKey,
      );
      final aliceSessionKey = await hkdf.deriveKey(
        secretKey: aliceSharedSecret,
        info: utf8.encode('chatapp-e2ee-session-key-v1'),
      );

      // Bob derives session key using Alice's public key
      final bobSharedSecret = await x25519.sharedSecretKey(
        keyPair: bobKeyPair,
        remotePublicKey: alicePubKey,
      );
      final bobSessionKey = await hkdf.deriveKey(
        secretKey: bobSharedSecret,
        info: utf8.encode('chatapp-e2ee-session-key-v1'),
      );

      final aliceKeyBytes = await aliceSessionKey.extractBytes();
      final bobKeyBytes = await bobSessionKey.extractBytes();

      expect(aliceKeyBytes, equals(bobKeyBytes));
      expect(aliceKeyBytes.length, 32); // 256-bit AES symmetric key
    });

    test('3. Text message AES-256-GCM encryption and decryption round-trip', () async {
      final secretKey = await cipherService.aesGcm.newSecretKey();
      const plaintext = 'Secret E2EE message: Hello World! 🚀🔒';

      final payload = await cipherService.encryptText(
        plaintext: plaintext,
        secretKey: secretKey,
      );

      expect(payload.ciphertext, isNotEmpty);
      expect(payload.iv, isNotEmpty);
      expect(payload.mac, isNotEmpty);
      expect(payload.ciphertext, isNot(contains('Hello World')));

      final decrypted = await cipherService.decryptText(
        payload: payload,
        secretKey: secretKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('4. Ciphertext tampering detection via authentication tag (MAC)', () async {
      final secretKey = await cipherService.aesGcm.newSecretKey();
      const plaintext = 'Authentic tamper-proof message';

      final payload = await cipherService.encryptText(
        plaintext: plaintext,
        secretKey: secretKey,
      );

      // Tamper with first byte of ciphertext
      final rawBytes = base64Decode(payload.ciphertext);
      rawBytes[0] ^= 0xFF;
      final tamperedPayload = EncryptedPayload(
        ciphertext: base64Encode(rawBytes),
        iv: payload.iv,
        mac: payload.mac,
      );

      expect(
        () async => await cipherService.decryptText(
          payload: tamperedPayload,
          secretKey: secretKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('5. Media file binary encryption and key wrapping round-trip', () async {
      final originalMediaBytes = Uint8List.fromList(
        List.generate(512, (i) => (i * 7 + 13) % 256),
      );

      final sessionKey = await cipherService.aesGcm.newSecretKey();

      // 1. Encrypt file with one-time AES key
      final encryptedMedia = await cipherService.encryptFile(fileBytes: originalMediaBytes);
      final encryptedBytes = encryptedMedia['encryptedBytes'] as Uint8List;
      final fileKeyBase64 = encryptedMedia['fileKeyBase64'] as String;
      final fileIv = encryptedMedia['iv'] as String;
      final fileMac = encryptedMedia['mac'] as String;

      expect(encryptedBytes, isNot(equals(originalMediaBytes)));

      // 2. Wrap file key with session key
      final wrappedKeyPayload = await cipherService.wrapFileKey(
        fileKeyBase64: fileKeyBase64,
        sessionKey: sessionKey,
      );

      // 3. Unwrap file key
      final unwrappedFileKey = await cipherService.unwrapFileKey(
        wrappedPayload: wrappedKeyPayload,
        sessionKey: sessionKey,
      );

      // 4. Decrypt media file
      final decryptedBytes = await cipherService.decryptFile(
        encryptedBytes: encryptedBytes,
        fileKey: unwrappedFileKey,
        ivBase64: fileIv,
        macBase64: fileMac,
      );

      expect(decryptedBytes, equals(originalMediaBytes));
    });
  });
}
