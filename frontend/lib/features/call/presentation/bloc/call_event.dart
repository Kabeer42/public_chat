import 'package:equatable/equatable.dart';

abstract class CallEvent extends Equatable {
  const CallEvent();

  @override
  List<Object?> get props => [];
}

class StartOutgoingCallEvent extends CallEvent {
  final int peerId;
  final String peerName;
  final String? peerEmail;
  final String callType; // 'voice' or 'video'

  const StartOutgoingCallEvent({
    required this.peerId,
    required this.peerName,
    this.peerEmail,
    required this.callType,
  });

  @override
  List<Object?> get props => [peerId, peerName, peerEmail, callType];
}

class IncomingCallReceivedEvent extends CallEvent {
  final int callerId;
  final String callerName;
  final String? callerEmail;
  final String sdpOffer;
  final String callType;
  final String? callId;

  const IncomingCallReceivedEvent({
    required this.callerId,
    required this.callerName,
    this.callerEmail,
    required this.sdpOffer,
    required this.callType,
    this.callId,
  });

  @override
  List<Object?> get props => [callerId, callerName, callerEmail, sdpOffer, callType, callId];
}

class AcceptCallEvent extends CallEvent {
  const AcceptCallEvent();
}

class RejectCallEvent extends CallEvent {
  const RejectCallEvent();
}

class RemoteAnswerReceivedEvent extends CallEvent {
  final String sdpAnswer;

  const RemoteAnswerReceivedEvent({required this.sdpAnswer});

  @override
  List<Object?> get props => [sdpAnswer];
}

class RemoteIceCandidateReceivedEvent extends CallEvent {
  final Map<String, dynamic> candidate;

  const RemoteIceCandidateReceivedEvent({required this.candidate});

  @override
  List<Object?> get props => [candidate];
}

class RemoteCallEndedEvent extends CallEvent {
  final String reason;

  const RemoteCallEndedEvent({required this.reason});

  @override
  List<Object?> get props => [reason];
}

class ToggleMuteEvent extends CallEvent {
  const ToggleMuteEvent();
}

class ToggleSpeakerEvent extends CallEvent {
  const ToggleSpeakerEvent();
}

class ToggleVideoEvent extends CallEvent {
  const ToggleVideoEvent();
}

class SwitchCameraEvent extends CallEvent {
  const SwitchCameraEvent();
}

class ToggleScreenShareEvent extends CallEvent {
  const ToggleScreenShareEvent();
}

class HangupCallEvent extends CallEvent {
  const HangupCallEvent();
}

class CallTimerTickEvent extends CallEvent {
  const CallTimerTickEvent();
}

class ResetCallEvent extends CallEvent {
  const ResetCallEvent();
}

class CallRingingTimeoutEvent extends CallEvent {
  const CallRingingTimeoutEvent();
}
