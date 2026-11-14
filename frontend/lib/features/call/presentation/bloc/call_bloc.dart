import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/services/call_audio_service.dart';
import '../../domain/entities/call_entity.dart';
import '../../domain/repositories/call_repository.dart';
import '../../domain/usecases/answer_call_usecase.dart';
import '../../domain/usecases/end_call_usecase.dart';
import '../../domain/usecases/initiate_call_usecase.dart';
import '../../domain/usecases/send_ice_candidate_usecase.dart';
import 'call_event.dart';
import 'call_state.dart';

class CallBloc extends Bloc<CallEvent, CallState> {
  final InitiateCallUseCase _initiateCallUseCase;
  final AnswerCallUseCase _answerCallUseCase;
  final EndCallUseCase _endCallUseCase;
  final SendIceCandidateUseCase _sendIceCandidateUseCase;
  final CallRepository _callRepository;
  final CallAudioService _callAudioService;
  final ApiClient? _apiClient;

  CallRepository get callRepository => _callRepository;
  SendIceCandidateUseCase get sendIceCandidateUseCase => _sendIceCandidateUseCase;
  CallAudioService get callAudioService => _callAudioService;

  StreamSubscription? _signalingSub;
  Timer? _durationTimer;
  Timer? _ringingTimeoutTimer;
  String? _incomingSdpOffer;
  String? _incomingCallId;

  CallBloc({
    required InitiateCallUseCase initiateCallUseCase,
    required AnswerCallUseCase answerCallUseCase,
    required EndCallUseCase endCallUseCase,
    required SendIceCandidateUseCase sendIceCandidateUseCase,
    required CallRepository callRepository,
    CallAudioService? callAudioService,
    ApiClient? apiClient,
  })  : _initiateCallUseCase = initiateCallUseCase,
        _answerCallUseCase = answerCallUseCase,
        _endCallUseCase = endCallUseCase,
        _sendIceCandidateUseCase = sendIceCandidateUseCase,
        _callRepository = callRepository,
        _callAudioService = callAudioService ?? CallAudioService(),
        _apiClient = apiClient,
        super(const CallInitialState()) {
    on<StartOutgoingCallEvent>(_onStartOutgoingCall);
    on<IncomingCallReceivedEvent>(_onIncomingCallReceived);
    on<AcceptCallEvent>(_onAcceptCall);
    on<RejectCallEvent>(_onRejectCall);
    on<RemoteAnswerReceivedEvent>(_onRemoteAnswerReceived);
    on<RemoteIceCandidateReceivedEvent>(_onRemoteIceCandidateReceived);
    on<RemoteCallEndedEvent>(_onRemoteCallEnded);
    on<ToggleMuteEvent>(_onToggleMute);
    on<ToggleSpeakerEvent>(_onToggleSpeaker);
    on<ToggleVideoEvent>(_onToggleVideo);
    on<SwitchCameraEvent>(_onSwitchCamera);
    on<ToggleScreenShareEvent>(_onToggleScreenShare);
    on<HangupCallEvent>(_onHangupCall);
    on<CallTimerTickEvent>(_onCallTimerTick);
    on<ResetCallEvent>(_onResetCall);
    on<CallRingingTimeoutEvent>(_onCallRingingTimeout);

    _listenToSignalingEvents();
  }

