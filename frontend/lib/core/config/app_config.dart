import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String _prefKeyCustomApiUrl = 'custom_api_base_url';
  static const String _prefKeyCustomWsHost = 'custom_ws_host';
  static const String _prefKeyCustomWsPort = 'custom_ws_port';
  static const String _prefKeyCustomWsScheme = 'custom_ws_scheme';
  static const String _prefKeyCustomTurnUrl = 'custom_turn_url';
  static const String _prefKeyCustomTurnUsername = 'custom_turn_username';
  static const String _prefKeyCustomTurnCredential = 'custom_turn_credential';

  final SharedPreferences _prefs;

  AppConfig(this._prefs);

  /// Default API base URL from .env (e.g., http://10.0.2.2:8000/api/v1)
  String get defaultApiBaseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000/api/v1';

  /// Active API base URL (custom user override if set, otherwise .env default)
  String get apiBaseUrl {
    final custom = _prefs.getString(_prefKeyCustomApiUrl);
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return defaultApiBaseUrl;
  }

  /// Default WebSocket host from .env
  String get defaultWsHost => dotenv.env['REVERB_HOST'] ?? '10.0.2.2';

  /// Active WebSocket host
  String get wsHost {
    final custom = _prefs.getString(_prefKeyCustomWsHost);
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return defaultWsHost;
  }

  /// Default WebSocket port from .env
  int get defaultWsPort =>
      int.tryParse(dotenv.env['REVERB_PORT'] ?? '8080') ?? 8080;

  /// Active WebSocket port
  int get wsPort => _prefs.getInt(_prefKeyCustomWsPort) ?? defaultWsPort;

  /// WebSocket scheme ('ws' or 'wss')
  String get defaultWsScheme => dotenv.env['REVERB_SCHEME'] ?? 'ws';

  /// Active WebSocket scheme
  String get wsScheme =>
      _prefs.getString(_prefKeyCustomWsScheme) ?? defaultWsScheme;

  /// Reverb App Key
  String get reverbAppKey => dotenv.env['REVERB_APP_KEY'] ?? 'reverb_key';

  /// STUN servers list
  List<String> get stunServers => [
        dotenv.env['STUN_SERVER_1'] ?? 'stun:stun.l.google.com:19302',
        dotenv.env['STUN_SERVER_2'] ?? 'stun:stun1.l.google.com:19302',
        dotenv.env['STUN_SERVER_3'] ?? 'stun:stun2.l.google.com:19302',
      ];

  /// Default TURN server configurations from .env
  String get defaultTurnUrl => dotenv.env['TURN_SERVER_URL'] ?? '';
  String get defaultTurnUsername => dotenv.env['TURN_USERNAME'] ?? '';
  String get defaultTurnCredential => dotenv.env['TURN_CREDENTIAL'] ?? '';

  /// Active TURN server parameters
  String get turnUrl =>
      _prefs.getString(_prefKeyCustomTurnUrl) ?? defaultTurnUrl;
  String get turnUsername =>
      _prefs.getString(_prefKeyCustomTurnUsername) ?? defaultTurnUsername;
  String get turnCredential =>
      _prefs.getString(_prefKeyCustomTurnCredential) ?? defaultTurnCredential;

  /// Dynamic WebRTC ICE Configuration (STUN + TURN fallback)
  Map<String, dynamic> get iceServersConfiguration {
    final iceServers = <Map<String, dynamic>>[
      {'urls': stunServers},
    ];

    if (turnUrl.isNotEmpty) {
      final turnConfig = <String, dynamic>{
        'urls': turnUrl.contains(',')
            ? turnUrl.split(',').map((u) => u.trim()).toList()
            : turnUrl,
      };
      if (turnUsername.isNotEmpty) {
        turnConfig['username'] = turnUsername;
      }
      if (turnCredential.isNotEmpty) {
        turnConfig['credential'] = turnCredential;
      }
      iceServers.add(turnConfig);
    }

    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };
  }

  /// Update dynamic tunnel URL at runtime (e.g., from Cloudflare Tunnel or Ngrok)
  Future<void> updateNetworkConfig({
    required String apiUrl,
    required String wsHost,
    required int wsPort,
    required String wsScheme,
    String? turnUrl,
    String? turnUsername,
    String? turnCredential,
  }) async {
    await _prefs.setString(_prefKeyCustomApiUrl, apiUrl.trim());
    await _prefs.setString(_prefKeyCustomWsHost, wsHost.trim());
    await _prefs.setInt(_prefKeyCustomWsPort, wsPort);
    await _prefs.setString(_prefKeyCustomWsScheme, wsScheme.trim());

    if (turnUrl != null) {
      await _prefs.setString(_prefKeyCustomTurnUrl, turnUrl.trim());
    }
    if (turnUsername != null) {
      await _prefs.setString(_prefKeyCustomTurnUsername, turnUsername.trim());
    }
    if (turnCredential != null) {
      await _prefs.setString(
          _prefKeyCustomTurnCredential, turnCredential.trim());
    }
  }

  /// Reset to default values specified in .env
  Future<void> resetToDefault() async {
    await _prefs.remove(_prefKeyCustomApiUrl);
    await _prefs.remove(_prefKeyCustomWsHost);
    await _prefs.remove(_prefKeyCustomWsPort);
    await _prefs.remove(_prefKeyCustomWsScheme);
    await _prefs.remove(_prefKeyCustomTurnUrl);
    await _prefs.remove(_prefKeyCustomTurnUsername);
    await _prefs.remove(_prefKeyCustomTurnCredential);
  }

  bool get isCustomUrlConfigured =>
      _prefs.containsKey(_prefKeyCustomApiUrl);
}
