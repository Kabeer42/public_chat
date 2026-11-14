import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

class TestEncryptedPayload {
  final String ciphertext;
  final String iv;
  final String mac;

  TestEncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'iv': iv,
    'mac': mac,
  };

  factory TestEncryptedPayload.fromJson(Map<String, dynamic> json) {
    return TestEncryptedPayload(
      ciphertext: json['ciphertext'] as String,
      iv: json['iv'] as String,
      mac: json['mac'] as String,
    );
  }
}

class TestMediaMessageModel {
  final int id;
  final int senderId;
  final int receiverId;
  final String messageType;
  final String ciphertext;
  final String iv;
  final String mac;
  final String? mediaUrl;
  final String? encryptedMediaKey;
  final DateTime createdAt;

  TestMediaMessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageType,
    required this.ciphertext,
    required this.iv,
    required this.mac,
    this.mediaUrl,
    this.encryptedMediaKey,
    required this.createdAt,
  });

  factory TestMediaMessageModel.fromJson(Map<String, dynamic> json) {
    return TestMediaMessageModel(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      messageType: json['message_type'] as String,
      ciphertext: json['ciphertext'] as String? ?? '',
      iv: json['iv'] as String? ?? '',
      mac: json['mac'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      encryptedMediaKey: json['encrypted_media_key'] as String?,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender_id': senderId,
    'receiver_id': receiverId,
    'message_type': messageType,
    'ciphertext': ciphertext,
    'iv': iv,
    'mac': mac,
    'media_url': mediaUrl,
    'encrypted_media_key': encryptedMediaKey,
    'created_at': createdAt.toIso8601String(),
  };
}

void main() {
  group('TASK-11: Flutter End-to-End Encrypted Media Sharing & Viewer Tests', () {
    late X25519 x25519;
    late Hkdf hkdf;
    late AesGcm aesGcm;

    setUp(() {
      x25519 = X25519();
      hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      aesGcm = AesGcm.with256bits();
    });

    test('1. TestMediaMessageModel parses backend JSON containing media_url and encrypted_media_key', () {
      final json = {
        'id': 101,
        'sender_id': 5,
        'receiver_id': 9,
        'message_type': 'image',
        'ciphertext': 'd3JhcHBlZEtleUNpcGhlcg==',
        'iv': 'ZmlsZUl2MTIzNA==',
        'mac': 'ZmlsZU1hYzEyMzQ1Njc4OQ==',
        'media_url': '/api/v1/media/550e8400-e29b-41d4-a716-446655440000',
        'encrypted_media_key': jsonEncode({
          'ciphertext': 'd3JhcHBlZEtleUNpcGhlcg==',
          'iv': 'a2V5SXYxMjM0',
          'mac': 'a2V5TWFjMTIzNDU2',
        }),
        'created_at': '2026-10-17T03:45:00.000Z',
      };

      final model = TestMediaMessageModel.fromJson(json);

      expect(model.id, 101);
      expect(model.senderId, 5);
      expect(model.receiverId, 9);
      expect(model.messageType, 'image');
      expect(model.mediaUrl, '/api/v1/media/550e8400-e29b-41d4-a716-446655440000');
      expect(model.encryptedMediaKey, isNotNull);

      final keyPayload = TestEncryptedPayload.fromJson(
        jsonDecode(model.encryptedMediaKey!) as Map<String, dynamic>,
      );
      expect(keyPayload.ciphertext, 'd3JhcHBlZEtleUNpcGhlcg==');
      expect(keyPayload.iv, 'a2V5SXYxMjM0');
      expect(keyPayload.mac, 'a2V5TWFjMTIzNDU2');
    });

    test('2. Complete Image E2EE Sharing Flow: One-time AES key encryption, session key wrapping, and local decryption', () async {
      // 1. Setup Alice and Bob cryptographic identity keypairs
      final aliceKeyPair = await x25519.newKeyPair();
      final alicePublicKey = await aliceKeyPair.extractPublicKey();

      final bobKeyPair = await x25519.newKeyPair();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      // Alice derives session key for Bob
      final aliceSharedSecret = await x25519.sharedSecretKey(keyPair: aliceKeyPair, remotePublicKey: bobPublicKey);
      final aliceSessionKey = await hkdf.deriveKey(secretKey: aliceSharedSecret, info: utf8.encode('chatapp-e2ee-session-key-v1'));

      // 2. Prepare sample image raw binary data (e.g., PNG header + image bytes)
      final rawImageBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG Header
        ...List.generate(2048, (i) => (i * 7) % 256), // Sample pixel data
      ]);

      // 3. Sender creates random one-time 256-bit AES key for the media file
      final oneTimeFileKey = await aesGcm.newSecretKey();
      final fileKeyBytes = await oneTimeFileKey.extractBytes();
      final fileKeyBase64 = base64Encode(fileKeyBytes);

      // Encrypt the raw image bytes with the one-time file key
      final fileSecretBox = await aesGcm.encrypt(rawImageBytes, secretKey: oneTimeFileKey);
      final encryptedFileBytes = Uint8List.fromList(fileSecretBox.cipherText);
      final fileIv = base64Encode(fileSecretBox.nonce);
      final fileMac = base64Encode(fileSecretBox.mac.bytes);

      // Verify that encrypted binary data does NOT leak PNG header magic bytes
      expect(encryptedFileBytes.sublist(0, 8), isNot(equals(rawImageBytes.sublist(0, 8))));

      // 4. Sender wraps the one-time file key using the peer session key
      final wrappedKeySecretBox = await aesGcm.encrypt(utf8.encode(fileKeyBase64), secretKey: aliceSessionKey);
      final wrappedKeyPayload = TestEncryptedPayload(
        ciphertext: base64Encode(wrappedKeySecretBox.cipherText),
        iv: base64Encode(wrappedKeySecretBox.nonce),
        mac: base64Encode(wrappedKeySecretBox.mac.bytes),
      );

      // 5. Simulated payload uploaded to backend and received by Bob
      final backendMessage = TestMediaMessageModel(
        id: 202,
        senderId: 1, // Alice
        receiverId: 2, // Bob
        messageType: 'image',
        ciphertext: wrappedKeyPayload.ciphertext,
        iv: fileIv,
        mac: fileMac,
        mediaUrl: '/api/v1/media/b44f24ef-941f-4b09-b6bb-fdfaef3d9441',
        encryptedMediaKey: jsonEncode(wrappedKeyPayload.toJson()),
        createdAt: DateTime.now(),
      );

      // 6. Bob receives message and decrypts the wrapped key using his session key
      final bobSharedSecret = await x25519.sharedSecretKey(keyPair: bobKeyPair, remotePublicKey: alicePublicKey);
      final bobSessionKey = await hkdf.deriveKey(secretKey: bobSharedSecret, info: utf8.encode('chatapp-e2ee-session-key-v1'));

      final receivedKeyPayload = TestEncryptedPayload.fromJson(
        jsonDecode(backendMessage.encryptedMediaKey!) as Map<String, dynamic>,
      );

      final unwrappedKeyBytes = await aesGcm.decrypt(
        SecretBox(
          base64Decode(receivedKeyPayload.ciphertext),
          nonce: base64Decode(receivedKeyPayload.iv),
          mac: Mac(base64Decode(receivedKeyPayload.mac)),
        ),
        secretKey: bobSessionKey,
      );
      final recoveredFileKeyBase64 = utf8.decode(unwrappedKeyBytes);
      expect(recoveredFileKeyBase64, equals(fileKeyBase64));

      // 7. Bob decrypts the binary media payload with recovered file key
      final bobRecoveredFileKey = SecretKey(base64Decode(recoveredFileKeyBase64));
      final decryptedImageBytes = await aesGcm.decrypt(
        SecretBox(
          encryptedFileBytes,
          nonce: base64Decode(backendMessage.iv),
          mac: Mac(base64Decode(backendMessage.mac)),
        ),
        secretKey: bobRecoveredFileKey,
      );

      // 8. Assert decrypted bytes exactly match original image bytes
      expect(Uint8List.fromList(decryptedImageBytes), equals(rawImageBytes));
      expect(decryptedImageBytes.sublist(0, 8), equals([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]));
    });

    test('3. Video E2EE Sharing Flow: Preserves video data integrity across encryption and decryption round-trip', () async {
      final aliceKeyPair = await x25519.newKeyPair();
      final alicePub = await aliceKeyPair.extractPublicKey();

      final bobKeyPair = await x25519.newKeyPair();
      final bobPub = await bobKeyPair.extractPublicKey();

      final aliceSecret = await x25519.sharedSecretKey(keyPair: aliceKeyPair, remotePublicKey: bobPub);
      final aliceSessionKey = await hkdf.deriveKey(secretKey: aliceSecret, info: utf8.encode('chatapp-e2ee-session-key-v1'));

      // Sample MP4 video binary header + simulated video chunks (10 KB)
      final rawVideoBytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // 'ftyp' MP4 box
        0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
        ...List.generate(10240, (i) => (i * 13) % 256),
      ]);

      // Encrypt with one-time AES-256 key
      final videoKey = await aesGcm.newSecretKey();
      final videoKeyBytes = await videoKey.extractBytes();
      final videoSecretBox = await aesGcm.encrypt(rawVideoBytes, secretKey: videoKey);

      // Wrap video key for Bob
      final wrappedKeyBox = await aesGcm.encrypt(videoKeyBytes, secretKey: aliceSessionKey);

      // Bob decrypts
      final bobSecret = await x25519.sharedSecretKey(keyPair: bobKeyPair, remotePublicKey: alicePub);
      final bobSessionKey = await hkdf.deriveKey(secretKey: bobSecret, info: utf8.encode('chatapp-e2ee-session-key-v1'));

      final unwrappedVideoKeyBytes = await aesGcm.decrypt(wrappedKeyBox, secretKey: bobSessionKey);
      final recoveredVideoKey = SecretKey(unwrappedVideoKeyBytes);

      final decryptedVideoBytes = await aesGcm.decrypt(videoSecretBox, secretKey: recoveredVideoKey);
      expect(Uint8List.fromList(decryptedVideoBytes), equals(rawVideoBytes));
    });

    test('4. Zero-Knowledge validation: Tampered ciphertext or wrong key fails decryption', () async {
      final key1 = await aesGcm.newSecretKey();
      final key2 = await aesGcm.newSecretKey();

      final testData = utf8.encode('Highly confidential media contents');
      final secretBox = await aesGcm.encrypt(testData, secretKey: key1);

      // Attempt decryption with wrong key
      expect(
        () async => await aesGcm.decrypt(secretBox, secretKey: key2),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // Attempt decryption with tampered ciphertext
      final tamperedCipherText = List<int>.from(secretBox.cipherText);
      tamperedCipherText[0] ^= 0xFF;
      final tamperedBox = SecretBox(
        tamperedCipherText,
        nonce: secretBox.nonce,
        mac: secretBox.mac,
      );

      expect(
        () async => await aesGcm.decrypt(tamperedBox, secretKey: key1),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });
}