  static String _extractSdp(dynamic sdpField) {
    if (sdpField == null) return '';
    if (sdpField is String) {
      final trimmed = sdpField.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            final inner = decoded['sdp'] ?? decoded['description'];
            if (inner != null) return inner.toString().trim();
          }
        } catch (_) {}
      }
      return trimmed;
    }
    if (sdpField is Map) {
      final inner = sdpField['sdp'] ?? sdpField['description'] ?? sdpField['sdp_offer'] ?? sdpField['sdp_answer'];
      if (inner != null) return inner.toString().trim();
    }
    return sdpField.toString().trim();
  }

  void _onResetCall(
    ResetCallEvent event,
    Emitter<CallState> emit,
  ) {
    _stopTimer();
    _stopRingingTimeout();
    _callAudioService.stopRingtone();
    _incomingSdpOffer = null;
    _incomingCallId = null;
    emit(const CallInitialState());
  }

  void _startRingingTimeout() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = Timer(const Duration(seconds: 60), () {
      add(const CallRingingTimeoutEvent());
    });
  }

  void _stopRingingTimeout() {
    _ringingTimeoutTimer?.cancel();
    _ringingTimeoutTimer = null;
  }

  void _listenToSignalingEvents() {
    _signalingSub?.cancel();
    _signalingSub = _callRepository.signalingEventStream.listen((eventMap) {
      final event = eventMap['event'] as String? ?? '';
      final rawData = eventMap['data'];
      final data = rawData is Map ? Map<String, dynamic>.from(rawData) : <String, dynamic>{};

      AppLogger.i('CallBloc signaling event received: $event');

      if (event.endsWith('call.offer') || event.endsWith('CallOfferEvent')) {
        final offerSdp = _extractSdp(data['sdp']).isNotEmpty
            ? _extractSdp(data['sdp'])
            : _extractSdp(data['sdp_offer']);
        final rawCallerId = data['caller_id'];
        final callerId = rawCallerId is int
            ? rawCallerId
            : int.tryParse(rawCallerId?.toString() ?? '') ?? 0;
        add(IncomingCallReceivedEvent(
          callerId: callerId,
          callerName: data['caller_name'] as String? ?? 'Incoming Caller',
          callerEmail: data['caller_email'] as String?,
          sdpOffer: offerSdp,
          callType: data['call_type'] as String? ?? 'voice',
          callId: data['call_id']?.toString(),
        ));
      } else if (event.endsWith('call.answer') || event.endsWith('CallAnswerEvent')) {
        final answerSdp = _extractSdp(data['sdp']).isNotEmpty
            ? _extractSdp(data['sdp'])
            : _extractSdp(data['sdp_answer']);
        add(RemoteAnswerReceivedEvent(
          sdpAnswer: answerSdp,
        ));
      } else if (event.endsWith('call.ice-candidate') || event.endsWith('IceCandidateEvent')) {
        final candidateData = data['candidate'];
        if (candidateData is Map) {
          if (candidateData['batch'] is List) {
            for (final c in candidateData['batch']) {
              if (c is Map) {
                add(RemoteIceCandidateReceivedEvent(
                  candidate: Map<String, dynamic>.from(c),
                ));
              }
            }
          } else {
            add(RemoteIceCandidateReceivedEvent(
              candidate: Map<String, dynamic>.from(candidateData),
            ));
          }
        }
      } else if (event.endsWith('call.ended') || event.endsWith('CallEndedEvent')) {
        add(RemoteCallEndedEvent(
          reason: data['reason'] as String? ?? 'Call ended by peer',
        ));
      }
    });
  }

  Future<void> _onStartOutgoingCall(
    StartOutgoingCallEvent event,
    Emitter<CallState> emit,
  ) async {
    _stopTimer();
    _startRingingTimeout();

    final session = CallSessionEntity(
      peerId: event.peerId,
      peerName: event.peerName,
      peerEmail: event.peerEmail,
      callType: event.callType,
      isCaller: true,
      status: CallStatus.connecting,
    );
    emit(CallSessionState(session: session));

    final startTime = DateTime.now();
    bool isAway = false;

    try {
      await _initiateCallUseCase(
        receiverId: event.peerId,
        callType: event.callType,
      );
    } catch (e) {
      AppLogger.w('Initiate call caught: $e');
      isAway = true;
    }

    // Keep displaying "Calling..." for at least 5 seconds
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final remainingMs = 5000 - elapsedMs;
    if (remainingMs > 0) {
      await Future.delayed(Duration(milliseconds: remainingMs));
    }

    // If recipient is away and call has not connected, sound the buzzer and auto-end
    if (state is CallSessionState) {
      final currentStatus = (state as CallSessionState).session.status;
      if ((currentStatus == CallStatus.connecting || currentStatus == CallStatus.ringing) && isAway) {
        _stopRingingTimeout();
        await _callAudioService.playBuzzer();

        emit(CallSessionState(
          session: (state as CallSessionState).session.copyWith(
            status: CallStatus.error,
            errorMessage: 'User is Away',
          ),
        ));

        // Let buzzer play for 1.5 seconds, then transition to ended
        await Future.delayed(const Duration(milliseconds: 1500));
        if (state is CallSessionState &&
            (state as CallSessionState).session.status != CallStatus.connected) {
          _callAudioService.stopRingtone();
          emit(CallSessionState(
            session: (state as CallSessionState).session.copyWith(
              status: CallStatus.ended,
              errorMessage: 'Call Ended',
            ),
          ));
        }
      }
    }
  }

  Future<void> _onIncomingCallReceived(
    IncomingCallReceivedEvent event,
    Emitter<CallState> emit,
  ) async {
    // If already in an active or ringing call, auto-reject with busy
    if (state is CallSessionState) {
      final currentStatus = (state as CallSessionState).session.status;
      if (currentStatus == CallStatus.connected ||
          currentStatus == CallStatus.connecting ||
          currentStatus == CallStatus.ringing) {
        AppLogger.w('Auto-rejecting incoming call from user ${event.callerId}: local user is busy');
        try {
          await _endCallUseCase(
            targetUserId: event.callerId,
            reason: 'busy',
          );
        } catch (_) {}
        return;
      }
    }

    _stopTimer();
    _startRingingTimeout();
    _callAudioService.startRingtone(isIncoming: true);
    _incomingSdpOffer = event.sdpOffer;
    _incomingCallId = event.callId;

    final session = CallSessionEntity(
      peerId: event.callerId,
      peerName: event.callerName,
      peerEmail: event.callerEmail,
      callType: event.callType,
      isCaller: false,
      status: CallStatus.ringing,
      callId: event.callId,
    );
    emit(CallSessionState(session: session));
  }

  Future<void> _onAcceptCall(
    AcceptCallEvent event,
    Emitter<CallState> emit,
  ) async {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;

    _stopRingingTimeout();
    _callAudioService.stopRingtone();

    emit(CallSessionState(
      session: currentSession.copyWith(status: CallStatus.connecting),
    ));

    try {
      // If SDP offer was not provided over WebSocket or FCM push, fetch it via API
      if ((_incomingSdpOffer == null || _incomingSdpOffer!.isEmpty) &&
          _incomingCallId != null &&
          _apiClient != null) {
        final res = await _apiClient.get('/call/$_incomingCallId');
        if (res.data is Map && res.data['sdp'] != null) {
          _incomingSdpOffer = res.data['sdp'].toString();
        }
      }

      if (_incomingSdpOffer == null || _incomingSdpOffer!.isEmpty) {
        throw Exception('Call offer expired or unavailable.');
      }

      await _answerCallUseCase(
        callerId: currentSession.peerId,
        sdpOffer: _incomingSdpOffer!,
        callType: currentSession.callType,
        callId: _incomingCallId,
      );

      emit(CallSessionState(
        session: currentSession.copyWith(status: CallStatus.connected),
      ));
      _startTimer();
    } catch (e, st) {
      AppLogger.e('Failed to answer call', e);
      String? refCode;
      if (_apiClient != null) {
        refCode = await _apiClient.reportClientError(
          message: e.toString(),
          errorCode: 'CALL_ANSWER_ERROR',
          exceptionClass: e.runtimeType.toString(),
          stackTrace: st.toString(),
          screen: currentSession.callType == 'video' ? 'VideoCallPage' : 'VoiceCallPage',
          functionName: 'answerCall',
          metadata: {'caller_id': currentSession.peerId, 'call_type': currentSession.callType},
        );
      }
      emit(CallSessionState(
        session: currentSession.copyWith(
          status: CallStatus.error,
          errorMessage: e.toString(),
          referenceCode: refCode,
        ),
      ));
    }
  }

  Future<void> _onRejectCall(
    RejectCallEvent event,
    Emitter<CallState> emit,
  ) async {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;

    _stopTimer();
    _stopRingingTimeout();
    _callAudioService.stopRingtone();

    try {
      await _endCallUseCase(
        targetUserId: currentSession.peerId,
        reason: 'rejected',
      );
    } catch (_) {}

    emit(CallSessionState(
      session: currentSession.copyWith(status: CallStatus.rejected),
    ));
  }

  Future<void> _onRemoteAnswerReceived(
    RemoteAnswerReceivedEvent event,
    Emitter<CallState> emit,
  ) async {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;

    _stopRingingTimeout();
    _callAudioService.stopRingtone();

    try {
      await _callRepository.handleRemoteAnswer(sdpAnswer: event.sdpAnswer);
      emit(CallSessionState(
        session: currentSession.copyWith(status: CallStatus.connected),
      ));
      _startTimer();
    } catch (e, st) {
      AppLogger.e('Failed to handle remote answer', e);
      String? refCode;
      if (_apiClient != null) {
        refCode = await _apiClient.reportClientError(
          message: e.toString(),
          errorCode: 'WEBRTC_REMOTE_ANSWER_ERROR',
          exceptionClass: e.runtimeType.toString(),
          stackTrace: st.toString(),
          screen: currentSession.callType == 'video' ? 'VideoCallPage' : 'VoiceCallPage',
          functionName: 'handleRemoteAnswer',
        );
      }
      emit(CallSessionState(
        session: currentSession.copyWith(
          status: CallStatus.error,
          errorMessage: e.toString(),
          referenceCode: refCode,
        ),
      ));
    }
  }

  Future<void> _onRemoteIceCandidateReceived(
    RemoteIceCandidateReceivedEvent event,
    Emitter<CallState> emit,
  ) async {
    try {
      await _callRepository.handleRemoteIceCandidate(
        candidate: event.candidate,
      );
    } catch (e) {
      AppLogger.w('Failed to add remote candidate: $e');
    }
  }

  Future<void> _onRemoteCallEnded(
    RemoteCallEndedEvent event,
    Emitter<CallState> emit,
  ) async {
    _stopTimer();
    _stopRingingTimeout();
    _callAudioService.stopRingtone();
    await _callRepository.disposeCall();

    if (state is CallSessionState) {
      final currentSession = (state as CallSessionState).session;
      final displayMessage = event.reason == 'no_answer'
          ? 'Call was not answered'
          : (event.reason == 'missed'
              ? 'Missed call'
              : event.reason);

      emit(CallSessionState(
        session: currentSession.copyWith(
          status: CallStatus.ended,
          errorMessage: displayMessage,
        ),
      ));
    }
  }

  Future<void> _onCallRingingTimeout(
    CallRingingTimeoutEvent event,
    Emitter<CallState> emit,
  ) async {
    _stopRingingTimeout();
    await _callAudioService.stopRingtone();

    if (state is CallSessionState) {
      final currentSession = (state as CallSessionState).session;
      if (currentSession.status == CallStatus.ringing) {
        try {
          await _endCallUseCase(
            targetUserId: currentSession.peerId,
            reason: currentSession.isCaller ? 'no_answer' : 'missed',
          );
        } catch (_) {}
        await _callRepository.disposeCall();

        emit(CallSessionState(
          session: currentSession.copyWith(
            status: CallStatus.ended,
            errorMessage: currentSession.isCaller
                ? 'No answer (Call timed out after 60s)'
                : 'Missed call (Timed out)',
          ),
        ));
      }
    }
  }

  void _onToggleMute(
    ToggleMuteEvent event,
    Emitter<CallState> emit,
  ) {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;
    final isMuted = _callRepository.toggleMute();
    emit(CallSessionState(session: currentSession.copyWith(isMuted: isMuted)));
  }

  void _onToggleSpeaker(
    ToggleSpeakerEvent event,
    Emitter<CallState> emit,
  ) {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;
    final isSpeaker = _callRepository.toggleSpeaker();
    emit(CallSessionState(
        session: currentSession.copyWith(isSpeakerOn: isSpeaker)));
  }

  void _onToggleVideo(
    ToggleVideoEvent event,
    Emitter<CallState> emit,
  ) {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;
    final isVideo = _callRepository.toggleVideo();
    emit(CallSessionState(
      session: currentSession.copyWith(isVideoEnabled: isVideo),
    ));
  }

  Future<void> _onSwitchCamera(
    SwitchCameraEvent event,
    Emitter<CallState> emit,
  ) async {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;
    await _callRepository.switchCamera();
    emit(CallSessionState(
      session: currentSession.copyWith(
        isFrontCamera: !currentSession.isFrontCamera,
      ),
    ));
  }

  Future<void> _onToggleScreenShare(
    ToggleScreenShareEvent event,
    Emitter<CallState> emit,
  ) async {
    if (state is! CallSessionState) return;
    final currentSession = (state as CallSessionState).session;

    if (currentSession.isScreenSharing) {
      await _callRepository.stopScreenShare();
      emit(CallSessionState(
        session: currentSession.copyWith(isScreenSharing: false),
      ));
    } else {
      final success = await _callRepository.startScreenShare();
      emit(CallSessionState(
        session: currentSession.copyWith(isScreenSharing: success),
      ));
    }
  }

  Future<void> _onHangupCall(
    HangupCallEvent event,
    Emitter<CallState> emit,
  ) async {
    _stopTimer();
    _stopRingingTimeout();
    _callAudioService.stopRingtone();
    if (state is CallSessionState) {
      final currentSession = (state as CallSessionState).session;
      try {
        await _endCallUseCase(
          targetUserId: currentSession.peerId,
          reason: 'hangup',
        );
      } catch (_) {}

      emit(CallSessionState(
        session: currentSession.copyWith(status: CallStatus.ended),
      ));
    }
  }

  void _onCallTimerTick(
    CallTimerTickEvent event,
    Emitter<CallState> emit,
  ) {
    if (state is CallSessionState) {
      final currentSession = (state as CallSessionState).session;
      if (currentSession.status == CallStatus.connected) {
        emit(CallSessionState(
          session: currentSession.copyWith(
            durationSeconds: currentSession.durationSeconds + 1,
          ),
        ));
      }
    }
  }

  void _startTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(const CallTimerTickEvent());
    });
  }

  void _stopTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  @override
  Future<void> close() {
    _stopTimer();
    _stopRingingTimeout();
    _callAudioService.dispose();
    _signalingSub?.cancel();
    _callRepository.disposeCall();
    return super.close();
  }
}
