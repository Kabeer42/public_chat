import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../config/app_config.dart';
import '../utils/app_logger.dart';
import 'api_client.dart';

enum WebSocketConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class WebSocketService {
  final AppConfig _config;
  final ApiClient _apiClient;

  WebSocket? _socket;
  String? _socketId;
  WebSocketConnectionStatus _status = WebSocketConnectionStatus.disconnected;

  final Set<String> _subscribedChannels = {};
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController =
      StreamController<WebSocketConnectionStatus>.broadcast();

  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isManualDisconnect = false;

  WebSocketService(this._config, this._apiClient);

  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;
  Stream<WebSocketConnectionStatus> get statusStream =>
      _statusController.stream;
  WebSocketConnectionStatus get status => _status;
  String? get socketId => _socketId;

  /// Connect to the Laravel Reverb WebSocket server
  Future<void> connect() async {
    if (_status == WebSocketConnectionStatus.connected ||
        _status == WebSocketConnectionStatus.connecting) {
      return;
    }

    _isManualDisconnect = false;
    _setStatus(WebSocketConnectionStatus.connecting);

    try {
      final scheme = _config.wsScheme == 'https' || _config.wsScheme == 'wss'
          ? 'wss'
          : 'ws';
      var host = _config.wsHost.trim()
          .replaceFirst(RegExp(r'^(https?|wss?)://'), '')
          .replaceAll(RegExp(r'/+$'), '');
      var port = _config.wsPort;
      if (host.contains(':')) {
        final parts = host.split(':');
        host = parts[0];
        port = int.tryParse(parts[1]) ?? port;
      }
      final key = _config.reverbAppKey;
      final portSuffix =
          (scheme == 'wss' && port == 443) || (scheme == 'ws' && port == 80)
              ? ''
              : ':$port';

      final uri = Uri.parse(
          '$scheme://$host$portSuffix/app/$key?protocol=7&client=js&version=8.4.0-reverb&flash=false');

      AppLogger.i('Connecting to Reverb WebSocket at: $uri');

      _socket = await WebSocket.connect(uri.toString())
          .timeout(const Duration(seconds: 10));

      _socket!.listen(
        _onMessageReceived,
        onDone: _onDisconnected,
        onError: _onError,
        cancelOnError: false,
      );

      _startPingTimer();
    } catch (e) {
      AppLogger.e('WebSocket connection failed', e);
      _scheduleReconnect();
    }
  }

  void _onMessageReceived(dynamic message) {
    try {
      final decoded = jsonDecode(message as String);
      final event = decoded['event'] as String?;
      final dataRaw = decoded['data'];

      dynamic data;
      if (dataRaw is String) {
        try {
          data = jsonDecode(dataRaw);
        } catch (_) {
          data = dataRaw;
        }
      } else {
        data = dataRaw;
      }

      AppLogger.d('WS Received: event=$event');

      if (event == 'pusher:connection_established') {
        _socketId = data['socket_id'] as String?;
        _reconnectAttempts = 0;
        _setStatus(WebSocketConnectionStatus.connected);
        AppLogger.i('Reverb connected. socket_id=$_socketId');

        // Re-subscribe to any previously subscribed channels
        _resubscribeAll();
        return;
      }

      if (event == 'pusher:ping') {
        sendRaw('pusher:pong', {});
        return;
      }

      if (event != null) {
        _eventController.add({
          'event': event,
          'channel': decoded['channel'],
          'data': data,
        });
      }
    } catch (e) {
      AppLogger.e('Error parsing incoming WebSocket frame', e);
    }
  }

  /// Subscribe to the user's private channel (e.g. private-user.{userId})
  Future<void> subscribeToUserChannel(int userId) async {
    final channelName = 'private-user.$userId';
    if (_subscribedChannels.contains(channelName)) return;

    _subscribedChannels.add(channelName);

    if (_status != WebSocketConnectionStatus.connected || _socketId == null) {
      AppLogger.d('Socket not ready yet; will subscribe upon connection.');
      return;
    }

    try {
      // 1. Authorize channel with backend via Sanctum
      final authResponse = await _apiClient.post(
        '/broadcasting/auth',
        data: {
          'socket_id': _socketId,
          'channel_name': channelName,
        },
      );

      if (authResponse.statusCode == 200) {
        final authData = authResponse.data;
        final authSig = authData['auth'] as String;

        // 2. Send pusher:subscribe
        sendRaw('pusher:subscribe', {
          'channel': channelName,
          'auth': authSig,
        });
        AppLogger.i('Subscribed to private channel: $channelName');
      }
    } catch (e) {
      AppLogger.e('Failed to authorize channel $channelName', e);
    }
  }

