import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

class KeyManager {
  static const String _prefPrivateKey = 'e2ee_identity_private_key';
  static const String _prefPublicKey = 'e2ee_identity_public_key';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences? _prefs;
  final X25519 _algorithm = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();

  SimpleKeyPair? _cachedKeyPair;

  KeyManager(this._secureStorage, [this._prefs]);

  X25519 get algorithm => _algorithm;

  /// Check if an identity key pair already exists on the device
  Future<bool> hasKeyPair() async {
    final priv = _prefs?.getString(_prefPrivateKey) ?? await _secureStorage.read(key: _prefPrivateKey);
    final pub = _prefs?.getString(_prefPublicKey) ?? await _secureStorage.read(key: _prefPublicKey);
    return priv != null && pub != null;
  }

  /// Load existing key pair from storage if present, without auto-generating
  Future<SimpleKeyPair?> loadExistingKeyPair() async {
    if (_cachedKeyPair != null) {
      return _cachedKeyPair;
    }

    String? privBase64 = _prefs?.getString(_prefPrivateKey);
    String? pubBase64 = _prefs?.getString(_prefPublicKey);

    if (privBase64 == null || pubBase64 == null) {
      try {
        privBase64 ??= await _secureStorage.read(key: _prefPrivateKey);
        pubBase64 ??= await _secureStorage.read(key: _prefPublicKey);
        if (privBase64 != null && pubBase64 != null) {
          await _prefs?.setString(_prefPrivateKey, privBase64);
          await _prefs?.setString(_prefPublicKey, pubBase64);
        }
      } catch (_) {}
    }

    if (privBase64 != null && pubBase64 != null) {
      final privBytes = base64Decode(privBase64);
      final pubBytes = base64Decode(pubBase64);

      _cachedKeyPair = SimpleKeyPairData(
        privBytes,
        publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );
      return _cachedKeyPair;
    }

    return null;
  }

  /// Generate a new Curve25519 (X25519) identity key pair and store in secure storage & prefs
  Future<SimpleKeyPair> generateAndSaveKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    final pubBase64 = base64Encode(publicKey.bytes);
    final privBase64 = base64Encode(privateKeyBytes);

    await _prefs?.setString(_prefPublicKey, pubBase64);
    await _prefs?.setString(_prefPrivateKey, privBase64);

    try {
      await _secureStorage.write(key: _prefPublicKey, value: pubBase64);
      await _secureStorage.write(key: _prefPrivateKey, value: privBase64);
    } catch (_) {}

    _cachedKeyPair = keyPair;
    AppLogger.i('Generated and stored new X25519 identity key pair');
    return keyPair;
  }

  /// Save an externally restored or generated key pair
  Future<void> saveKeyPair(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    final pubBase64 = base64Encode(publicKey.bytes);
    final privBase64 = base64Encode(privateKeyBytes);

    await _prefs?.setString(_prefPublicKey, pubBase64);
    await _prefs?.setString(_prefPrivateKey, privBase64);

    try {
      await _secureStorage.write(key: _prefPublicKey, value: pubBase64);
      await _secureStorage.write(key: _prefPrivateKey, value: privBase64);
    } catch (_) {}

    _cachedKeyPair = keyPair;
  }

  /// Get the existing key pair, or generate a new one if it does not exist
  Future<SimpleKeyPair> getOrGenerateKeyPair() async {
    final existing = await loadExistingKeyPair();
    if (existing != null) return existing;
    return await generateAndSaveKeyPair();
  }

  /// Export the private key encrypted with a 6-digit PIN via PBKDF2 & AES-256-GCM
  Future<String> exportBackupWithPin(String pin) async {
    final keyPair = await getOrGenerateKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = await keyPair.extractPublicKey();

    // 16-byte random salt for PBKDF2 key derivation
    final salt = Uint8List(16);
    final rng = Random.secure();
    for (int i = 0; i < salt.length; i++) {
      salt[i] = rng.nextInt(256);
    }

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 10000,
      bits: 256,
    );

    final derivedKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin.trim())),
      nonce: salt,
    );

    // Encrypt private key bytes with AES-GCM
    final secretBox = await _aesGcm.encrypt(
      privateKeyBytes,
      secretKey: derivedKey,
    );

    return jsonEncode({
      'v': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
      'pub': base64Encode(publicKey.bytes),
    });
  }

  /// Restore private key from backup JSON using user's PIN. Returns true on success, false if PIN incorrect.
  Future<bool> restoreBackupWithPin({
    required String backupJson,
    required String pin,
  }) async {
    try {
      final Map<String, dynamic> data = jsonDecode(backupJson);
      final salt = base64Decode(data['salt'] as String);
      final nonce = base64Decode(data['nonce'] as String);
      final ciphertext = base64Decode(data['ciphertext'] as String);
      final mac = base64Decode(data['mac'] as String);
      final pubBytes = base64Decode(data['pub'] as String);

      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 10000,
        bits: 256,
      );

      final derivedKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(pin.trim())),
        nonce: salt,
      );

      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(mac),
      );

      final privateKeyBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: derivedKey,
      );

      final restoredKeyPair = SimpleKeyPairData(
        privateKeyBytes,
        publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );

      await saveKeyPair(restoredKeyPair);
      AppLogger.i('Restored and verified X25519 identity key from PIN backup');
      return true;
    } catch (e) {
      AppLogger.w('Failed to decrypt key backup with PIN: $e');
      return false;
    }
  }

  /// Export the public key as Base64 string for sharing with the backend
  Future<String> getPublicKeyBase64() async {
    final keyPair = await getOrGenerateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Clear stored keys (used on account deletion or test resets)
  Future<void> clearKeys() async {
    _cachedKeyPair = null;
    await _prefs?.remove(_prefPrivateKey);
    await _prefs?.remove(_prefPublicKey);
    try {
      await _secureStorage.delete(key: _prefPrivateKey);
      await _secureStorage.delete(key: _prefPublicKey);
    } catch (_) {}
  }
}
