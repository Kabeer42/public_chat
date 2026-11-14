import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../constants/api_endpoints.dart';
import '../utils/app_logger.dart';
import 'api_exceptions.dart';

class ApiClient {
  static const String authTokenKey = 'sanctum_auth_token';

  final Dio _dio;
  final AppConfig _appConfig;
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences? _prefs;
  void Function()? onUnauthorized;
  String? _authToken;

  void setAuthToken(String? token) {
    _authToken = token;
    if (token != null) {
      _prefs?.setString(authTokenKey, token);
      try {
        _secureStorage.write(key: authTokenKey, value: token);
      } catch (_) {}
    } else {
      _prefs?.remove(authTokenKey);
      try {
        _secureStorage.delete(key: authTokenKey);
      } catch (_) {}
    }
  }

  String? get authToken => _authToken;

  ApiClient({
    required AppConfig appConfig,
    required FlutterSecureStorage secureStorage,
    SharedPreferences? prefs,
    Dio? dio,
  })  : _appConfig = appConfig,
        _secureStorage = secureStorage,
        _prefs = prefs,
        _dio = dio ?? Dio() {
    _authToken = _prefs?.getString(authTokenKey);
    _dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Dynamically route to current base URL (supports live tunnel changes)
          final currentBase = _appConfig.apiBaseUrl;
          if (!options.path.startsWith('http')) {
            options.baseUrl = currentBase;
          }

          // Inject bearer token (in-memory fast path, fallback to prefs and secureStorage)
          String? token = _authToken ?? _prefs?.getString(authTokenKey);
          if (token == null || token.isEmpty) {
            try {
              token = await _secureStorage.read(key: authTokenKey);
            } catch (_) {}
          }
          if (token != null && token.isNotEmpty) {
            _authToken = token;
            options.headers['Authorization'] = 'Bearer $token';
          }

          AppLogger.d('➡️ ${options.method} ${options.baseUrl}${options.path}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          AppLogger.d('⬅️ [${response.statusCode}] ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (DioException error, handler) {
          AppLogger.e('❌ DioError [${error.response?.statusCode}]: ${error.message}', error);
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(path, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put<T>(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(path, data: data, options: options);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ApiException _handleError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return NetworkException(
        message: 'Cannot connect to server at ${_appConfig.apiBaseUrl}. Ensure backend and tunnel are running.',
      );
    }

    final response = error.response;
    if (response != null) {
      final statusCode = response.statusCode;
      final data = response.data;
      final referenceCode = data is Map ? data['reference_code'] as String? : null;

      if (statusCode == 401) {
        _authToken = null;
        onUnauthorized?.call();
        return UnauthorizedException(
          message: data is Map && data['message'] != null ? data['message'] : 'Unauthorized',
          referenceCode: referenceCode,
        );
      }

      if (statusCode == 422) {
        return ValidationException(
          message: data is Map && data['message'] != null ? data['message'] : 'Validation failed',
          errors: data is Map ? data['errors'] : null,
          referenceCode: referenceCode,
        );
      }

      final message = data is Map && data['message'] != null
          ? data['message'].toString()
          : 'Server returned error ($statusCode)';
      return ApiException(
        message: message,
        statusCode: statusCode,
        referenceCode: referenceCode,
      );
    }

    return ApiException(message: error.message ?? 'Unexpected network error');
  }

  /// Report a client-side Flutter diagnostic error to the centralized backend audit table
  Future<String?> reportClientError({
    required String message,
    String? errorCode,
    String? exceptionClass,
    String? stackTrace,
    String? screen,
    String? functionName,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await post(
        ApiEndpoints.clientErrorLog,
        data: {
          'message': message,
          'error_code': errorCode,
          'exception_class': exceptionClass,
          'stack_trace': stackTrace,
          'screen': screen,
          'function_name': functionName,
          'metadata': metadata,
        },
      );
      if (response.data is Map) {
        return response.data['reference_code'] as String?;
      }
    } catch (e) {
      AppLogger.w('Failed to submit client error log to backend: $e');
    }
    return null;
  }
}
