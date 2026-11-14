import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/crypto/e2ee_manager.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/push_notification_service.dart';
import '../../../../core/network/websocket_service.dart';
import '../../domain/usecases/check_auth_status_usecase.dart';
import '../../domain/usecases/login_usecase.dart';
import '../../domain/usecases/logout_usecase.dart';
import '../../domain/usecases/register_usecase.dart';
import 'auth_event.dart';
import 'auth_state.dart';


class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase _loginUseCase;
  final RegisterUseCase _registerUseCase;
  final LogoutUseCase _logoutUseCase;
  final CheckAuthStatusUseCase _checkAuthStatusUseCase;
  final E2eeManager _e2eeManager;
  final WebSocketService _webSocketService;

  AuthBloc({
    required LoginUseCase loginUseCase,
    required RegisterUseCase registerUseCase,
    required LogoutUseCase logoutUseCase,
    required CheckAuthStatusUseCase checkAuthStatusUseCase,
    required E2eeManager e2eeManager,
    required WebSocketService webSocketService,
  })  : _loginUseCase = loginUseCase,
        _registerUseCase = registerUseCase,
        _logoutUseCase = logoutUseCase,
        _checkAuthStatusUseCase = checkAuthStatusUseCase,
        _e2eeManager = e2eeManager,
        _webSocketService = webSocketService,
        super(const AuthInitial()) {
    on<AuthCheckRequested>(_onAuthCheckRequested);
    on<AuthLoginSubmitted>(_onAuthLoginSubmitted);
    on<AuthRegisterSubmitted>(_onAuthRegisterSubmitted);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
  }


  Future<void> _onAuthCheckRequested(
    AuthCheckRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final user = await _checkAuthStatusUseCase();
      if (user != null) {
        // Connect WebSocket and join user channel immediately
        _webSocketService.connect();
        _webSocketService.subscribeToUserChannel(user.id);

        // Sync public key and FCM token in background without blocking screen transition
        unawaited(_e2eeManager.syncPublicKeyWithBackend());
        unawaited(sl<PushNotificationService>().syncToken());

        emit(Authenticated(user));
      } else {
        emit(const Unauthenticated());
      }
    } catch (_) {
      emit(const Unauthenticated());
    }
  }

  Future<void> _onAuthLoginSubmitted(
    AuthLoginSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      final user = await _loginUseCase(
        email: event.email,
        password: event.password,
      );
      // Automatically register E2EE public key with backend
      await _e2eeManager.syncPublicKeyWithBackend();
      sl<PushNotificationService>().syncToken();
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceAll('ApiException: ', '')));
    }
  }

  Future<void> _onAuthRegisterSubmitted(
    AuthRegisterSubmitted event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      // Get device public key to register along with account
      final localPublicKey = await _e2eeManager.keyManager.getPublicKeyBase64();

      final user = await _registerUseCase(
        name: event.name,
        email: event.email,
        password: event.password,
        publicIdentityKey: event.publicIdentityKey ?? localPublicKey,
        publicSignedPrekey: event.publicSignedPrekey,
      );
      sl<PushNotificationService>().syncToken();
      emit(Authenticated(user));
    } catch (e) {
      emit(AuthFailure(e.toString().replaceAll('ApiException: ', '')));
    }
  }

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(const AuthLoading());
    try {
      await _logoutUseCase();
    } finally {
      _webSocketService.disconnect();
      _e2eeManager.reset();
      emit(const Unauthenticated());
    }
  }

}
