import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../auth/presentation/bloc/auth_state.dart';
import '../../../auth/presentation/pages/login_page.dart';
import '../../../call/domain/entities/call_entity.dart';
import '../../../call/presentation/bloc/call_bloc.dart';
import '../../../call/presentation/bloc/call_state.dart';
import '../../../settings/presentation/pages/network_settings_dialog.dart';
import '../../../users/presentation/pages/home_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  final _apiClient = sl<ApiClient>();
  final _appConfig = sl<AppConfig>();

  String _statusMessage = 'Connecting to backend server...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _checkServerAndAuth();
  }

  Future<void> _checkServerAndAuth() async {
    // 1. Fast path: if session token exists locally, restore instantly (sub-100ms startup)
    final token = await sl<AuthLocalDataSource>().getToken();
    if (token != null && token.isNotEmpty && mounted) {
      context.read<AuthBloc>().add(const AuthCheckRequested());
      return;
    }

    // 2. Cold installation / unauthenticated path: verify server reachable before LoginPage
    setState(() {
      _statusMessage = 'Connecting to server at ${_appConfig.apiBaseUrl}...';
      _hasError = false;
    });

    try {
      final response = await _apiClient.get('/health');
      if (response.statusCode == 200) {
        if (mounted) {
          context.read<AuthBloc>().add(const AuthCheckRequested());
        }
      } else {
        setState(() {
          _hasError = true;
          _statusMessage = 'Backend returned status ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _statusMessage =
            'Could not reach server at ${_appConfig.apiBaseUrl}.\nTap Settings to configure your Tunnel URL.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          // If a call is already active or ringing, do not overwrite the call screen
          final callState = sl<CallBloc>().state;
          if (callState is CallSessionState &&
              (callState.session.status == CallStatus.connected ||
               callState.session.status == CallStatus.connecting ||
               callState.session.status == CallStatus.ringing)) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => HomePage(currentUser: state.user)),
              (route) => route.settings.name != null,
            );
            return;
          }

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomePage(currentUser: state.user),
            ),
          );
        } else if (state is Unauthenticated || state is AuthFailure) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const LoginPage(),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: AppColors.primaryLight),
              tooltip: 'Network & Tunnel Settings',
              onPressed: () async {
                await NetworkSettingsDialog.show(context);
                _checkServerAndAuth();
              },
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 104,
                      height: 104,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'VaultChat',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, size: 14, color: AppColors.accent),
                    SizedBox(width: 6),
                    Text(
                      'End-to-End Encrypted Messenger',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondaryDark,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 38),
                if (!_hasError) ...[
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: _hasError ? AppColors.accentRose : AppColors.textSecondaryDark,
                  ),
                ),
                if (_hasError) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _checkServerAndAuth,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cardDark,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await NetworkSettingsDialog.show(context);
                          _checkServerAndAuth();
                        },
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Set Tunnel URL'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
