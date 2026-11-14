import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatapp/core/network/api_client.dart';
import 'package:chatapp/features/call/data/services/call_audio_service.dart';
import 'package:chatapp/features/call/data/services/webrtc_service.dart';
import 'package:chatapp/features/call/domain/entities/call_entity.dart';
import 'package:chatapp/features/call/domain/repositories/call_repository.dart';
import 'package:chatapp/features/call/domain/usecases/answer_call_usecase.dart';
import 'package:chatapp/features/call/domain/usecases/end_call_usecase.dart';
import 'package:chatapp/features/call/domain/usecases/initiate_call_usecase.dart';
import 'package:chatapp/features/call/domain/usecases/send_ice_candidate_usecase.dart';
import 'package:chatapp/features/call/presentation/bloc/call_bloc.dart';
import 'package:chatapp/features/call/presentation/bloc/call_event.dart';
import 'package:chatapp/features/call/presentation/bloc/call_state.dart';

class FakeApiClient implements ApiClient {
  String? reportedScreen;
  String? reportedFunction;
  String? reportedMessage;
  String? mockRefCode = 'ERR-MOCK-CALL123';

  @override
  Future<String?> reportClientError({
    required String message,
    String? errorCode,
    String? exceptionClass,
    String? stackTrace,
    String? screen,
    String? functionName,
    Map<String, dynamic>? metadata,
  }) async {
    reportedMessage = message;
    reportedScreen = screen;
    reportedFunction = functionName;
    return mockRefCode;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCallAudioService extends CallAudioService {
  bool startedRinging = false;
  bool isIncomingRingtone = false;
  bool stoppedRinging = false;

  @override
  Future<void> startRingtone({required bool isIncoming}) async {
    startedRinging = true;
    isIncomingRingtone = isIncoming;
  }

  @override
  Future<void> stopRingtone() async {
    stoppedRinging = true;
  }

  @override
  Future<void> dispose() async {}
}

class FakeCallRepository implements CallRepository {
  final _signalingController = StreamController<Map<String, dynamic>>.broadcast();

  bool initiateCallCalled = false;
  bool answerCallCalled = false;
  bool endCallCalled = false;
  bool shouldThrowOnInitiate = false;
  String? lastEndReason;
  int? lastEndedTarget;

  void emitSignalingEvent(String event, Map<String, dynamic> data) {
    _signalingController.add({'event': event, 'data': data});
  }

  @override
  Stream<Map<String, dynamic>> get signalingEventStream => _signalingController.stream;

  @override
  IWebRtcService get webRtcService => throw UnimplementedError();

  @override
  Future<void> initiateCall({required int receiverId, required String callType}) async {
    if (shouldThrowOnInitiate) {
      throw Exception('Peer connection failed');
    }
    initiateCallCalled = true;
  }

  @override
  Future<void> answerCall({required int callerId, required String sdpOffer, String callType = 'voice', String? callId}) async {
    answerCallCalled = true;
  }

  @override
  Future<void> endCall({required int targetUserId, String? reason}) async {
    endCallCalled = true;
    lastEndedTarget = targetUserId;
    lastEndReason = reason;
  }

  @override
  Future<void> handleRemoteAnswer({required String sdpAnswer}) async {}

  @override
  Future<void> handleRemoteIceCandidate({required Map<String, dynamic> candidate}) async {}

  @override
  Future<void> sendIceCandidate({required int targetUserId, required Map<String, dynamic> candidate}) async {}

  @override
  bool toggleMute() => false;

  @override
  bool toggleSpeaker() => false;

  @override
  bool toggleVideo() => false;

  @override
  Future<void> switchCamera() async {}

  @override
  bool get isScreenSharing => false;

  @override
  Future<bool> startScreenShare() async => true;

  @override
  Future<void> stopScreenShare() async {}

  @override
  Future<void> disposeCall() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallBloc Feature Tests (TASK-26)', () {
    late FakeCallRepository fakeRepo;
    late FakeCallAudioService fakeAudio;
    late FakeApiClient fakeApiClient;
    late CallBloc callBloc;

    setUp(() {
      fakeRepo = FakeCallRepository();
      fakeAudio = FakeCallAudioService();
      fakeApiClient = FakeApiClient();

      callBloc = CallBloc(
        initiateCallUseCase: InitiateCallUseCase(fakeRepo),
        answerCallUseCase: AnswerCallUseCase(fakeRepo),
        endCallUseCase: EndCallUseCase(fakeRepo),
        sendIceCandidateUseCase: SendIceCandidateUseCase(fakeRepo),
        callRepository: fakeRepo,
        callAudioService: fakeAudio,
        apiClient: fakeApiClient,
      );
    });

    tearDown(() async {
      await callBloc.close();
    });

    test('Incoming call signaling event with sdp key parses correctly and plays incoming ringtone', () async {
      fakeRepo.emitSignalingEvent('call.offer', {
        'caller_id': 42,
        'caller_name': 'Jane Doe',
        'caller_email': 'jane@example.com',
        'sdp': 'v=0\r\no=- 12345 2 IN IP4 127.0.0.1\r\ns=-\r\n',
        'call_type': 'video',
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.peerId, 42);
      expect(session.peerName, 'Jane Doe');
      expect(session.callType, 'video');
      expect(session.status, CallStatus.ringing);
      expect(session.isCaller, false);

      expect(fakeAudio.startedRinging, true);
      expect(fakeAudio.isIncomingRingtone, true);
    });

    test('Outgoing call initiates, starts audio ringback, and transitions to ringing', () async {
      callBloc.add(const StartOutgoingCallEvent(
        peerId: 99,
        peerName: 'Bob Partner',
        callType: 'voice',
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(fakeRepo.initiateCallCalled, true);
      expect(fakeAudio.startedRinging, true);
      expect(fakeAudio.isIncomingRingtone, false);

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.peerId, 99);
      expect(session.status, CallStatus.ringing);
      expect(session.isCaller, true);
    });

    test('CallRingingTimeoutEvent ends ringing call after 60s timeout with no_answer reason', () async {
      callBloc.add(const StartOutgoingCallEvent(
        peerId: 77,
        peerName: 'Alice',
        callType: 'voice',
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      // Trigger 60s timeout
      callBloc.add(const CallRingingTimeoutEvent());
      await Future.delayed(const Duration(milliseconds: 20));

      expect(fakeRepo.endCallCalled, true);
      expect(fakeRepo.lastEndReason, 'no_answer');
      expect(fakeAudio.stoppedRinging, true);

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.status, CallStatus.ended);
      expect(session.errorMessage, contains('timed out'));
    });

    test('RejectCallEvent stops ringing and transitions state to rejected', () async {
      callBloc.add(const IncomingCallReceivedEvent(
        callerId: 10,
        callerName: 'Charlie',
        sdpOffer: 'dummy-offer',
        callType: 'voice',
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      callBloc.add(const RejectCallEvent());
      await Future.delayed(const Duration(milliseconds: 20));

      expect(fakeRepo.endCallCalled, true);
      expect(fakeRepo.lastEndReason, 'rejected');
      expect(fakeAudio.stoppedRinging, true);

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.status, CallStatus.rejected);
    });

    test('RemoteCallEndedEvent with no_answer sets human-readable message', () async {
      callBloc.add(const StartOutgoingCallEvent(
        peerId: 88,
        peerName: 'Dave',
        callType: 'voice',
      ));
      await Future.delayed(const Duration(milliseconds: 20));

      callBloc.add(const RemoteCallEndedEvent(reason: 'no_answer'));
      await Future.delayed(const Duration(milliseconds: 20));

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.status, CallStatus.ended);
      expect(session.errorMessage, 'Call was not answered');
      expect(fakeAudio.stoppedRinging, true);
    });

    test('Incoming call signaling event with JSON-encoded map extracts SDP cleanly', () async {
      fakeRepo.emitSignalingEvent('call.offer', {
        'caller_id': 99,
        'caller_name': 'Alice WebRTC',
        'call_type': 'video',
        'sdp': '{"sdp":"v=0\\r\\no=- 12345 2 IN IP4 127.0.0.1\\r\\n","type":"offer"}',
      });
      await Future.delayed(const Duration(milliseconds: 20));

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.callType, 'video');
      expect(session.status, CallStatus.ringing);
    });

    test('Outgoing call failure logs diagnostic error with screen and function_name and emits referenceCode', () async {
      fakeRepo.shouldThrowOnInitiate = true;

      callBloc.add(const StartOutgoingCallEvent(
        peerId: 55,
        peerName: 'Failed Peer',
        callType: 'voice',
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(callBloc.state, isA<CallSessionState>());
      final session = (callBloc.state as CallSessionState).session;
      expect(session.status, CallStatus.error);
      expect(session.referenceCode, 'ERR-MOCK-CALL123');
      expect(fakeApiClient.reportedScreen, 'VoiceCallPage');
      expect(fakeApiClient.reportedFunction, 'initiateCall');
    });
  });
}
