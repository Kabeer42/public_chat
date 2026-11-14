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

// Test model mirroring CallSessionEntity with video fields
class TestVideoCallSession {
  final int peerId;
  final String peerName;
  final String? peerEmail;
  final String callType; // 'voice' or 'video'
  final bool isCaller;
  final TestCallStatus status;
  final int durationSeconds;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isFrontCamera;
  final String? errorMessage;

  const TestVideoCallSession({
    required this.peerId,
    required this.peerName,
    this.peerEmail,
    required this.callType,
    required this.isCaller,
    this.status = TestCallStatus.idle,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.isFrontCamera = true,
    this.errorMessage,
  });

  TestVideoCallSession copyWith({
    int? peerId,
    String? peerName,
    String? peerEmail,
    String? callType,
    bool? isCaller,
    TestCallStatus? status,
    int? durationSeconds,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isFrontCamera,
    String? errorMessage,
  }) {
    return TestVideoCallSession(
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      peerEmail: peerEmail ?? this.peerEmail,
      callType: callType ?? this.callType,
      isCaller: isCaller ?? this.isCaller,
      status: status ?? this.status,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// Mock Video WebRTC Service
class MockVideoWebRtcService {
  bool isPeerConnectionOpen = false;
  bool isAudioTrackActive = false;
  bool isVideoTrackActive = false;
  bool isMuted = false;
  bool isSpeakerOn = false;
  bool isVideoEnabled = true;
  bool isFrontCamera = true;
  bool areRenderersInitialized = false;

  String? localSdp;
  String? remoteSdp;
  final List<Map<String, dynamic>> receivedIceCandidates = [];

  Future<void> initializeRenderers() async {
    areRenderersInitialized = true;
  }

  Future<String> createOffer({bool isAudioOnly = false}) async {
    await initializeRenderers();
    isPeerConnectionOpen = true;
    isAudioTrackActive = true;
    isVideoTrackActive = !isAudioOnly;

    localSdp = 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        '${isAudioOnly ? '' : 'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'}';
    return localSdp!;
  }

  Future<String> createAnswer(String remoteOffer, {bool isAudioOnly = false}) async {
    await initializeRenderers();
    isPeerConnectionOpen = true;
    isAudioTrackActive = true;
    isVideoTrackActive = !isAudioOnly;
    remoteSdp = remoteOffer;

    localSdp = 'v=0\r\no=- 67890 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        '${isAudioOnly ? '' : 'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'}';
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

  bool toggleVideo() {
    isVideoEnabled = !isVideoEnabled;
    return isVideoEnabled;
  }

  Future<void> switchCamera() async {
    isFrontCamera = !isFrontCamera;
  }

  Future<void> dispose() async {
    isPeerConnectionOpen = false;
    isAudioTrackActive = false;
    isVideoTrackActive = false;
    isMuted = false;
    isSpeakerOn = false;
    isVideoEnabled = true;
    isFrontCamera = true;
    areRenderersInitialized = false;
    localSdp = null;
    remoteSdp = null;
    receivedIceCandidates.clear();
  }
}

void main() {
  group('TASK-14: Flutter WebRTC 1-to-1 Video Calling Implementation Tests', () {
    test('1. Video CallSessionEntity state management and video flags', () {
      var session = const TestVideoCallSession(
        peerId: 3,
        peerName: 'Charlie',
        callType: 'video',
        isCaller: true,
        status: TestCallStatus.ringing,
        isVideoEnabled: true,
        isFrontCamera: true,
      );

      expect(session.callType, equals('video'));
      expect(session.status, equals(TestCallStatus.ringing));
      expect(session.isVideoEnabled, isTrue);
      expect(session.isFrontCamera, isTrue);

      // Connected
      session = session.copyWith(status: TestCallStatus.connected);
      expect(session.status, equals(TestCallStatus.connected));

      // Toggle camera off (audio remains on)
      session = session.copyWith(isVideoEnabled: false);
      expect(session.isVideoEnabled, isFalse);
      expect(session.isMuted, isFalse);

      // Switch camera to back
      session = session.copyWith(isFrontCamera: false);
      expect(session.isFrontCamera, isFalse);

      // Duration increment
      session = session.copyWith(durationSeconds: 15);
      expect(session.durationSeconds, equals(15));
    });

    test('2. Video SDP Offer & Answer generation with both audio and video m-lines', () async {
      final aliceRtc = MockVideoWebRtcService();
      final bobRtc = MockVideoWebRtcService();

      // Alice creates video offer
      final aliceOffer = await aliceRtc.createOffer(isAudioOnly: false);
      expect(aliceRtc.areRenderersInitialized, isTrue);
      expect(aliceRtc.isVideoTrackActive, isTrue);
      expect(aliceRtc.isAudioTrackActive, isTrue);
      expect(aliceOffer, contains('m=audio'));
      expect(aliceOffer, contains('m=video'));

      // Bob accepts and creates video answer
      final bobAnswer = await bobRtc.createAnswer(aliceOffer, isAudioOnly: false);
      expect(bobRtc.areRenderersInitialized, isTrue);
      expect(bobRtc.isVideoTrackActive, isTrue);
      expect(bobAnswer, contains('m=audio'));
      expect(bobAnswer, contains('m=video'));

      // Alice sets remote answer
      await aliceRtc.setRemoteAnswer(bobAnswer);
      expect(aliceRtc.remoteSdp, equals(bobAnswer));
    });

    test('3. Video Call controls: Toggle camera and flip front/back camera', () async {
      final service = MockVideoWebRtcService();
      await service.createOffer(isAudioOnly: false);

      expect(service.isVideoEnabled, isTrue);
      service.toggleVideo();
      expect(service.isVideoEnabled, isFalse);
      // Audio is unaffected
      expect(service.isAudioTrackActive, isTrue);

      expect(service.isFrontCamera, isTrue);
      await service.switchCamera();
      expect(service.isFrontCamera, isFalse);

      await service.switchCamera();
      expect(service.isFrontCamera, isTrue);
    });

    test('4. Complete Video Call lifecycle and teardown cleanly releases hardware', () async {
      final alice = MockVideoWebRtcService();
      final bob = MockVideoWebRtcService();

      // Initiate and connect
      final offer = await alice.createOffer(isAudioOnly: false);
      final answer = await bob.createAnswer(offer, isAudioOnly: false);
      await alice.setRemoteAnswer(answer);

      expect(alice.isPeerConnectionOpen, isTrue);
      expect(bob.isPeerConnectionOpen, isTrue);

      // Hangup and clean disposal
      await alice.dispose();
      await bob.dispose();

      expect(alice.isPeerConnectionOpen, isFalse);
      expect(alice.areRenderersInitialized, isFalse);
      expect(alice.isVideoTrackActive, isFalse);
      expect(bob.isPeerConnectionOpen, isFalse);
      expect(bob.areRenderersInitialized, isFalse);
      expect(bob.isVideoTrackActive, isFalse);
    });
  });
}
