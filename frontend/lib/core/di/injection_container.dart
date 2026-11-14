import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/datasources/auth_local_data_source.dart';
import '../../features/auth/data/datasources/auth_remote_data_source.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/domain/usecases/check_auth_status_usecase.dart';
import '../../features/auth/domain/usecases/login_usecase.dart';
import '../../features/auth/domain/usecases/logout_usecase.dart';
import '../../features/auth/domain/usecases/register_usecase.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/auth_event.dart';

import '../../features/users/data/datasources/users_remote_data_source.dart';
import '../../features/users/data/repositories/users_repository_impl.dart';
import '../../features/users/domain/repositories/users_repository.dart';
import '../../features/users/domain/usecases/get_users_usecase.dart';
import '../../features/users/presentation/bloc/users_bloc.dart';
import '../../features/chat/data/datasources/chat_remote_datasource.dart';
import '../../features/chat/data/repositories/chat_repository_impl.dart';
import '../../features/chat/domain/repositories/chat_repository.dart';
import '../../features/chat/domain/usecases/delete_messages_usecase.dart';
import '../../features/chat/domain/usecases/download_media_usecase.dart';
import '../../features/chat/domain/usecases/get_chat_history_usecase.dart';
import '../../features/chat/domain/usecases/mark_message_read_usecase.dart';
import '../../features/chat/domain/usecases/send_media_message_usecase.dart';
import '../../features/chat/domain/usecases/send_message_usecase.dart';
import '../../features/chat/presentation/bloc/chat_bloc.dart';
import '../../features/call/data/datasources/call_signaling_remote_datasource.dart';
import '../../features/call/data/repositories/call_repository_impl.dart';
import '../../features/call/data/services/call_audio_service.dart';
import '../../features/call/data/services/webrtc_service.dart';
import '../../features/call/domain/repositories/call_repository.dart';
import '../../features/call/domain/usecases/answer_call_usecase.dart';
import '../../features/call/domain/usecases/end_call_usecase.dart';
import '../../features/call/domain/usecases/initiate_call_usecase.dart';
import '../../features/call/domain/usecases/send_ice_candidate_usecase.dart';
import '../../features/call/presentation/bloc/call_bloc.dart';
import '../../features/settings/data/datasources/settings_remote_datasource.dart';
import '../../features/settings/data/repositories/settings_repository_impl.dart';
import '../../features/settings/domain/repositories/settings_repository.dart';
import '../../features/settings/presentation/bloc/settings_bloc.dart';
import '../storage/storage_manager_service.dart';
import '../theme/theme_cubit.dart';
import '../audio/audio_player_service.dart';
import '../audio/voice_record_service.dart';
import '../config/app_config.dart';
import '../crypto/cipher_service.dart';
import '../crypto/e2ee_manager.dart';
import '../crypto/key_exchange_service.dart';
import '../crypto/key_manager.dart';
import '../network/api_client.dart';
import '../network/push_notification_service.dart';
import '../network/websocket_service.dart';
import '../storage/local_database_service.dart';
import '../storage/local_vault_service.dart';


final sl = GetIt.instance;

