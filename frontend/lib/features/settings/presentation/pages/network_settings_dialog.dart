import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/websocket_service.dart';
import '../../../../core/theme/app_colors.dart';

class NetworkSettingsDialog extends StatefulWidget {
  const NetworkSettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const NetworkSettingsDialog(),
    );
  }

  @override
  State<NetworkSettingsDialog> createState() => _NetworkSettingsDialogState();
}

class _NetworkSettingsDialogState extends State<NetworkSettingsDialog> {
  final _appConfig = sl<AppConfig>();
  final _apiClient = sl<ApiClient>();

  late final TextEditingController _apiUrlController;
  late final TextEditingController _wsHostController;
  late final TextEditingController _wsPortController;
  late final TextEditingController _turnUrlController;
  late final TextEditingController _turnUsernameController;
  late final TextEditingController _turnCredentialController;
  late String _selectedWsScheme;

  bool _isTesting = false;
  String? _testResult;
  bool _isSuccess = false;
  bool _showTurnSettings = false;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: _appConfig.apiBaseUrl);
    _wsHostController = TextEditingController(text: _appConfig.wsHost);
    _wsPortController = TextEditingController(text: _appConfig.wsPort.toString());
    _selectedWsScheme = _appConfig.wsScheme;
    _turnUrlController = TextEditingController(text: _appConfig.turnUrl);
    _turnUsernameController = TextEditingController(text: _appConfig.turnUsername);
    _turnCredentialController = TextEditingController(text: _appConfig.turnCredential);

    if (_appConfig.turnUrl.isNotEmpty) {
      _showTurnSettings = true;
    }
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _wsHostController.dispose();
    _wsPortController.dispose();
    _turnUrlController.dispose();
    _turnUsernameController.dispose();
    _turnCredentialController.dispose();
    super.dispose();
  }

  String _sanitizeInput(String input) {
    var s = input.trim();
    while (s.isNotEmpty && (s.startsWith("'") || s.startsWith('"'))) {
      s = s.substring(1).trim();
    }
    while (s.isNotEmpty && (s.endsWith("'") || s.endsWith('"'))) {
      s = s.substring(0, s.length - 1).trim();
    }
    return s;
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      var testUrl = _sanitizeInput(_apiUrlController.text);
      if (testUrl.isNotEmpty && !testUrl.startsWith('http://') && !testUrl.startsWith('https://')) {
        testUrl = (testUrl.contains('localhost') || testUrl.contains('10.0.2.2') || testUrl.contains('192.168.'))
            ? 'http://$testUrl'
            : 'https://$testUrl';
      }
      _apiUrlController.text = testUrl;

      final healthEndpoint =
          testUrl.endsWith('/') ? '${testUrl}health' : '$testUrl/health';

      final response = await _apiClient.dio.get(
        healthEndpoint,
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 && response.data['status'] == 'ok') {
        // Also test WebSocket reachability
        String wsNotice = '';
        try {
          final wsScheme = _selectedWsScheme == 'https' || _selectedWsScheme == 'wss' ? 'wss' : 'ws';
          var cleanHost = _sanitizeInput(_wsHostController.text).replaceFirst(RegExp(r'^(https?|wss?)://'), '').replaceAll(RegExp(r'/+$'), '');
          _wsHostController.text = cleanHost;
          var wsPort = int.tryParse(_wsPortController.text.trim()) ?? 8080;
          if (cleanHost.contains(':')) {
            final p = cleanHost.split(':');
            cleanHost = p[0];
            wsPort = int.tryParse(p[1]) ?? wsPort;
          }
          final portSuffix = (wsScheme == 'wss' && wsPort == 443) || (wsScheme == 'ws' && wsPort == 80) ? '' : ':$wsPort';
          final wsUri = Uri.parse('$wsScheme://$cleanHost$portSuffix/app/${_appConfig.reverbAppKey}?protocol=7&client=js&version=8.4.0-reverb&flash=false');
          final sock = await WebSocket.connect(wsUri.toString()).timeout(const Duration(seconds: 4));
          await sock.close();
          wsNotice = ' & WebSocket connected!';
        } catch (wsErr) {
          wsNotice = ' (Warning: WebSocket failed: $wsErr. Verify Dev Tunnel Port 8080 protocol is HTTP and Visibility is Public)';
        }

        setState(() {
          _isTesting = false;
          _isSuccess = !wsNotice.contains('Warning');
          _testResult = 'API connected$wsNotice';
        });
      } else {
        setState(() {
          _isTesting = false;
          _isSuccess = false;
          _testResult =
              'Connected, but received unexpected response: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isTesting = false;
        _isSuccess = false;
        _testResult = 'Connection failed: $e';
      });
    }
  }

  Future<void> _saveSettings() async {
    final port = int.tryParse(_wsPortController.text.trim()) ?? 8080;
    var saveApiUrl = _sanitizeInput(_apiUrlController.text);
    if (saveApiUrl.isNotEmpty && !saveApiUrl.startsWith('http://') && !saveApiUrl.startsWith('https://')) {
      saveApiUrl = (saveApiUrl.contains('localhost') || saveApiUrl.contains('10.0.2.2') || saveApiUrl.contains('192.168.'))
          ? 'http://$saveApiUrl'
          : 'https://$saveApiUrl';
    }
    var saveWsHost = _sanitizeInput(_wsHostController.text).replaceFirst(RegExp(r'^(https?|wss?)://'), '').replaceAll(RegExp(r'/+$'), '');

    await _appConfig.updateNetworkConfig(
      apiUrl: saveApiUrl,
      wsHost: saveWsHost,
      wsPort: port,
      wsScheme: _selectedWsScheme,
      turnUrl: _turnUrlController.text.trim(),
      turnUsername: _turnUsernameController.text.trim(),
      turnCredential: _turnCredentialController.text.trim(),
    );

    try {
      sl<WebSocketService>().disconnect(notifyBackend: false);
      sl<WebSocketService>().connect();
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server, Tunnel & TURN settings updated!'),
          backgroundColor: AppColors.accent,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _resetToDefaults() async {
    await _appConfig.resetToDefault();
    setState(() {
      _apiUrlController.text = _appConfig.defaultApiBaseUrl;
      _wsHostController.text = _appConfig.defaultWsHost;
      _wsPortController.text = _appConfig.defaultWsPort.toString();
      _selectedWsScheme = _appConfig.defaultWsScheme;
      _turnUrlController.text = _appConfig.defaultTurnUrl;
      _turnUsernameController.text = _appConfig.defaultTurnUsername;
      _turnCredentialController.text = _appConfig.defaultTurnCredential;
      _testResult = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset to .env defaults')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      title: const Row(
        children: [
          Icon(Icons.cloud_sync, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Server & Tunnel Settings', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your local IP or Tunnel URL (Cloudflare Tunnel / Ngrok) to connect seamlessly from physical mobile devices.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondaryDark),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'https://api.yourdomain.com/api/v1',
                prefixIcon: Icon(Icons.link, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wsHostController,
              decoration: const InputDecoration(
                labelText: 'WebSocket Host',
                hintText: 'ws.yourdomain.com or 10.0.2.2',
                prefixIcon: Icon(Icons.podcasts, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _wsPortController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '8080 or 443',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedWsScheme,
                    decoration: const InputDecoration(labelText: 'Scheme'),
                    items: const [
                      DropdownMenuItem(value: 'ws', child: Text('ws')),
                      DropdownMenuItem(value: 'wss', child: Text('wss')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedWsScheme = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Expandable WebRTC TURN Server Settings
            InkWell(
              onTap: () {
                setState(() {
                  _showTurnSettings = !_showTurnSettings;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      _showTurnSettings
                          ? Icons.arrow_drop_down_rounded
                          : Icons.arrow_right_rounded,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'WebRTC TURN / NAT Relay (Optional)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showTurnSettings) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _turnUrlController,
                decoration: const InputDecoration(
                  labelText: 'TURN Server URL',
                  hintText: 'turn:turn.domain.com:3478',
                  prefixIcon: Icon(Icons.router_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _turnUsernameController,
                decoration: const InputDecoration(
                  labelText: 'TURN Username',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _turnCredentialController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'TURN Password / Credential',
                  prefixIcon: Icon(Icons.password_outlined, size: 20),
                ),
              ),
            ],

            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.network_check, size: 18),
              label: Text(_isTesting ? 'Testing...' : 'Test API Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cardDark,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(42),
              ),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? AppColors.accent.withOpacity(0.15)
                      : AppColors.accentRose.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isSuccess ? AppColors.accent : AppColors.accentRose,
                  ),
                ),
                child: Text(
                  _testResult!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _isSuccess ? AppColors.accent : AppColors.accentRose,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _resetToDefaults,
          child: const Text('Reset',
              style: TextStyle(color: AppColors.textSecondaryDark)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondaryDark)),
        ),
        ElevatedButton(
          onPressed: _saveSettings,
          child: const Text('Save & Apply'),
        ),
      ],
    );
  }
}
