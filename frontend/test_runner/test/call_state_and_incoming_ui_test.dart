import 'package:test/test.dart';

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

class TestCallSession {
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
    this.isVideoEnabled = true,
    this.isFrontCamera = true,
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
    bool? isVideoEnabled,
    bool? isFrontCamera,
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
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// Simulated State Machine for Call Management
class TestCallStateMachine {
  TestCallSession? currentSession;
  final List<String> dispatchedSignalingLogs = [];
  bool areHardwareResourcesReleased = false;

  bool get isIdle => currentSession == null || currentSession!.status == TestCallStatus.idle;

  // Caller starts outgoing call
  void startOutgoingCall({
    required int peerId,
    required String peerName,
    required String callType,
  }) {
    currentSession = TestCallSession(
      peerId: peerId,
      peerName: peerName,
      callType: callType,
      isCaller: true,
      status: TestCallStatus.ringing,
    );
    areHardwareResourcesReleased = false;
    dispatchedSignalingLogs.add('OUTGOING_OFFER: to=$peerId, type=$callType');
  }

  // Callee receives incoming call offer
  bool handleIncomingOffer({
    required int callerId,
    required String callerName,
    required String callType,
    required String sdpOffer,
  }) {
    // If already in an active call, auto-reject with busy
    if (!isIdle &&
        (currentSession!.status == TestCallStatus.connected ||
            currentSession!.status == TestCallStatus.connecting ||
            currentSession!.status == TestCallStatus.ringing)) {
      dispatchedSignalingLogs.add('AUTO_REJECT_BUSY: to=$callerId, reason=busy');
      return false; // rejected
    }

    currentSession = TestCallSession(
      peerId: callerId,
      peerName: callerName,
      callType: callType,
      isCaller: false,
      status: TestCallStatus.ringing,
    );
    areHardwareResourcesReleased = false;
    dispatchedSignalingLogs.add('INCOMING_RINGING: from=$callerId, type=$callType');
    return true; // accepted into ringing
  }

  // Callee accepts incoming call
  void acceptIncomingCall() {
    if (currentSession != null && currentSession!.status == TestCallStatus.ringing) {
      currentSession = currentSession!.copyWith(status: TestCallStatus.connecting);
      dispatchedSignalingLogs.add('SEND_ANSWER: to=${currentSession!.peerId}');

      // Connection established
      currentSession = currentSession!.copyWith(status: TestCallStatus.connected);
      dispatchedSignalingLogs.add('CALL_CONNECTED: peer=${currentSession!.peerId}');
    }
  }

  // Callee declines incoming call
  void declineIncomingCall() {
    if (currentSession != null) {
      dispatchedSignalingLogs.add('REJECT_CALL: to=${currentSession!.peerId}, reason=rejected');
      currentSession = currentSession!.copyWith(status: TestCallStatus.rejected);
      releaseHardware();
    }
  }

  // Either party hangs up
  void hangupCall() {
    if (currentSession != null) {
      dispatchedSignalingLogs.add('END_CALL: to=${currentSession!.peerId}, reason=hangup');
      currentSession = currentSession!.copyWith(status: TestCallStatus.ended);
      releaseHardware();
    }
  }

  // Remote caller/callee ends call
  void handleRemoteEnded({required String reason}) {
    if (currentSession != null) {
      dispatchedSignalingLogs.add('REMOTE_ENDED: reason=$reason');
      currentSession = currentSession!.copyWith(
        status: TestCallStatus.ended,
        errorMessage: reason,
      );
      releaseHardware();
    }
  }

  void releaseHardware() {
    areHardwareResourcesReleased = true;
  }