Future<void> initDependencies() async {
  // External Libraries
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton<SharedPreferences>(() => sharedPreferences);

  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  sl.registerLazySingleton<FlutterSecureStorage>(() => secureStorage);

  // Core Config
  sl.registerLazySingleton<AppConfig>(() => AppConfig(sl<SharedPreferences>()));

  // Core Network
  sl.registerLazySingleton<ApiClient>(
    () => ApiClient(
      appConfig: sl<AppConfig>(),
      secureStorage: sl<FlutterSecureStorage>(),
      prefs: sl<SharedPreferences>(),
    ),
  );
  sl.registerLazySingleton<PushNotificationService>(
    () => PushNotificationService(apiClient: sl<ApiClient>()),
  );

  // Sandboxed Decrypted Storage & Local Database
  final localVault = LocalVaultService();
  await localVault.initialize();
  sl.registerSingleton<LocalVaultService>(localVault);
  sl.registerLazySingleton<LocalDatabaseService>(() => LocalDatabaseService());

  // Audio Services (Voice Notes & Recording)
  sl.registerLazySingleton<VoiceRecordService>(() => VoiceRecordService());
  sl.registerLazySingleton<AudioPlayerService>(() => AudioPlayerService());



  // Core E2EE Crypto Engine
  sl.registerLazySingleton<KeyManager>(
    () => KeyManager(sl<FlutterSecureStorage>(), sl<SharedPreferences>()),
  );
  sl.registerLazySingleton<KeyExchangeService>(() => KeyExchangeService(sl<KeyManager>()));
  sl.registerLazySingleton<CipherService>(() => CipherService());
  sl.registerLazySingleton<E2eeManager>(
    () => E2eeManager(
      keyManager: sl<KeyManager>(),
      keyExchangeService: sl<KeyExchangeService>(),
      cipherService: sl<CipherService>(),
      apiClient: sl<ApiClient>(),
    ),
  );

  // Auth Feature
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSourceImpl(
      sl<FlutterSecureStorage>(),
      sl<SharedPreferences>(),
    ),
  );
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      remoteDataSource: sl<AuthRemoteDataSource>(),
      localDataSource: sl<AuthLocalDataSource>(),
      apiClient: sl<ApiClient>(),
    ),
  );
  sl.registerLazySingleton<LoginUseCase>(() => LoginUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<RegisterUseCase>(() => RegisterUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<LogoutUseCase>(() => LogoutUseCase(sl<AuthRepository>()));
  sl.registerLazySingleton<CheckAuthStatusUseCase>(() => CheckAuthStatusUseCase(sl<AuthRepository>()));
  sl.registerFactory<AuthBloc>(
    () => AuthBloc(
      loginUseCase: sl<LoginUseCase>(),
      registerUseCase: sl<RegisterUseCase>(),
      logoutUseCase: sl<LogoutUseCase>(),
      checkAuthStatusUseCase: sl<CheckAuthStatusUseCase>(),
      e2eeManager: sl<E2eeManager>(),
      webSocketService: sl<WebSocketService>(),
    ),
  );

  // Auto-logout when API returns 401 Unauthorized
  sl<ApiClient>().onUnauthorized = () {
    sl<AuthBloc>().add(const AuthLogoutRequested());
  };


  // Users Feature
  sl.registerLazySingleton<UsersRemoteDataSource>(
    () => UsersRemoteDataSourceImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton<UsersRepository>(
    () => UsersRepositoryImpl(
      remoteDataSource: sl<UsersRemoteDataSource>(),
    ),
  );
  sl.registerLazySingleton<GetUsersUseCase>(() => GetUsersUseCase(sl<UsersRepository>()));
  sl.registerFactory<UsersBloc>(
    () => UsersBloc(getUsersUseCase: sl<GetUsersUseCase>()),
  );

  // Core Network - WebSocket (Laravel Reverb)
  sl.registerLazySingleton<WebSocketService>(
    () => WebSocketService(sl<AppConfig>(), sl<ApiClient>()),
  );

  // Chat Feature
  sl.registerLazySingleton<ChatRemoteDataSource>(
    () => ChatRemoteDataSourceImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(
      remoteDataSource: sl<ChatRemoteDataSource>(),
      e2eeManager: sl<E2eeManager>(),
      webSocketService: sl<WebSocketService>(),
      localDb: sl<LocalDatabaseService>(),
      localVault: sl<LocalVaultService>(),
    ),
  );

  sl.registerLazySingleton<SendMessageUseCase>(
    () => SendMessageUseCase(sl<ChatRepository>()),
  );
  sl.registerLazySingleton<SendMediaMessageUseCase>(
    () => SendMediaMessageUseCase(sl<ChatRepository>()),
  );
  sl.registerLazySingleton<DownloadMediaUseCase>(
    () => DownloadMediaUseCase(sl<ChatRepository>()),
  );
  sl.registerLazySingleton<GetChatHistoryUseCase>(
    () => GetChatHistoryUseCase(sl<ChatRepository>()),
  );
  sl.registerLazySingleton<MarkMessageReadUseCase>(
    () => MarkMessageReadUseCase(sl<ChatRepository>()),
  );
  sl.registerLazySingleton<DeleteMessagesUseCase>(
    () => DeleteMessagesUseCase(sl<ChatRepository>()),
  );
  sl.registerFactory<ChatBloc>(
    () => ChatBloc(
      sendMessageUseCase: sl<SendMessageUseCase>(),
      sendMediaMessageUseCase: sl<SendMediaMessageUseCase>(),
      getChatHistoryUseCase: sl<GetChatHistoryUseCase>(),
      markMessageReadUseCase: sl<MarkMessageReadUseCase>(),
      deleteMessagesUseCase: sl<DeleteMessagesUseCase>(),
      chatRepository: sl<ChatRepository>(),
      localDb: sl<LocalDatabaseService>(),
    ),
  );

  // WebRTC Calling Feature (TASK-13)
  sl.registerLazySingleton<CallSignalingRemoteDataSource>(
    () => CallSignalingRemoteDataSourceImpl(sl<ApiClient>()),
  );
  sl.registerLazySingleton<IWebRtcService>(
    () => WebRtcServiceImpl(),
  );
  sl.registerLazySingleton<CallRepository>(
    () => CallRepositoryImpl(
      remoteDataSource: sl<CallSignalingRemoteDataSource>(),
      webRtcService: sl<IWebRtcService>(),
      webSocketService: sl<WebSocketService>(),
    ),
  );
  sl.registerLazySingleton<InitiateCallUseCase>(
    () => InitiateCallUseCase(sl<CallRepository>()),
  );
  sl.registerLazySingleton<AnswerCallUseCase>(
    () => AnswerCallUseCase(sl<CallRepository>()),
  );
  sl.registerLazySingleton<EndCallUseCase>(
    () => EndCallUseCase(sl<CallRepository>()),
  );
  sl.registerLazySingleton<SendIceCandidateUseCase>(
    () => SendIceCandidateUseCase(sl<CallRepository>()),
  );
  sl.registerLazySingleton<CallAudioService>(
    () => CallAudioService(),
  );
  sl.registerLazySingleton<CallBloc>(
    () => CallBloc(
      initiateCallUseCase: sl<InitiateCallUseCase>(),
      answerCallUseCase: sl<AnswerCallUseCase>(),
      endCallUseCase: sl<EndCallUseCase>(),
      sendIceCandidateUseCase: sl<SendIceCandidateUseCase>(),
      callRepository: sl<CallRepository>(),
      callAudioService: sl<CallAudioService>(),
      apiClient: sl<ApiClient>(),
    ),
  );

  // Storage Management & Settings Feature (TASK-29)
  sl.registerLazySingleton<StorageManagerService>(
    () => StorageManagerService(localDb: sl<LocalDatabaseService>()),
  );
  sl.registerLazySingleton<SettingsRemoteDataSource>(
    () => SettingsRemoteDataSourceImpl(apiClient: sl<ApiClient>()),
  );
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(
      remoteDataSource: sl<SettingsRemoteDataSource>(),
      storageManagerService: sl<StorageManagerService>(),
    ),
  );
    // Theme Management (Dark & Light Mode)
  sl.registerLazySingleton<ThemeCubit>(
    () => ThemeCubit(sl<SharedPreferences>()),
  );

  sl.registerFactory<SettingsBloc>(
    () => SettingsBloc(settingsRepository: sl<SettingsRepository>()),
  );
}
