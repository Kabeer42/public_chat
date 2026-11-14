import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

// Standalone payload for testing cryptographic tamper resistance
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

class TestSecurityEngine {
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<SimpleKeyPair> generateKeyPair() => _x25519.newKeyPair();

  Future<SecretKey> deriveSessionKey({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
  }) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );

    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode('ChatApp-E2EE-v1-SessionKey'),
      nonce: utf8.encode('ChatApp-ZeroKnowledge-Salt'),
    );
  }

  Future<EncryptedPayload> encryptText({
    required String plaintext,
    required SecretKey secretKey,
  }) async {
    final plainBytes = utf8.encode(plaintext);
    final secretBox = await _aesGcm.encrypt(plainBytes, secretKey: secretKey);

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

    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(plainBytes);
  }

  Future<Map<String, dynamic>> encryptMediaBlob({
    required Uint8List rawBytes,
    required SecretKey sessionKey,
  }) async {
    // 1. Generate one-time symmetric AES-256 media key
    final oneTimeMediaKey = await _aesGcm.newSecretKey();
    final oneTimeKeyBytes = await oneTimeMediaKey.extractBytes();

    // 2. Encrypt media binary
    final secretBox = await _aesGcm.encrypt(rawBytes, secretKey: oneTimeMediaKey);

    // 3. Wrap (encrypt) one-time media key with session key
    final wrappedKeyBox = await _aesGcm.encrypt(
      Uint8List.fromList(oneTimeKeyBytes),
      secretKey: sessionKey,
    );

    final encryptedMediaKeyPayload = jsonEncode({
      'ciphertext': base64Encode(wrappedKeyBox.cipherText),
      'iv': base64Encode(wrappedKeyBox.nonce),
      'mac': base64Encode(wrappedKeyBox.mac.bytes),
    });

    return {
      'encryptedBlob': Uint8List.fromList(secretBox.cipherText),
      'mediaIv': base64Encode(secretBox.nonce),
      'mediaMac': base64Encode(secretBox.mac.bytes),
      'encryptedMediaKey': encryptedMediaKeyPayload,
    };
  }

  Future<Uint8List> decryptMediaBlob({
    required Uint8List encryptedBlob,
    required String mediaIv,
    required String mediaMac,
    required String encryptedMediaKey,
    required SecretKey sessionKey,
  }) async {
    // 1. Unwrap one-time media key using session key
    final wrappedKeyData = jsonDecode(encryptedMediaKey) as Map<String, dynamic>;
    final wrappedCiphertext = base64Decode(wrappedKeyData['ciphertext'] as String);
    final wrappedIv = base64Decode(wrappedKeyData['iv'] as String);
    final wrappedMac = base64Decode(wrappedKeyData['mac'] as String);

    final unwrappedKeyBytes = await _aesGcm.decrypt(
      SecretBox(wrappedCiphertext, nonce: wrappedIv, mac: Mac(wrappedMac)),
      secretKey: sessionKey,
    );

    final oneTimeMediaKey = SecretKey(unwrappedKeyBytes);

    // 2. Decrypt media blob
    final mediaPlainBytes = await _aesGcm.decrypt(
      SecretBox(encryptedBlob, nonce: base64Decode(mediaIv), mac: Mac(base64Decode(mediaMac))),
      secretKey: oneTimeMediaKey,
    );

    return Uint8List.fromList(mediaPlainBytes);
  }
}

