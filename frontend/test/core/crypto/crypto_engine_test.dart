import 'dart:convert';
import 'dart:typed_data';
import 'package:chatapp/core/crypto/cipher_service.dart';
import 'package:chatapp/core/crypto/key_exchange_service.dart';
import 'package:chatapp/core/crypto/key_manager.dart';
import 'package:chatapp/core/crypto/models/encrypted_payload.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// In-memory mock for FlutterSecureStorage
class MockSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _store[key] = value;
    } else {
      _store.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _store[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _store.remove(key);
  }
}

void main() {
  late MockSecureStorage aliceStorage;
  late MockSecureStorage bobStorage;
  late KeyManager aliceKeyManager;
  late KeyManager bobKeyManager;
  late KeyExchangeService aliceKeyExchange;
  late KeyExchangeService bobKeyExchange;
  late CipherService cipherService;

  setUp(() {
    aliceStorage = MockSecureStorage();
    bobStorage = MockSecureStorage();

    aliceKeyManager = KeyManager(aliceStorage);
    bobKeyManager = KeyManager(bobStorage);

    aliceKeyExchange = KeyExchangeService(aliceKeyManager);
    bobKeyExchange = KeyExchangeService(bobKeyManager);

    cipherService = CipherService();
  });

  group('E2EE Cryptographic Engine Tests', () {
    test('KeyManager generates and securely stores X25519 key pair', () async {
      final keyPair = await aliceKeyManager.generateAndSaveKeyPair();
      expect(keyPair, isNotNull);

      final pubBase64 = await aliceKeyManager.getPublicKeyBase64();
      expect(pubBase64, isNotEmpty);

      // Verify persistence in secure storage
      expect(await aliceKeyManager.hasKeyPair(), isTrue);

      // Calling getOrGenerateKeyPair should return the persisted key
      final retrievedKeyPair = await aliceKeyManager.getOrGenerateKeyPair();
      final retrievedPub = await retrievedKeyPair.extractPublicKey();
      expect(base64Encode(retrievedPub.bytes), pubBase64);
    });

    test('X25519 Diffie-Hellman Key Exchange produces identical session keys on both sides', () async {
      // Alice generates key pair
      await aliceKeyManager.generateAndSaveKeyPair();
      final alicePubBase64 = await aliceKeyManager.getPublicKeyBase64();

      // Bob generates key pair
      await bobKeyManager.generateAndSaveKeyPair();
      final bobPubBase64 = await bobKeyManager.getPublicKeyBase64();

      // Alice derives session key using Bob's public key
      final aliceSessionKey = await aliceKeyExchange.getSessionKeyForPeer(
        peerId: 2,
        peerPublicKeyBase64: bobPubBase64,
      );

      // Bob derives session key using Alice's public key
      final bobSessionKey = await bobKeyExchange.getSessionKeyForPeer(
        peerId: 1,
        peerPublicKeyBase64: alicePubBase64,
      );

      final aliceKeyBytes = await aliceSessionKey.extractBytes();
      final bobKeyBytes = await bobSessionKey.extractBytes();

      // Both independently calculated keys MUST be identical 256-bit secrets
      expect(aliceKeyBytes, equals(bobKeyBytes));
      expect(aliceKeyBytes.length, 32); // 256 bits
    });

    test('Text message encryption and decryption round-trip via AES-256-GCM', () async {
      final secretKey = await cipherService.aesGcm.newSecretKey();
      const plaintext = 'Secret E2EE message: Hello World! 🚀🔒';

      // Encrypt
      final payload = await cipherService.encryptText(
        plaintext: plaintext,
        secretKey: secretKey,
      );

      expect(payload.ciphertext, isNotEmpty);
      expect(payload.iv, isNotEmpty);
      expect(payload.mac, isNotEmpty);
      expect(payload.ciphertext, isNot(contains('Hello World')));

      // Decrypt
      final decrypted = await cipherService.decryptText(
        payload: payload,
        secretKey: secretKey,
      );

      expect(decrypted, equals(plaintext));
    });

    test('Tampering with ciphertext causes authentication tag failure', () async {
      final secretKey = await cipherService.aesGcm.newSecretKey();
      const plaintext = 'Authentic message';

      final payload = await cipherService.encryptText(
        plaintext: plaintext,
        secretKey: secretKey,
      );

      // Corrupt 1 byte in ciphertext
      final rawBytes = base64Decode(payload.ciphertext);
      rawBytes[0] ^= 0xFF; // Flip bits
      final tamperedPayload = EncryptedPayload(
        ciphertext: base64Encode(rawBytes),
        iv: payload.iv,
        mac: payload.mac,
      );

      // Decryption must throw SecretBoxAuthenticationError
      expect(
        () async => await cipherService.decryptText(
          payload: tamperedPayload,
          secretKey: secretKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('Media binary file encryption and key wrapping round-trip', () async {
      // Dummy image/video binary payload
      final originalMediaBytes = Uint8List.fromList(
        List.generate(512, (i) => (i * 7 + 13) % 256),
      );

      // Generate session key between Alice and Bob
      final sessionKey = await cipherService.aesGcm.newSecretKey();

      // 1. Sender encrypts media file with one-time AES key
      final encryptedMedia = await cipherService.encryptFile(fileBytes: originalMediaBytes);
      final encryptedBytes = encryptedMedia['encryptedBytes'] as Uint8List;
      final fileKeyBase64 = encryptedMedia['fileKeyBase64'] as String;
      final fileIv = encryptedMedia['iv'] as String;
      final fileMac = encryptedMedia['mac'] as String;

      expect(encryptedBytes, isNot(equals(originalMediaBytes)));

      // 2. Sender wraps file key for recipient
      final wrappedKeyPayload = await cipherService.wrapFileKey(
        fileKeyBase64: fileKeyBase64,
        sessionKey: sessionKey,
      );

      // 3. Recipient unwraps file key
      final unwrappedFileKey = await cipherService.unwrapFileKey(
        wrappedPayload: wrappedKeyPayload,
        sessionKey: sessionKey,
      );

      // 4. Recipient decrypts media file
      final decryptedBytes = await cipherService.decryptFile(
        encryptedBytes: encryptedBytes,
        fileKey: unwrappedFileKey,
        ivBase64: fileIv,
        macBase64: fileMac,
      );

      expect(decryptedBytes, equals(originalMediaBytes));
    });

    test('6-Digit PIN Backup & Restore round-trip', () async {
      final keyManager = KeyManager(MockSecureStorage());
      await keyManager.generateAndSaveKeyPair();
      final originalPublicKey = await keyManager.getPublicKeyBase64();

      // Export encrypted with PIN "123456"
      final backupJson = await keyManager.exportBackupWithPin('123456');
      expect(backupJson, contains('"ciphertext"'));
      expect(backupJson, contains('"salt"'));

      // Simulate new device (clear keys)
      await keyManager.clearKeys();
      expect(await keyManager.hasKeyPair(), isFalse);

      // Try restoring with wrong PIN -> should fail
      final wrongPinResult = await keyManager.restoreBackupWithPin(
        backupJson: backupJson,
        pin: '999999',
      );
      expect(wrongPinResult, isFalse);
      expect(await keyManager.hasKeyPair(), isFalse);

      // Restore with correct PIN -> should succeed
      final correctPinResult = await keyManager.restoreBackupWithPin(
        backupJson: backupJson,
        pin: '123456',
      );
      expect(correctPinResult, isTrue);
      expect(await keyManager.hasKeyPair(), isTrue);

      final restoredPublicKey = await keyManager.getPublicKeyBase64();
      expect(restoredPublicKey, equals(originalPublicKey));
    });
  });
}
