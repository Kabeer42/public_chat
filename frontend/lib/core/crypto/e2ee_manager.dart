import 'dart:typed_data';
import '../constants/api_endpoints.dart';

import '../network/api_client.dart';
import '../utils/app_logger.dart';
import 'cipher_service.dart';
import 'key_exchange_service.dart';
import 'key_manager.dart';
import 'models/encrypted_payload.dart';

class E2eeManager {
  final KeyManager _keyManager;
  final KeyExchangeService _keyExchangeService;
  final CipherService _cipherService;
  final ApiClient _apiClient;

  bool _isPublicKeySynced = false;

  E2eeManager({
    required KeyManager keyManager,
    required KeyExchangeService keyExchangeService,
    required CipherService cipherService,
    required ApiClient apiClient,
  })  : _keyManager = keyManager,
        _keyExchangeService = keyExchangeService,
        _cipherService = cipherService,
        _apiClient = apiClient;

  KeyManager get keyManager => _keyManager;
  KeyExchangeService get keyExchangeService => _keyExchangeService;
  CipherService get cipherService => _cipherService;
  bool get isPublicKeySynced => _isPublicKeySynced;

  /// Initialize local keys (loads if existing, avoids premature generation on new installs)
  Future<void> initialize() async {
    await _keyManager.loadExistingKeyPair();
    AppLogger.i('E2EE Cryptographic Engine Initialized');
  }

