import 'package:equatable/equatable.dart';

enum CallStatus {
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

class CallSessionEntity extends Equatable {
  final int peerId;
  final String peerName;
  final String? peerEmail;
  final String callType; // 'voice' or 'video'
  final bool isCaller;
  final CallStatus status;
  final int durationSeconds;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isFrontCamera;
  final bool isScreenSharing;
  final String? errorMessage;
  final String? referenceCode;
  final String? callId;

  const CallSessionEntity({
    required this.peerId,
    required this.peerName,
    this.peerEmail,
    required this.callType,
    required this.isCaller,
    this.status = CallStatus.idle,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.isFrontCamera = true,
    this.isScreenSharing = false,
    this.errorMessage,
    this.referenceCode,
    this.callId,
  });

  CallSessionEntity copyWith({
    int? peerId,
    String? peerName,
    String? peerEmail,
    String? callType,
    bool? isCaller,
    CallStatus? status,
    int? durationSeconds,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isFrontCamera,
    bool? isScreenSharing,
    String? errorMessage,
    String? referenceCode,
    String? callId,
  }) {
    return CallSessionEntity(
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
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      errorMessage: errorMessage ?? this.errorMessage,
      referenceCode: referenceCode ?? this.referenceCode,
      callId: callId ?? this.callId,
    );
  }

  @override
  List<Object?> get props => [
        peerId,
        peerName,
        peerEmail,
        callType,
        isCaller,
        status,
        durationSeconds,
        isMuted,
        isSpeakerOn,
        isVideoEnabled,
        isFrontCamera,
        isScreenSharing,
        errorMessage,
        referenceCode,
        callId,
      ];
}
