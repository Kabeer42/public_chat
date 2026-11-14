import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/user_entity.dart';
import '../models/user_model.dart';

abstract class AuthLocalDataSource {
  Future<void> saveToken(String token);
  Future<String?> getToken();
  Future<void> clearToken();
  Future<void> saveUser(UserEntity user);
  Future<UserEntity?> getUser();
  Future<void> clearUser();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  static const String _userCacheKey = 'cached_current_user_profile';
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;

  AuthLocalDataSourceImpl(this._secureStorage, this._prefs);

  @override
  Future<void> saveToken(String token) async {
    await _prefs.setString(ApiClient.authTokenKey, token);
    try {
      await _secureStorage.write(key: ApiClient.authTokenKey, value: token);
    } catch (_) {}
  }

  @override
  Future<String?> getToken() async {
    final token = _prefs.getString(ApiClient.authTokenKey);
    if (token != null && token.isNotEmpty) return token;
    try {
      return await _secureStorage.read(key: ApiClient.authTokenKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearToken() async {
    await _prefs.remove(ApiClient.authTokenKey);
    try {
      await _secureStorage.delete(key: ApiClient.authTokenKey);
    } catch (_) {}
  }

  @override
  Future<void> saveUser(UserEntity user) async {
    try {
      final model = user is UserModel
          ? user
          : UserModel(
              id: user.id,
              name: user.name,
              email: user.email,
              publicIdentityKey: user.publicIdentityKey,
              publicSignedPrekey: user.publicSignedPrekey,
              isOnline: user.isOnline,
              showLastSeen: user.showLastSeen,
              lastSeenAt: user.lastSeenAt,
              createdAt: user.createdAt,
            );
      await _prefs.setString(_userCacheKey, jsonEncode(model.toJson()));
    } catch (_) {}
  }

  @override
  Future<UserEntity?> getUser() async {
    final raw = _prefs.getString(_userCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearUser() async {
    await _prefs.remove(_userCacheKey);
  }
}