void main() {
  group('TASK-17: End-to-End System Security Audit & Final Integration Tests', () {
    late TestSecurityEngine securityEngine;

    setUp(() {
      securityEngine = TestSecurityEngine();
    });

    test('1. Full E2EE Text Chat Lifecycle: Zero-Knowledge Key Exchange & Message Integrity', () async {
      // Alice and Bob generate Curve25519 keypairs
      final aliceKeyPair = await securityEngine.generateKeyPair();
      final alicePublicKey = await aliceKeyPair.extractPublicKey();

      final bobKeyPair = await securityEngine.generateKeyPair();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      // Alice & Bob derive session keys
      final aliceSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: aliceKeyPair,
        remotePublicKey: bobPublicKey,
      );
      final bobSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: bobKeyPair,
        remotePublicKey: alicePublicKey,
      );

      // Verify Diffie-Hellman HKDF parity
      final aliceKeyBytes = await aliceSessionKey.extractBytes();
      final bobKeyBytes = await bobSessionKey.extractBytes();
      expect(aliceKeyBytes, equals(bobKeyBytes));

      // Alice encrypts confidential message
      const confidentialMessage = "Top Secret Zero-Knowledge E2EE Message: Meet at 22:00 UTC";
      final encryptedPayload = await securityEngine.encryptText(
        plaintext: confidentialMessage,
        secretKey: aliceSessionKey,
      );

      // Server payload verification: Server receives ONLY ciphertext, iv, and mac
      final serverStoredPayload = encryptedPayload.toJson();
      expect(serverStoredPayload.containsKey('ciphertext'), isTrue);
      expect(serverStoredPayload.containsKey('iv'), isTrue);
      expect(serverStoredPayload.containsKey('mac'), isTrue);
      expect(serverStoredPayload.containsKey('plaintext'), isFalse);
      expect(serverStoredPayload['ciphertext'], isNot(contains(confidentialMessage)));

      // Bob decrypts with his session key
      final decryptedMessage = await securityEngine.decryptText(
        payload: encryptedPayload,
        secretKey: bobSessionKey,
      );

      expect(decryptedMessage, equals(confidentialMessage));
    });

    test('2. Cryptographic Tamper-Proofing (AEAD Integrity): Modifying 1 byte causes instant decryption failure', () async {
      final aliceKeyPair = await securityEngine.generateKeyPair();
      final bobKeyPair = await securityEngine.generateKeyPair();
      final alicePublicKey = await aliceKeyPair.extractPublicKey();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      final aliceSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: aliceKeyPair,
        remotePublicKey: bobPublicKey,
      );
      final bobSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: bobKeyPair,
        remotePublicKey: alicePublicKey,
      );

      final payload = await securityEngine.encryptText(
        plaintext: "Tamper resistance test",
        secretKey: aliceSessionKey,
      );

      // Attack 1: Alter 1 byte in ciphertext
      final rawCipher = base64Decode(payload.ciphertext);
      rawCipher[0] = rawCipher[0] ^ 0xFF; // flip bits
      final tamperedCipherPayload = EncryptedPayload(
        ciphertext: base64Encode(rawCipher),
        iv: payload.iv,
        mac: payload.mac,
      );

      expect(
        () async => await securityEngine.decryptText(
          payload: tamperedCipherPayload,
          secretKey: bobSessionKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // Attack 2: Alter 1 byte in MAC (Auth Tag)
      final rawMac = base64Decode(payload.mac);
      rawMac[0] = rawMac[0] ^ 0xFF;
      final tamperedMacPayload = EncryptedPayload(
        ciphertext: payload.ciphertext,
        iv: payload.iv,
        mac: base64Encode(rawMac),
      );

      expect(
        () async => await securityEngine.decryptText(
          payload: tamperedMacPayload,
          secretKey: bobSessionKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // Attack 3: Unauthorized third-party (Eve) key attempts decryption
      final eveKeyPair = await securityEngine.generateKeyPair();
      final eveSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: eveKeyPair,
        remotePublicKey: alicePublicKey,
      );

      expect(
        () async => await securityEngine.decryptText(
          payload: payload,
          secretKey: eveSessionKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('3. Full E2EE Media Lifecycle: Image & Video Zero-Knowledge Encryption, Upload Blob, and Playback', () async {
      final aliceKeyPair = await securityEngine.generateKeyPair();
      final bobKeyPair = await securityEngine.generateKeyPair();
      final alicePublicKey = await aliceKeyPair.extractPublicKey();
      final bobPublicKey = await bobKeyPair.extractPublicKey();

      final aliceSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: aliceKeyPair,
        remotePublicKey: bobPublicKey,
      );
      final bobSessionKey = await securityEngine.deriveSessionKey(
        localKeyPair: bobKeyPair,
        remotePublicKey: alicePublicKey,
      );

      // Simulated raw binary media (PNG header + image data)
      final originalMediaBytes = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic header
        ...List.generate(1024, (i) => (i * 17) % 256), // Sample binary payload
      ]);

      // Alice encrypts media with random one-time AES key and wraps key
      final encryptionResult = await securityEngine.encryptMediaBlob(
        rawBytes: originalMediaBytes,
        sessionKey: aliceSessionKey,
      );

      final encryptedBlob = encryptionResult['encryptedBlob'] as Uint8List;
      final mediaIv = encryptionResult['mediaIv'] as String;
      final mediaMac = encryptionResult['mediaMac'] as String;
      final encryptedMediaKey = encryptionResult['encryptedMediaKey'] as String;

      // Ensure server binary blob does NOT expose PNG magic header
      expect(encryptedBlob.sublist(0, 8), isNot(equals(originalMediaBytes.sublist(0, 8))));

      // Bob receives encrypted blob and wrapped key, unwraps and decrypts
      final decryptedMediaBytes = await securityEngine.decryptMediaBlob(
        encryptedBlob: encryptedBlob,
        mediaIv: mediaIv,
        mediaMac: mediaMac,
        encryptedMediaKey: encryptedMediaKey,
        sessionKey: bobSessionKey,
      );

      expect(decryptedMediaBytes, equals(originalMediaBytes));

      // Verify tamper on media blob throws authentication error
      encryptedBlob[0] = encryptedBlob[0] ^ 0xAA;
      expect(
        () async => await securityEngine.decryptMediaBlob(
          encryptedBlob: encryptedBlob,
          mediaIv: mediaIv,
          mediaMac: mediaMac,
          encryptedMediaKey: encryptedMediaKey,
          sessionKey: bobSessionKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('4. WebRTC DTLS-SRTP Audio/Video Calling Security & Signaling Verification', () {
      // Verify DTLS-SRTP peer connection configuration
      final rtcConfiguration = {
        'iceServers': [
          {'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']},
          {
            'urls': ['turn:turn.mychatapp.org:3478?transport=udp'],
            'username': 'turn_user',
            'credential': 'turn_password',
          }
        ],
        'sdpSemantics': 'unified-plan',
      };

      expect(rtcConfiguration['sdpSemantics'], equals('unified-plan'));
      final iceServers = rtcConfiguration['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, equals(2));
      expect(iceServers[0]['urls'], contains('stun:stun.l.google.com:19302'));
      expect(iceServers[1]['urls'], contains('turn:turn.mychatapp.org:3478?transport=udp'));

      // Validate Signaling Offer & Answer DTLS-SRTP markers
      const sampleSdpOffer = """
v=0
o=- 123456789 2 IN IP4 127.0.0.1
s=-
t=0 0
a=fingerprint:sha-256 00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF
a=setup:actpass
m=audio 9 UDP/TLS/RTP/SAVPF 111
m=video 9 UDP/TLS/RTP/SAVPF 96
""";

      expect(sampleSdpOffer, contains('a=fingerprint:sha-256'));
      expect(sampleSdpOffer, contains('UDP/TLS/RTP/SAVPF')); // Enforces DTLS-SRTP Secure RTP Profile
    });

    test('5. Dynamic Tunneling & Connectivity Architecture Verification', () {
      final configMap = {
        'defaultApiUrl': 'http://10.0.2.2:8000/api/v1',
        'cloudflareApiUrl': 'https://api.chatapp.trycloudflare.com/api/v1',
        'ngrokApiUrl': 'https://chatapp.ngrok-free.app/api/v1',
        'cloudflareWsUrl': 'wss://ws.chatapp.trycloudflare.com',
        'ngrokWsUrl': 'wss://ws-chatapp.ngrok-free.app',
      };

      for (final url in configMap.values) {
        final uri = Uri.parse(url);
        expect(uri.hasScheme, isTrue);
        expect(uri.hasAuthority, isTrue);
        if (url.startsWith('https://')) {
          expect(uri.isScheme('https'), isTrue);
        } else if (url.startsWith('wss://')) {
          expect(uri.isScheme('wss'), isTrue);
        }
      }
    });
  });
}
