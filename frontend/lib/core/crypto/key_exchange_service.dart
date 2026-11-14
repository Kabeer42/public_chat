import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import '../utils/app_logger.dart';
import 'key_manager.dart';

class KeyExchangeService {
  static const String _hkdfInfo = 'chatapp-e2ee-session-key-v1';

  final KeyManager _keyManager;
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32, // 256-bit AES key
  );

  // In-memory cache for derived peer session keys to avoid redundant ECDH computations
  final Map<String, SecretKey> _sessionKeyCache = {};

  KeyExchangeService(this._keyManager);

  /// Derive or retrieve a cached 256-bit AES session key for the given peer user
  Future<SecretKey> getSessionKeyForPeer({
    required int peerId,
    required String peerPublicKeyBase64,
  }) async {
    final cleanKey = peerPublicKeyBase64.trim();
    if (cleanKey.isEmpty) {
      throw ArgumentError('peerPublicKeyBase64 cannot be empty for peer #$peerId');
    }

    final cacheKey = '$peerId:$cleanKey';
    if (_sessionKeyCache.containsKey(cacheKey)) {
      return _sessionKeyCache[cacheKey]!;
    }

    final myKeyPair = await _keyManager.getOrGenerateKeyPair();
    final peerPublicKeyBytes = base64Decode(cleanKey);
    final peerPublicKey = SimplePublicKey(
      peerPublicKeyBytes,
      type: KeyPairType.x25519,
    );

    // 1. Compute Diffie-Hellman shared secret
    final sharedSecret = await _keyManager.algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    // 2. Derive 256-bit AES key using HKDF-SHA256
    final sessionKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode(_hkdfInfo),
    );

    _sessionKeyCache[cacheKey] = sessionKey;
    AppLogger.d('Derived E2EE session key for peer #$peerId via X25519 & HKDF-SHA256');
    return sessionKey;
  }

  /// Manually derive a session key from two raw keys (useful in unit testing)
  Future<SecretKey> deriveSessionKeyFromRaw({
    required KeyPair myKeyPair,
    required PublicKey peerPublicKey,
  }) async {
    final sharedSecret = await _keyManager.algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    return await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode(_hkdfInfo),
    );
  }

  /// Clear cached session keys (e.g. on logout)
  void clearCache() {
    _sessionKeyCache.clear();
  }
}
