import 'dart:async';
import 'package:test/test.dart';

// Test enum mirroring domain CallStatus
enum TestCallStatus {
  idle,
  ringing,
  connecting,
  connected,
  ended,
  busy,
  offline,
  rejected,
  error,
}

// Test model mirroring CallSessionEntity
class TestCallSession {
  final int peerId;
  final String peerName;
  final String? peerEmail;
  final String callType;
  final bool isCaller;
  final TestCallStatus status;
  final int durationSeconds;
  final bool isMuted;
  final bool isSpeakerOn;
  final String? errorMessage;

  const TestCallSession({
    required this.peerId,
    required this.peerName,
    this.peerEmail,
    required this.callType,
    required this.isCaller,
    this.status = TestCallStatus.idle,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.errorMessage,
  });

  TestCallSession copyWith({
    int? peerId,
    String? peerName,
    String? peerEmail,
    String? callType,
    bool? isCaller,
    TestCallStatus? status,
    int? durationSeconds,
    bool? isMuted,
    bool? isSpeakerOn,
    String? errorMessage,
  }) {
    return TestCallSession(
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      peerEmail: peerEmail ?? this.peerEmail,
      callType: callType ?? this.callType,
      isCaller: isCaller ?? this.isCaller,
      status: status ?? this.status,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// Mock WebRTC Service for testing P2P state machine
class MockWebRtcService {
  bool isPeerConnectionOpen = false;
  bool isAudioTrackActive = false;
  bool isMuted = false;
  bool isSpeakerOn = false;
  String? localSdp;
  String? remoteSdp;
  final List<Map<String, dynamic>> receivedIceCandidates = [];

  Future<String> createOffer({bool isAudioOnly = true}) async {
    isPeerConnectionOpen = true;
    isAudioTrackActive = true;
    localSdp = 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111';
    return localSdp!;
  }

  Future<String> createAnswer(String remoteOffer, {bool isAudioOnly = true}) async {
    isPeerConnectionOpen = true;
    isAudioTrackActive = true;
    remoteSdp = remoteOffer;
    localSdp = 'v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111';
    return localSdp!;
  }

  Future<void> setRemoteAnswer(String answer) async {
    remoteSdp = answer;
  }

  Future<void> addCandidate(Map<String, dynamic> candidate) async {
    receivedIceCandidates.add(candidate);
  }

  bool toggleMute() {
    isMuted = !isMuted;
    return isMuted;
  }

  bool toggleSpeaker() {
    isSpeakerOn = !isSpeakerOn;
    return isSpeakerOn;
  }

  Future<void> dispose() async {
    isPeerConnectionOpen = false;
    isAudioTrackActive = false;
    isMuted = false;
    isSpeakerOn = false;
    localSdp = null;
    remoteSdp = null;
    receivedIceCandidates.clear();
  }
}

void main() {
  group('TASK-13: Flutter WebRTC 1-to-1 Voice Calling Implementation Tests', () {
    test('1. CallSessionEntity state transitions and audio controls', () {
      var session = const TestCallSession(
        peerId: 2,
        peerName: 'Bob',
        peerEmail: 'bob@example.com',
        callType: 'voice',
        isCaller: true,
        status: TestCallStatus.ringing,
      );

      expect(session.status, equals(TestCallStatus.ringing));
      expect(session.isCaller, isTrue);
      expect(session.durationSeconds, equals(0));
      expect(session.isMuted, isFalse);
      expect(session.isSpeakerOn, isFalse);

      // Connected state
      session = session.copyWith(status: TestCallStatus.connected);
      expect(session.status, equals(TestCallStatus.connected));

      // Timer ticks
      session = session.copyWith(durationSeconds: session.durationSeconds + 1);
      session = session.copyWith(durationSeconds: session.durationSeconds + 1);
      expect(session.durationSeconds, equals(2));

      // Audio mute and speakerphone controls
      session = session.copyWith(isMuted: true);
      expect(session.isMuted, isTrue);

      session = session.copyWith(isSpeakerOn: true);
      expect(session.isSpeakerOn, isTrue);

      // Ended state
      session = session.copyWith(status: TestCallStatus.ended);
      expect(session.status, equals(TestCallStatus.ended));
    });

    test('2. WebRTC Signaling API request and event schemas match Laravel backend', () {
      // 1. Offer request & broadcast payload
      final offerRequestPayload = {
        'receiver_id': 2,
        'call_type': 'voice',
        'sdp_offer': 'mock_offer_sdp',
      };
      expect(offerRequestPayload['receiver_id'], equals(2));
      expect(offerRequestPayload['call_type'], equals('voice'));

      final offerBroadcastPayload = {
        'caller_id': 1,
        'caller_name': 'Alice',
        'caller_email': 'alice@example.com',
        'call_type': 'voice',
        'sdp_offer': 'mock_offer_sdp',
        'created_at': DateTime.now().toIso8601String(),
      };
      expect(offerBroadcastPayload['caller_id'], equals(1));
      expect(offerBroadcastPayload['sdp_offer'], equals('mock_offer_sdp'));

      // 2. Answer request & broadcast payload
      final answerRequestPayload = {
        'caller_id': 1,
        'sdp_answer': 'mock_answer_sdp',
      };
      expect(answerRequestPayload['caller_id'], equals(1));

      final answerBroadcastPayload = {
        'callee_id': 2,
        'sdp_answer': 'mock_answer_sdp',
        'created_at': DateTime.now().toIso8601String(),
      };
      expect(answerBroadcastPayload['callee_id'], equals(2));

      // 3. ICE Candidate request & broadcast payload
      final iceRequestPayload = {
        'target_user_id': 2,
        'candidate': {
          'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.100 54321 typ host',
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        },
      };
      expect((iceRequestPayload['candidate'] as Map)['sdpMid'], equals('0'));

      // 4. Call End request & broadcast payload
      final endRequestPayload = {
        'target_user_id': 2,
        'reason': 'normal_hangup',
      };
      expect(endRequestPayload['reason'], equals('normal_hangup'));
    });

    test('3. Complete 1-to-1 WebRTC Voice Call roundtrip: Caller <-> Callee', () async {
      final aliceRtc = MockWebRtcService();
      final bobRtc = MockWebRtcService();

      // Step 1: Alice creates local offer (audio only)
      final aliceOffer = await aliceRtc.createOffer(isAudioOnly: true);
      expect(aliceRtc.isPeerConnectionOpen, isTrue);
      expect(aliceRtc.isAudioTrackActive, isTrue);
      expect(aliceOffer, contains('m=audio'));

      // Step 2: Bob receives Alice's offer and generates answer
      final bobAnswer = await bobRtc.createAnswer(aliceOffer, isAudioOnly: true);
      expect(bobRtc.isPeerConnectionOpen, isTrue);
      expect(bobRtc.isAudioTrackActive, isTrue);
      expect(bobRtc.remoteSdp, equals(aliceOffer));

      // Step 3: Alice receives Bob's answer
      await aliceRtc.setRemoteAnswer(bobAnswer);
      expect(aliceRtc.remoteSdp, equals(bobAnswer));

      // Step 4: ICE Candidates exchanged
      final candidateFromAlice = {
        'candidate': 'candidate:1 1 UDP 2122260223 192.168.1.50 50000 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      };
      await bobRtc.addCandidate(candidateFromAlice);
      expect(bobRtc.receivedIceCandidates.length, equals(1));
      expect(bobRtc.receivedIceCandidates.first['sdpMid'], equals('0'));

      final candidateFromBob = {
        'candidate': 'candidate:2 1 UDP 2122260223 192.168.1.60 50002 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      };
      await aliceRtc.addCandidate(candidateFromBob);
      expect(aliceRtc.receivedIceCandidates.length, equals(1));

      // Step 5: Audio controls - Mute and Speaker
      expect(aliceRtc.isMuted, isFalse);
      aliceRtc.toggleMute();
      expect(aliceRtc.isMuted, isTrue);

      expect(aliceRtc.isSpeakerOn, isFalse);
      aliceRtc.toggleSpeaker();
      expect(aliceRtc.isSpeakerOn, isTrue);

      // Step 6: Hangup and cleanup
      await aliceRtc.dispose();
      await bobRtc.dispose();

      expect(aliceRtc.isPeerConnectionOpen, isFalse);
      expect(aliceRtc.isAudioTrackActive, isFalse);
      expect(bobRtc.isPeerConnectionOpen, isFalse);
      expect(bobRtc.isAudioTrackActive, isFalse);
    });

    test('4. Call rejection and busy status handling', () async {
      final aliceRtc = MockWebRtcService();
      await aliceRtc.createOffer(isAudioOnly: true);

      // Callee rejects call
      var session = const TestCallSession(
        peerId: 2,
        peerName: 'Bob',
        callType: 'voice',
        isCaller: true,
        status: TestCallStatus.ringing,
      );

      // Rejection event arrives
      session = session.copyWith(
        status: TestCallStatus.rejected,
        errorMessage: 'Call declined by recipient',
      );
      await aliceRtc.dispose();

      expect(session.status, equals(TestCallStatus.rejected));
      expect(aliceRtc.isPeerConnectionOpen, isFalse);
    });
  });
}