  /// Subscribe to a presence channel for WebRTC calling
  Future<void> subscribeToCallChannel(String callId) async {
    final channelName = 'presence-call.$callId';
    if (_subscribedChannels.contains(channelName)) return;

    _subscribedChannels.add(channelName);

    if (_status != WebSocketConnectionStatus.connected || _socketId == null) {
      return;
    }

    try {
      final authResponse = await _apiClient.post(
        '/broadcasting/auth',
        data: {
          'socket_id': _socketId,
          'channel_name': channelName,
        },
      );

      if (authResponse.statusCode == 200) {
        final authData = authResponse.data;
        sendRaw('pusher:subscribe', {
          'channel': channelName,
          'auth': authData['auth'],
          'channel_data': authData['channel_data'],
        });
        AppLogger.i('Subscribed to presence channel: $channelName');
      }
    } catch (e) {
      AppLogger.e('Failed to authorize call channel $channelName', e);
    }
  }

  /// Unsubscribe from a channel
  void unsubscribe(String channelName) {
    _subscribedChannels.remove(channelName);
    if (_status == WebSocketConnectionStatus.connected) {
      sendRaw('pusher:unsubscribe', {'channel': channelName});
    }
  }

  void _resubscribeAll() {
    final channels = List<String>.from(_subscribedChannels);
    _subscribedChannels.clear();
    for (final ch in channels) {
      if (ch.startsWith('private-user.')) {
        final userId = int.tryParse(ch.replaceFirst('private-user.', ''));
        if (userId != null) subscribeToUserChannel(userId);
      } else if (ch.startsWith('presence-call.')) {
        final callId = ch.replaceFirst('presence-call.', '');
        subscribeToCallChannel(callId);
      }
    }
  }

  /// Send a raw pusher protocol message
  void sendRaw(String event, Map<String, dynamic> data) {
    if (_socket != null && _status == WebSocketConnectionStatus.connected) {
      final payload = jsonEncode({'event': event, 'data': data});
      _socket!.add(payload);
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_status == WebSocketConnectionStatus.connected) {
        sendRaw('pusher:ping', {});
        // Refresh online presence timestamp on backend
        try {
          await _apiClient.dio.post('/user/heartbeat', data: {'is_online': true});
        } catch (_) {}
      }
    });
  }

  void _onDisconnected() {
    AppLogger.w('Reverb WebSocket disconnected');
    _cleanSocket();
    if (!_isManualDisconnect) {
      _scheduleReconnect();
    } else {
      _setStatus(WebSocketConnectionStatus.disconnected);
    }
  }

  void _onError(dynamic error) {
    AppLogger.e('Reverb WebSocket error', error);
    _cleanSocket();
    if (!_isManualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _setStatus(WebSocketConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();

    _reconnectAttempts++;
    final delaySeconds = (_reconnectAttempts > 5 ? 15 : _reconnectAttempts * 2);
    AppLogger.i('Reconnecting in $delaySeconds seconds (attempt $_reconnectAttempts)...');

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      connect();
    });
  }

  void _cleanSocket() {
    _pingTimer?.cancel();
    _socket?.close();
    _socket = null;
    _socketId = null;
  }

  void _setStatus(WebSocketConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  /// Disconnect and clean resources
  void disconnect({bool notifyBackend = true}) {
    _isManualDisconnect = true;
    _reconnectTimer?.cancel();
    _cleanSocket();
    _subscribedChannels.clear();
    _setStatus(WebSocketConnectionStatus.disconnected);
    AppLogger.i('WebSocket manually disconnected');
    if (notifyBackend) {
      _apiClient.dio.post('/user/heartbeat', data: {'is_online': false}).ignore();
    }
  }

  /// Explicitly update presence state (online / away)
  Future<void> updatePresence(bool isOnline) async {
    try {
      await _apiClient.dio.post('/user/heartbeat', data: {'is_online': isOnline});
      if (isOnline && _status != WebSocketConnectionStatus.connected) {
        connect();
      }
    } catch (_) {}
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _statusController.close();
  }
}
