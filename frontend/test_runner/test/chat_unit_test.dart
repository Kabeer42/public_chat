import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

// Standalone model and crypto test for Chat flow
class TestMessageModel {
  final int id;
  final int senderId;
  final int receiverId;
  final String messageType;
  final String ciphertext;
  final String iv;
  final String mac;
  final String? plaintext;
  final bool isDelivered;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;

  TestMessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.messageType,
    required this.ciphertext,
    required this.iv,
    required this.mac,
    this.plaintext,
    this.isDelivered = false,
    this.isRead = false,
    this.readAt,
    required this.createdAt,
  });

  factory TestMessageModel.fromJson(Map<String, dynamic> json) {
    return TestMessageModel(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      receiverId: json['receiver_id'] as int,
      messageType: json['message_type'] as String? ?? 'text',
      ciphertext: json['ciphertext'] as String? ?? '',
      iv: json['iv'] as String? ?? '',
      mac: json['mac'] as String? ?? '',
      isDelivered: json['is_delivered'] == true,
      isRead: json['is_read'] == true,
      readAt: json['read_at'] != null ? DateTime.tryParse(json['read_at']) : null,
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
    'is_delivered': isDelivered,
    'is_read': isRead,
    'read_at': readAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  TestMessageModel copyWith({
    String? plaintext,
    bool? isDelivered,
    bool? isRead,
    DateTime? readAt,
  }) {
    return TestMessageModel(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      messageType: messageType,
      ciphertext: ciphertext,
      iv: iv,
      mac: mac,
      plaintext: plaintext ?? this.plaintext,
      isDelivered: isDelivered ?? this.isDelivered,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }
}

void main() {
  group('TASK-09: Flutter 1-to-1 Real-Time E2EE Text Chat Flow Tests', () {
    test('1. MessageModel parses JSON from Laravel backend and preserves zero-knowledge fields', () {
      final json = {
        'id': 42,
        'sender_id': 10,
        'receiver_id': 20,
        'message_type': 'text',
        'ciphertext': 'VGVzdENpcGhlclRleHQ=',
        'iv': 'YXNkZjEyMzQ=',
        'mac': 'bWFjMTIzNDU2Nzg5',
        'is_delivered': true,
        'is_read': false,
        'read_at': null,
        'created_at': '2026-10-17T03:30:00.000Z',
      };

      final message = TestMessageModel.fromJson(json);

      expect(message.id, 42);
      expect(message.senderId, 10);
      expect(message.receiverId, 20);
      expect(message.ciphertext, 'VGVzdENpcGhlclRleHQ=');
      expect(message.isDelivered, true);
      expect(message.isRead, false);
      expect(message.plaintext, isNull); // Plaintext is NOT present on backend!
    });

    test('2. Complete 1-to-1 Chat E2EE flow: Alice encrypts -> Server stores -> Bob decrypts', () async {
      final x25519 = X25519();
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final aesGcm = AesGcm.with256bits();

      // Alice & Bob generate their X25519 identity keypairs
      final aliceKeyPair = await x25519.newKeyPair();
      final alicePub = await aliceKeyPair.extractPublicKey();

      final bobKeyPair = await x25519.newKeyPair();
      final bobPub = await bobKeyPair.extractPublicKey();

      // Alice derives session key to send to Bob
      final aliceSharedSecret = await x25519.sharedSecretKey(keyPair: aliceKeyPair, remotePublicKey: bobPub);
      final aliceSessionKey = await hkdf.deriveKey(secretKey: aliceSharedSecret, info: utf8.encode('chatapp-e2ee-session-key-v1'));

      // 1. Alice types plaintext
      const originalPlaintext = 'Meet me at the coffee shop at 5 PM! ☕🔐';

      // 2. Alice device encrypts with AES-256-GCM
      final secretBox = await aesGcm.encrypt(utf8.encode(originalPlaintext), secretKey: aliceSessionKey);
      final ciphertextBase64 = base64Encode(secretBox.cipherText);
      final ivBase64 = base64Encode(secretBox.nonce);
      final macBase64 = base64Encode(secretBox.mac.bytes);

      // Verify payload sent over network contains zero plaintext
      expect(ciphertextBase64, isNot(contains('Meet me')));
      expect(ciphertextBase64, isNot(contains('coffee')));

      // 3. Simulated Laravel backend storage and Reverb payload
      final backendMessageJson = {
        'id': 1,
        'sender_id': 1, // Alice
        'receiver_id': 2, // Bob
        'message_type': 'text',
        'ciphertext': ciphertextBase64,
        'iv': ivBase64,
        'mac': macBase64,
        'is_delivered': false,
        'is_read': false,
        'read_at': null,
        'created_at': DateTime.now().toIso8601String(),
      };

      // 4. Bob receives Reverb WebSocket event and parses model
      final bobReceivedModel = TestMessageModel.fromJson(backendMessageJson);

      // Bob derives same session key using Alice's public key
      final bobSharedSecret = await x25519.sharedSecretKey(keyPair: bobKeyPair, remotePublicKey: alicePub);
      final bobSessionKey = await hkdf.deriveKey(secretKey: bobSharedSecret, info: utf8.encode('chatapp-e2ee-session-key-v1'));

      // Bob decrypts payload
      final bobSecretBox = SecretBox(
        base64Decode(bobReceivedModel.ciphertext),
        nonce: base64Decode(bobReceivedModel.iv),
        mac: Mac(base64Decode(bobReceivedModel.mac)),
      );

      final decryptedBytes = await aesGcm.decrypt(bobSecretBox, secretKey: bobSessionKey);
      final decryptedPlaintext = utf8.decode(decryptedBytes);

      // Verify Bob successfully views original plaintext
      expect(decryptedPlaintext, equals(originalPlaintext));

      // 5. Bob marks message as read and updates model locally
      final readMessage = bobReceivedModel.copyWith(
        plaintext: decryptedPlaintext,
        isRead: true,
        isDelivered: true,
        readAt: DateTime.now(),
      );

      expect(readMessage.isRead, true);
      expect(readMessage.plaintext, originalPlaintext);
    });
  });
}