  /// Check if the backend has an encrypted key backup for this account
  Future<({bool hasBackup, String? backupData})> fetchCloudBackup() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.keyBackup);
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        return (
          hasBackup: data['has_backup'] == true,
          backupData: data['backup_data'] as String?,
        );
      }
    } catch (e) {
      AppLogger.w('Failed to check cloud key backup: $e');
    }
    return (hasBackup: false, backupData: null);
  }

  /// Create encrypted backup with PIN and upload to backend
  Future<({bool success, String? error})> setupPinBackup(String pin) async {
    try {
      final backupJson = await _keyManager.exportBackupWithPin(pin);
      final response = await _apiClient.post(
        ApiEndpoints.keyBackup,
        data: {'backup_data': backupJson},
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.i('E2EE private key backup uploaded successfully');
        return (success: true, error: null);
      }
      return (success: false, error: 'Server returned ${response.statusCode}');
    } catch (e) {
      AppLogger.e('Failed to upload key backup', e);
      final errorMsg = e.toString().replaceAll('ApiException: ', '');
      return (success: false, error: errorMsg);
    }
  }

  /// Restore private key from cloud backup using user PIN
  Future<({bool success, String? error})> restoreKeyWithPin(String pin) async {
    try {
      final backupInfo = await fetchCloudBackup();
      if (!backupInfo.hasBackup || backupInfo.backupData == null) {
        return (success: false, error: 'No cloud backup found on server.');
      }
      final success = await _keyManager.restoreBackupWithPin(
        backupJson: backupInfo.backupData!,
        pin: pin,
      );
      if (success) {
        _isPublicKeySynced = true;
        await syncPublicKeyWithBackend();
        return (success: true, error: null);
      }
      return (success: false, error: 'Incorrect PIN. Please try again.');
    } catch (e) {
      AppLogger.w('Restore key with PIN failed: $e');
      final errorMsg = e.toString().replaceAll('ApiException: ', '');
      return (success: false, error: errorMsg);
    }
  }

  /// If user forgot PIN, reset keys and start fresh
  Future<({bool success, String? error})> resetKeysAndStartFresh(String newPin) async {
    try {
      await _keyManager.clearKeys();
      await _keyManager.generateAndSaveKeyPair();
      final newPublicKey = await _keyManager.getPublicKeyBase64();

      await _apiClient.post(ApiEndpoints.resetKeys);
      await _apiClient.post(ApiEndpoints.publishKey, data: {
        'public_identity_key': newPublicKey,
      });

      final backupResult = await setupPinBackup(newPin);
      _isPublicKeySynced = true;
      AppLogger.i('E2EE keys reset and new PIN backup created');
      return backupResult;
    } catch (e) {
      AppLogger.e('Failed to reset E2EE keys', e);
      final errorMsg = e.toString().replaceAll('ApiException: ', '');
      return (success: false, error: errorMsg);
    }
  }

  /// Publish the local public key to the Laravel backend
  Future<bool> syncPublicKeyWithBackend() async {
    try {
      final hasKey = await _keyManager.hasKeyPair();
      if (!hasKey) {
        AppLogger.w('Skipping public key sync: local keypair not yet restored or initialized');
        return false;
      }
      final publicKeyBase64 = await _keyManager.getPublicKeyBase64();
      final response = await _apiClient.post(
        ApiEndpoints.publishKey,
        data: {
          'public_identity_key': publicKeyBase64,
        },
      );

      if (response.statusCode == 200) {
        _isPublicKeySynced = true;
        AppLogger.i('Public key successfully registered on backend');
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.e('Failed to sync public key with backend', e);
      return false;
    }
  }

  /// Encrypt a text message for a peer
  Future<EncryptedPayload> encryptMessage({
    required int peerId,
    required String peerPublicKeyBase64,
    required String plaintext,
  }) async {
    final sessionKey = await _keyExchangeService.getSessionKeyForPeer(
      peerId: peerId,
      peerPublicKeyBase64: peerPublicKeyBase64,
    );

    return await _cipherService.encryptText(
      plaintext: plaintext,
      secretKey: sessionKey,
    );
  }

  /// Decrypt a text message received from a peer
  Future<String> decryptMessage({
    required int peerId,
    required String peerPublicKeyBase64,
    required EncryptedPayload payload,
  }) async {
    final sessionKey = await _keyExchangeService.getSessionKeyForPeer(
      peerId: peerId,
      peerPublicKeyBase64: peerPublicKeyBase64,
    );

    return await _cipherService.decryptText(
      payload: payload,
      secretKey: sessionKey,
    );
  }

  /// Encrypt a media file (Image/Video) and wrap its key for the peer
  Future<Map<String, dynamic>> encryptMediaForPeer({
    required int peerId,
    required String peerPublicKeyBase64,
    required Uint8List fileBytes,
  }) async {
    // 1. Encrypt file with random one-time AES key
    final fileEncryption = await _cipherService.encryptFile(fileBytes: fileBytes);

    // 2. Derive session key for peer
    final sessionKey = await _keyExchangeService.getSessionKeyForPeer(
      peerId: peerId,
      peerPublicKeyBase64: peerPublicKeyBase64,
    );

    // 3. Encrypt the one-time file key with peer's session key
    final wrappedKeyPayload = await _cipherService.wrapFileKey(
      fileKeyBase64: fileEncryption['fileKeyBase64'] as String,
      sessionKey: sessionKey,
    );

    return {
      'encryptedBytes': fileEncryption['encryptedBytes'] as Uint8List,
      'wrappedKeyPayload': wrappedKeyPayload,
      'fileIv': fileEncryption['iv'] as String,
      'fileMac': fileEncryption['mac'] as String,
    };
  }

  /// Decrypt a media file (Image/Video) received from a peer
  Future<Uint8List> decryptMediaFromPeer({
    required int peerId,
    required String peerPublicKeyBase64,
    required Uint8List encryptedBytes,
    required EncryptedPayload wrappedKeyPayload,
    required String fileIv,
    required String fileMac,
  }) async {
    // 1. Derive session key for peer
    final sessionKey = await _keyExchangeService.getSessionKeyForPeer(
      peerId: peerId,
      peerPublicKeyBase64: peerPublicKeyBase64,
    );

    // 2. Decrypt the one-time file key
    final fileKey = await _cipherService.unwrapFileKey(
      wrappedPayload: wrappedKeyPayload,
      sessionKey: sessionKey,
    );

    // 3. Decrypt the binary file bytes
    return await _cipherService.decryptFile(
      encryptedBytes: encryptedBytes,
      fileKey: fileKey,
      ivBase64: fileIv,
      macBase64: fileMac,
    );
  }

  /// Reset session caches on logout
  void reset() {
    _keyExchangeService.clearCache();
    _isPublicKeySynced = false;
  }
}