  void resetToIdle() {
    currentSession = null;
    areHardwareResourcesReleased = true;
  }
}

void main() {
  group('TASK-15: Call State Management, Incoming Ringing & UI Flows Tests', () {
    test('1. Outgoing call lifecycle: Idle -> Ringing -> Connected -> Ended', () {
      final sm = TestCallStateMachine();
      expect(sm.isIdle, isTrue);

      // Alice initiates call to Bob
      sm.startOutgoingCall(peerId: 2, peerName: 'Bob', callType: 'voice');
      expect(sm.isIdle, isFalse);
      expect(sm.currentSession!.status, equals(TestCallStatus.ringing));
      expect(sm.currentSession!.isCaller, isTrue);

      // Bob answers, Alice receives answer
      sm.currentSession = sm.currentSession!.copyWith(status: TestCallStatus.connected);
      expect(sm.currentSession!.status, equals(TestCallStatus.connected));

      // Alice hangs up
      sm.hangupCall();
      expect(sm.currentSession!.status, equals(TestCallStatus.ended));
      expect(sm.areHardwareResourcesReleased, isTrue);

      // Reset back to idle
      sm.resetToIdle();
      expect(sm.isIdle, isTrue);
    });

    test('2. Callee receives incoming call: Idle -> Incoming Ringing -> Accept -> Connected', () {
      final bobSm = TestCallStateMachine();
      expect(bobSm.isIdle, isTrue);

      // Bob receives call offer from Alice
      final ringingAllowed = bobSm.handleIncomingOffer(
        callerId: 1,
        callerName: 'Alice',
        callType: 'video',
        sdpOffer: 'mock_offer_sdp',
      );

      expect(ringingAllowed, isTrue);
      expect(bobSm.currentSession!.status, equals(TestCallStatus.ringing));
      expect(bobSm.currentSession!.isCaller, isFalse);
      expect(bobSm.currentSession!.callType, equals('video'));

      // Bob accepts
      bobSm.acceptIncomingCall();
      expect(bobSm.currentSession!.status, equals(TestCallStatus.connected));
      expect(bobSm.dispatchedSignalingLogs, contains('CALL_CONNECTED: peer=1'));
    });

    test('3. Callee declines incoming call: Idle -> Incoming Ringing -> Decline -> Ended', () {
      final bobSm = TestCallStateMachine();

      bobSm.handleIncomingOffer(
        callerId: 1,
        callerName: 'Alice',
        callType: 'voice',
        sdpOffer: 'mock_offer_sdp',
      );

      expect(bobSm.currentSession!.status, equals(TestCallStatus.ringing));

      // Bob declines
      bobSm.declineIncomingCall();
      expect(bobSm.currentSession!.status, equals(TestCallStatus.rejected));
      expect(bobSm.areHardwareResourcesReleased, isTrue);
      expect(bobSm.dispatchedSignalingLogs, contains('REJECT_CALL: to=1, reason=rejected'));
    });

    test('4. Auto-reject with busy when user is already in active call', () {
      final userSm = TestCallStateMachine();

      // User is currently connected in call with Alice (id: 1)
      userSm.startOutgoingCall(peerId: 1, peerName: 'Alice', callType: 'voice');
      userSm.currentSession = userSm.currentSession!.copyWith(status: TestCallStatus.connected);

      // Charlie (id: 3) tries to call User simultaneously
      final accepted = userSm.handleIncomingOffer(
        callerId: 3,
        callerName: 'Charlie',
        callType: 'video',
        sdpOffer: 'charlie_offer_sdp',
      );

      // Must be rejected with busy
      expect(accepted, isFalse);
      expect(userSm.dispatchedSignalingLogs, contains('AUTO_REJECT_BUSY: to=3, reason=busy'));

      // Existing call with Alice is NOT interrupted
      expect(userSm.currentSession!.peerId, equals(1));
      expect(userSm.currentSession!.status, equals(TestCallStatus.connected));
    });

    test('5. Remote Caller cancels call before Callee answers', () {
      final calleeSm = TestCallStateMachine();

      // Incoming call arrives and starts ringing
      calleeSm.handleIncomingOffer(
        callerId: 1,
        callerName: 'Alice',
        callType: 'voice',
        sdpOffer: 'mock_offer_sdp',
      );
      expect(calleeSm.currentSession!.status, equals(TestCallStatus.ringing));

      // Caller cancels call
      calleeSm.handleRemoteEnded(reason: 'Caller cancelled');
      expect(calleeSm.currentSession!.status, equals(TestCallStatus.ended));
      expect(calleeSm.currentSession!.errorMessage, equals('Caller cancelled'));
      expect(calleeSm.areHardwareResourcesReleased, isTrue);
    });
  });
}
