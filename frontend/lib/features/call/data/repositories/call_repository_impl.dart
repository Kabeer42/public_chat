import 'dart:async';
import '../../../../core/network/websocket_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/repositories/call_repository.dart';
import '../datasources/call_signaling_remote_datasource.dart';
import '../services/webrtc_service.dart';

class CallRepositoryImpl implements CallRepository {
  final CallSignalingRemoteDataSource _remoteDataSource;
  final IWebRtcService _webRtcService;
  final WebSocketService _webSocketService;

  StreamSubscription? _localIceCandidateSub;
  Timer? _iceCandidateBatchTimer;
  final List<Map<String, dynamic>> _pendingIceCandidates = [];
  int? _activePeerId;
  String? _activeCallId;

  CallRepositoryImpl({
    required CallSignalingRemoteDataSource remoteDataSource,
    required IWebRtcService webRtcService,
    required WebSocketService webSocketService,
  })  : _remoteDataSource = remoteDataSource,
        _webRtcService = webRtcService,
        _webSocketService = webSocketService {
    _listenToLocalIceCandidates();
  }

  @override
  IWebRtcService get webRtcService => _webRtcService;

  void _listenToLocalIceCandidates() {
    _localIceCandidateSub?.cancel();
    _localIceCandidateSub = _webRtcService.iceCandidateStream.listen((candidate) {
      if (_activePeerId != null && candidate.candidate != null) {
        _pendingIceCandidates.add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });

        if (_pendingIceCandidates.length >= 6) {
          _flushCandidates();
        } else {
          _iceCandidateBatchTimer ??= Timer(const Duration(milliseconds: 150), () {
            _flushCandidates();
          });
        }
      }
    });
  }

  void _flushCandidates() {
    _iceCandidateBatchTimer?.cancel();
    _iceCandidateBatchTimer = null;
    if (_pendingIceCandidates.isEmpty || _activePeerId == null) return;

    final batch = List<Map<String, dynamic>>.from(_pendingIceCandidates);
    _pendingIceCandidates.clear();
    final targetId = _activePeerId!;
    final callId = _activeCallId;

    _remoteDataSource
        .sendIceCandidate(
          targetUserId: targetId,
          candidate: batch.length == 1 ? batch.first : {'batch': batch},
          callId: callId,
        )
        .catchError((e) {
      AppLogger.w('Failed to send ICE candidates to $targetId: $e');
    });
  }

  @override
  Stream<Map<String, dynamic>> get signalingEventStream {
    return _webSocketService.eventStream.where((eventMap) {
      final event = eventMap['event'] as String? ?? '';
      return event.endsWith('call.offer') ||
          event.endsWith('CallOfferEvent') ||
          event.endsWith('call.answer') ||
          event.endsWith('CallAnswerEvent') ||
          event.endsWith('call.ice-candidate') ||
          event.endsWith('IceCandidateEvent') ||
          event.endsWith('call.ended') ||
          event.endsWith('CallEndedEvent');
    });
  }

  @override
  Future<void> initiateCall({
    required int receiverId,
    required String callType,
  }) async {
    _activePeerId = receiverId;
    AppLogger.i('Initiating $callType call to user $receiverId');

    // 1. Create local WebRTC SDP offer
    final isAudioOnly = callType == 'voice';
    final sdpOffer = await _webRtcService.createOffer(isAudioOnly: isAudioOnly);

    // 2. Dispatch offer to Laravel backend signaling API
    final response = await _remoteDataSource.sendOffer(
      receiverId: receiverId,
      callType: callType,
      sdpOffer: sdpOffer,
    );

    if (response['status'] == 'offline') {
      throw Exception(response['message'] ?? 'Recipient is currently offline.');
    }
    if (response['status'] == 'busy') {
      throw Exception(response['message'] ?? 'Recipient is currently on another call.');
    }

    _activeCallId = response['call_id'] as String?;
  }

  @override
  Future<void> answerCall({
    required int callerId,
    required String sdpOffer,
    String callType = 'voice',
    String? callId,
  }) async {
    _activePeerId = callerId;
    if (callId != null) {
      _activeCallId = callId;
    }
    AppLogger.i('Answering $callType call from user $callerId (callId: $_activeCallId)');

    // 1. Create local WebRTC SDP answer from the received offer
    final isAudioOnly = callType == 'voice';
    final sdpAnswer = await _webRtcService.createAnswer(sdpOffer, isAudioOnly: isAudioOnly);

    // 2. Dispatch answer to Laravel backend signaling API
    final response = await _remoteDataSource.sendAnswer(
      callerId: callerId,
      sdpAnswer: sdpAnswer,
      callId: _activeCallId,
    );
    if (response['call_id'] != null) {
      _activeCallId = response['call_id'] as String?;
    }
  }

  @override
  Future<void> handleRemoteAnswer({required String sdpAnswer}) async {
    AppLogger.i('Applying remote SDP answer');
    await _webRtcService.setRemoteAnswer(sdpAnswer);
  }

  @override
  Future<void> handleRemoteIceCandidate({
    required Map<String, dynamic> candidate,
  }) async {
    AppLogger.d('Applying incoming remote ICE candidate');
    await _webRtcService.addCandidate(candidate);
  }

  @override
  Future<void> sendIceCandidate({
    required int targetUserId,
    required Map<String, dynamic> candidate,
  }) async {
    await _remoteDataSource.sendIceCandidate(
      targetUserId: targetUserId,
      candidate: candidate,
      callId: _activeCallId,
    );
  }

  @override
  Future<void> endCall({
    required int targetUserId,
    String? reason,
  }) async {
    AppLogger.i('Ending call with target user $targetUserId (reason: $reason)');
    try {
      await _remoteDataSource.endCall(
        targetUserId: targetUserId,
        reason: reason,
        callId: _activeCallId,
      );
    } catch (e) {
      AppLogger.w('Failed to notify backend of call end: $e');
    } finally {
      await disposeCall();
    }
  }

  @override
  bool toggleMute() {
    return _webRtcService.toggleMute();
  }

  @override
  bool toggleSpeaker() {
    return _webRtcService.toggleSpeaker();
  }

  @override
  bool toggleVideo() {
    return _webRtcService.toggleVideo();
  }

  @override
  Future<void> switchCamera() {
    return _webRtcService.switchCamera();
  }

  @override
  bool get isScreenSharing => _webRtcService.isScreenSharing;

  @override
  Future<bool> startScreenShare() {
    return _webRtcService.startScreenShare();
  }

  @override
  Future<void> stopScreenShare() {
    return _webRtcService.stopScreenShare();
  }

  @override
  Future<void> disposeCall() async {
    _iceCandidateBatchTimer?.cancel();
    _iceCandidateBatchTimer = null;
    _pendingIceCandidates.clear();
    _activePeerId = null;
    _activeCallId = null;
    await _webRtcService.dispose();
  }
}
