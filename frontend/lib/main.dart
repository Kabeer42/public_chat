import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/crypto/e2ee_manager.dart';
import 'core/di/injection_container.dart';
import 'core/network/push_notification_service.dart';
import 'core/network/websocket_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'core/utils/app_logger.dart';
import 'core/utils/navigation_service.dart';
import 'features/auth/domain/entities/user_entity.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/call/domain/entities/call_entity.dart';
import 'features/call/presentation/bloc/call_bloc.dart';
import 'features/call/presentation/bloc/call_state.dart';
import 'features/call/presentation/pages/incoming_call_page.dart';
import 'features/call/presentation/pages/video_call_page.dart';
import 'features/call/presentation/pages/voice_call_page.dart';
import 'features/splash/presentation/pages/splash_page.dart';
import 'features/users/presentation/bloc/users_bloc.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI on desktop platforms (Windows / Linux)
  if (!kIsWeb && (io.Platform.isWindows || io.Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Load environment variables (.env)
  try {
    await dotenv.load(fileName: '.env');
    AppLogger.i('Loaded .env successfully');
  } catch (e) {
    AppLogger.w('Could not load .env file, falling back to built-in defaults: $e');
  }

  // Initialize Dependency Injection
  await initDependencies();

  // Initialize Push Notifications & Background Ringing Service
  await sl<PushNotificationService>().initialize();

  // Initialize E2EE Cryptographic Engine (generates X25519 identity key pair if first run)
  await sl<E2eeManager>().initialize();

  runApp(const ChatApp());
}

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      sl<WebSocketService>().updatePresence(true);
    } else if (state == AppLifecycleState.detached) {
      sl<WebSocketService>().updatePresence(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => sl<AuthBloc>(),
        ),
        BlocProvider<UsersBloc>(
          create: (_) => sl<UsersBloc>(),
        ),
        BlocProvider<CallBloc>(
          create: (_) => sl<CallBloc>(),
        ),
        BlocProvider<ThemeCubit>(
          create: (_) => sl<ThemeCubit>(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (context, themeMode) {
          return MaterialApp(
            navigatorKey: NavigationService.navigatorKey,
            title: 'VaultChat',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
        builder: (context, child) {
          return BlocListener<CallBloc, CallState>(
            listenWhen: (previous, current) {
              if (current is CallSessionState) {
                final session = current.session;
                final prevStatus = previous is CallSessionState ? previous.session.status : null;

                // 1. Ringing incoming call: open IncomingCallPage
                if (session.status == CallStatus.ringing &&
                    !session.isCaller &&
                    prevStatus != CallStatus.ringing) {
                  return true;
                }

                // 2. Incoming call directly answered (connecting or connected): open CallPage
                if ((session.status == CallStatus.connected || session.status == CallStatus.connecting) &&
                    !session.isCaller &&
                    prevStatus != CallStatus.connected &&
                    prevStatus != CallStatus.connecting) {
                  return true;
                }
              }
              return false;
            },
            listener: (context, state) {
              if (state is CallSessionState) {
                final session = state.session;
                final caller = UserEntity(
                  id: session.peerId,
                  name: session.peerName,
                  email: session.peerEmail ?? '',
                );

                if (session.status == CallStatus.ringing) {
                  NavigationService.push(
                    IncomingCallPage(
                      caller: caller,
                      callType: session.callType,
                    ),
                  );
                } else if (session.status == CallStatus.connected || session.status == CallStatus.connecting) {
                  if (session.callType == 'video') {
                    NavigationService.push(
                      VideoCallPage(peerUser: caller, isOutgoing: false),
                    );
                  } else {
                    NavigationService.push(
                      VoiceCallPage(peerUser: caller, isOutgoing: false),
                    );
                  }
                }
              }
            },
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const SplashPage(),
          );
        },
      ),
    );
  }
}
