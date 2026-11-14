import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exceptions.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;
  final AuthLocalDataSource _localDataSource;
  final ApiClient _apiClient;

  AuthRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AuthLocalDataSource localDataSource,
    required ApiClient apiClient,
  })  : _remoteDataSource = remoteDataSource,
        _localDataSource = localDataSource,
        _apiClient = apiClient;

  @override
  Future<UserEntity> register({
    required String name,
    required String email,
    required String password,
    String? publicIdentityKey,
    String? publicSignedPrekey,
  }) async {
    final result = await _remoteDataSource.register(
      name: name,
      email: email,
      password: password,
      publicIdentityKey: publicIdentityKey,
      publicSignedPrekey: publicSignedPrekey,
    );

    final token = result['token'] as String;
    final user = result['user'] as UserEntity;

    _apiClient.setAuthToken(token);
    await _localDataSource.saveToken(token);
    await _localDataSource.saveUser(user);
    return user;
  }

  @override
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    final result = await _remoteDataSource.login(
      email: email,
      password: password,
    );

    final token = result['token'] as String;
    final user = result['user'] as UserEntity;

    _apiClient.setAuthToken(token);
    await _localDataSource.saveToken(token);
    await _localDataSource.saveUser(user);
    return user;
  }

  @override
  Future<void> logout() async {
    try {
      await _remoteDataSource.logout();
    } finally {
      _apiClient.setAuthToken(null);
      await _localDataSource.clearToken();
      await _localDataSource.clearUser();
    }
  }

  @override
  Future<UserEntity> getMe() async {
    final user = await _remoteDataSource.getMe();
    await _localDataSource.saveUser(user);
    return user;
  }

  @override
  Future<UserEntity?> checkAuthStatus() async {
    final token = await _localDataSource.getToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    _apiClient.setAuthToken(token);

    // Fast path: restore cached user immediately for instantaneous startup
    final cachedUser = await _localDataSource.getUser();
    if (cachedUser != null) {
      // Refresh session in background without stalling boot
      _remoteDataSource.getMe().then((freshUser) {
        _localDataSource.saveUser(freshUser);
      }).catchError((e) {
        if (e is UnauthorizedException || (e is ApiException && e.statusCode == 401)) {
          _apiClient.setAuthToken(null);
          _localDataSource.clearToken();
          _localDataSource.clearUser();
        }
      });
      return cachedUser;
    }

    try {
      final user = await _remoteDataSource.getMe();
      await _localDataSource.saveUser(user);
      return user;
    } on UnauthorizedException {
      AppLogger.w('Token invalidated (401), clearing local auth session');
      _apiClient.setAuthToken(null);
      await _localDataSource.clearToken();
      await _localDataSource.clearUser();
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        _apiClient.setAuthToken(null);
        await _localDataSource.clearToken();
        await _localDataSource.clearUser();
        return null;
      }
      AppLogger.w('checkAuthStatus API exception (${e.statusCode}), restoring cached user');
      return await _localDataSource.getUser();
    } catch (e) {
      AppLogger.w('checkAuthStatus network/offline error ($e), restoring cached user');
      return await _localDataSource.getUser();
    }
  }
}
