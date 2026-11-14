import 'dart:async';
import '../../data/services/webrtc_service.dart';


abstract class CallRepository {
  /// Stream of incoming signaling events (call.offer, call.answer, call.ice-candidate, call.ended)
  Stream<Map<String, dynamic>> get signalingEventStream;

  /// WebRTC service instance providing audio/video renderers
  IWebRtcService get webRtcService;

  /// Initiate an outgoing WebRTC call to receiver
  Future<void> initiateCall({
    required int receiverId,
    required String callType,
  });

  /// Answer an incoming WebRTC call from caller with local SDP answer
  Future<void> answerCall({
    required int callerId,
    required String sdpOffer,
    String callType = 'voice',
    String? callId,
  });

  /// Set remote SDP answer when caller receives answer from callee
  Future<void> handleRemoteAnswer({required String sdpAnswer});

  /// Add incoming ICE candidate from peer
  Future<void> handleRemoteIceCandidate({required Map<String, dynamic> candidate});

  /// Send local ICE candidate to peer
  Future<void> sendIceCandidate({
    required int targetUserId,
    required Map<String, dynamic> candidate,
  });

  /// End or reject the call
  Future<void> endCall({
    required int targetUserId,
    String? reason,
  });

  /// Toggle microphone mute
  bool toggleMute();

  /// Toggle speakerphone vs earpiece
  bool toggleSpeaker();

  /// Toggle local camera video stream (mute/unmute video feed)
  bool toggleVideo();

  /// Switch between front and back cameras
  Future<void> switchCamera();

  /// Whether screen sharing is currently active
  bool get isScreenSharing;

  /// Start sharing device screen via WebRTC
  Future<bool> startScreenShare();

  /// Stop sharing screen and revert to camera video track
  Future<void> stopScreenShare();

  /// Free all WebRTC resources, audio tracks, and peer connection
  Future<void> disposeCall();
}
