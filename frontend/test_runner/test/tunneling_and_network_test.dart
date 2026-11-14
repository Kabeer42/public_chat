import 'package:test/test.dart';

// Test model mirroring dynamic AppConfig behavior
class TestNetworkConfig {
  String apiBaseUrl;
  String wsHost;
  int wsPort;
  String wsScheme;
  String turnUrl;
  String turnUsername;
  String turnCredential;

  final List<String> defaultStunServers = const [
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun2.l.google.com:19302',
  ];

  TestNetworkConfig({
    this.apiBaseUrl = 'http://10.0.2.2:8000/api/v1',
    this.wsHost = '10.0.2.2',
    this.wsPort = 8080,
    this.wsScheme = 'ws',
    this.turnUrl = '',
    this.turnUsername = '',
    this.turnCredential = '',
  });

  void update({
    required String apiUrl,
    required String host,
    required int port,
    required String scheme,
    String? turn,
    String? user,
    String? cred,
  }) {
    apiBaseUrl = apiUrl.trim();
    wsHost = host.trim();
    wsPort = port;
    wsScheme = scheme.trim();
    if (turn != null) turnUrl = turn.trim();
    if (user != null) turnUsername = user.trim();
    if (cred != null) turnCredential = cred.trim();
  }

  void reset() {
    apiBaseUrl = 'http://10.0.2.2:8000/api/v1';
    wsHost = '10.0.2.2';
    wsPort = 8080;
    wsScheme = 'ws';
    turnUrl = '';
    turnUsername = '';
    turnCredential = '';
  }

  String get normalizedHealthEndpoint {
    final clean = apiBaseUrl.trim();
    return clean.endsWith('/') ? '${clean}health' : '$clean/health';
  }

  String buildWebSocketUri(String appKey) {
    return '$wsScheme://$wsHost:$wsPort/app/$appKey?protocol=7&client=js&version=8.4.0-reverb&flash=false';
  }

  Map<String, dynamic> get iceServersConfiguration {
    final iceServers = <Map<String, dynamic>>[
      {'urls': defaultStunServers},
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
}

void main() {
  group('TASK-16: Cross-Network Tunneling & STUN/TURN Verification Tests', () {
    test('1. Default network configuration matches local development environment', () {
      final config = TestNetworkConfig();

      expect(config.apiBaseUrl, equals('http://10.0.2.2:8000/api/v1'));
      expect(config.wsHost, equals('10.0.2.2'));
      expect(config.wsPort, equals(8080));
      expect(config.wsScheme, equals('ws'));

      final uri = config.buildWebSocketUri('reverb_key');
      expect(uri, contains('ws://10.0.2.2:8080/app/reverb_key'));
    });

    test('2. Dynamic update switches to Cloudflare Tunnel (HTTPS & WSS on port 443)', () {
      final config = TestNetworkConfig();

      config.update(
        apiUrl: 'https://api.chatapp-demo.trycloudflare.com/api/v1',
        host: 'ws.chatapp-demo.trycloudflare.com',
        port: 443,
        scheme: 'wss',
      );

      expect(config.apiBaseUrl, equals('https://api.chatapp-demo.trycloudflare.com/api/v1'));
      expect(config.wsHost, equals('ws.chatapp-demo.trycloudflare.com'));
      expect(config.wsPort, equals(443));
      expect(config.wsScheme, equals('wss'));

      final wsUri = config.buildWebSocketUri('test_app_key');
      expect(wsUri, startsWith('wss://ws.chatapp-demo.trycloudflare.com:443/app/test_app_key'));
    });

    test('3. Dynamic update switches to Ngrok forwarding tunnels', () {
      final config = TestNetworkConfig();

      config.update(
        apiUrl: 'https://1234-api.ngrok-free.app/api/v1',
        host: '5678-ws.ngrok-free.app',
        port: 443,
        scheme: 'wss',
      );

      expect(config.apiBaseUrl, contains('ngrok-free.app'));
      expect(config.wsScheme, equals('wss'));
      expect(config.normalizedHealthEndpoint, equals('https://1234-api.ngrok-free.app/api/v1/health'));
    });

    test('4. WebRTC ICE configuration generates Google STUN servers', () {
      final config = TestNetworkConfig();
      final ice = config.iceServersConfiguration;

      expect(ice['sdpSemantics'], equals('unified-plan'));
      final iceServers = ice['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, equals(1));
      expect(iceServers.first['urls'], contains('stun:stun.l.google.com:19302'));
    });

    test('5. WebRTC ICE configuration includes TURN fallback when specified', () {
      final config = TestNetworkConfig();

      config.update(
        apiUrl: 'https://api.tunnel.com/api/v1',
        host: 'ws.tunnel.com',
        port: 443,
        scheme: 'wss',
        turn: 'turn:relay.metered.ca:80,turn:relay.metered.ca:443?transport=tcp',
        user: 'turn_user_123',
        cred: 'turn_secret_pass',
      );

      final ice = config.iceServersConfiguration;
      final iceServers = ice['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers.length, equals(2));

      // STUN entry
      expect(iceServers[0]['urls'], contains('stun:stun.l.google.com:19302'));

      // TURN entry
      final turnEntry = iceServers[1];
      expect(turnEntry['username'], equals('turn_user_123'));
      expect(turnEntry['credential'], equals('turn_secret_pass'));
      expect(turnEntry['urls'], isA<List>());
      expect((turnEntry['urls'] as List).length, equals(2));
    });

    test('6. Reset cleanly restores defaults', () {
      final config = TestNetworkConfig();

      config.update(
        apiUrl: 'https://custom.com/api/v1',
        host: 'custom.com',
        port: 443,
        scheme: 'wss',
        turn: 'turn:turn.com',
      );
      expect(config.wsPort, equals(443));

      config.reset();
      expect(config.apiBaseUrl, equals('http://10.0.2.2:8000/api/v1'));
      expect(config.wsHost, equals('10.0.2.2'));
      expect(config.wsPort, equals(8080));
      expect(config.wsScheme, equals('ws'));
      expect(config.turnUrl, isEmpty);
    });
  });
}
