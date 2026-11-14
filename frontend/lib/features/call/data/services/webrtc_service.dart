import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/utils/app_logger.dart';

abstract class IWebRtcService {
  Stream<RTCPeerConnectionState> get connectionStateStream;
  Stream<RTCIceCandidate> get iceCandidateStream;
  Stream<MediaStream> get remoteStreamStream;

  RTCVideoRenderer get localRenderer;
  RTCVideoRenderer get remoteRenderer;

  bool get isMuted;
  bool get isSpeakerOn;
  bool get isVideoEnabled;
  bool get isFrontCamera;
  bool get isScreenSharing;

  Future<void> initializeRenderers();
  Future<String> createOffer({bool isAudioOnly = true});
  Future<String> createAnswer(String remoteOfferSdp, {bool isAudioOnly = true});
  Future<void> setRemoteAnswer(String remoteAnswerSdp);
  Future<void> addCandidate(Map<String, dynamic> candidateMap);

  bool toggleMute();
  bool toggleSpeaker();
  bool toggleVideo();
  Future<void> switchCamera();
  Future<bool> startScreenShare();
  Future<void> stopScreenShare();

  Future<void> dispose();
}

class WebRtcServiceImpl implements IWebRtcService {
  static const _mediaProjectionChannel =
      MethodChannel('com.chatapp.app/media_projection');

  final AppConfig _appConfig;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _screenStream;

  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  bool _isRenderersInitialized = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = true;
  bool _isFrontCamera = true;
  bool _isScreenSharing = false;

  final _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  final _iceCandidateController = StreamController<RTCIceCandidate>.broadcast();
  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  WebRtcServiceImpl({AppConfig? appConfig})
      : _appConfig = appConfig ?? sl<AppConfig>();

  @override
  Stream<RTCPeerConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  @override
  Stream<RTCIceCandidate> get iceCandidateStream =>
      _iceCandidateController.stream;

  @override
  Stream<MediaStream> get remoteStreamStream => _remoteStreamController.stream;

  @override
  RTCVideoRenderer get localRenderer => _localRenderer;

  @override
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  @override
  bool get isMuted => _isMuted;

  @override
  bool get isSpeakerOn => _isSpeakerOn;

  @override
  bool get isVideoEnabled => _isVideoEnabled;

  @override
  bool get isFrontCamera => _isFrontCamera;

  @override
  bool get isScreenSharing => _isScreenSharing;

  @override
  Future<void> initializeRenderers() async {
    if (!_isRenderersInitialized) {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      _isRenderersInitialized = true;
      AppLogger.i('WebRTC local and remote video renderers initialized');
    }
  }

  Future<void> _initPeerConnection(bool isAudioOnly) async {
    if (_peerConnection != null) {
      await dispose();
    }

    // Request hardware permissions dynamically before accessing media devices
    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      AppLogger.w('Microphone permission not granted for call');
      throw Exception('Microphone permission is required for calling.');
    }

    if (!isAudioOnly) {
      final camPermission = await Permission.camera.request();
      if (!camPermission.isGranted) {
        AppLogger.w('Camera permission not granted for video call');
        throw Exception('Camera permission is required for video calling.');
      }
    }

    await initializeRenderers();

    final iceConfiguration = _appConfig.iceServersConfiguration;
    AppLogger.i(
        'Initializing WebRTC RTCPeerConnection with STUN/TURN servers: ${iceConfiguration['iceServers']} (audioOnly: $isAudioOnly)');
    _peerConnection = await createPeerConnection(iceConfiguration);

    // Audio & Camera media constraints (clean standard constraints preventing Camera2 HAL crash on MIUI/HyperOS)
    final mediaConstraints = {
      'audio': true,
      'video': isAudioOnly
          ? false
          : {
              'facingMode': 'user',
            },
    };

    try {
      _localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
    } catch (e) {
      if (!isAudioOnly) {
        AppLogger.w('getUserMedia failed with preferred video constraints, falling back: $e');
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': {'facingMode': 'user'},
        });
      } else {
        rethrow;
      }
    }

    // Attach local stream to local video renderer
    _localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        _iceCandidateController.add(candidate);
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      AppLogger.i('WebRTC connection state changed: $state');
      _connectionStateController.add(state);
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      AppLogger.i('WebRTC remote track received: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      } else {
        _remoteStream ??= await createLocalMediaStream('remote_stream');
        _remoteStream!.addTrack(event.track);
      }
      _remoteRenderer.srcObject = _remoteStream;
      _remoteStreamController.add(_remoteStream!);
    };
  }

  String _sanitizeSdp(dynamic raw) {
    if (raw == null) return '';
    String s = raw.toString().trim();
    if (s.startsWith('{') && s.endsWith('}')) {
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          final extracted = decoded['sdp'] ?? decoded['description'];
          if (extracted != null) {
            s = extracted.toString().trim();
          }
        }
      } catch (_) {}
    }
    // Normalize newlines to \r\n and ensure trailing \r\n (RFC 4566 requirement)
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\n', '\r\n');
    if (!s.endsWith('\r\n')) {
      s = '$s\r\n';
    }
    return s;
  }

  @override
  Future<String> createOffer({bool isAudioOnly = true}) async {
    await _initPeerConnection(isAudioOnly);

    final offerConstraints = {
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isAudioOnly ? 0 : 1,
    };

    final offer = await _peerConnection!.createOffer(offerConstraints);
    await _peerConnection!.setLocalDescription(offer);
    AppLogger.i('WebRTC local offer created (audioOnly: $isAudioOnly)');
    return _sanitizeSdp(offer.sdp);
  }

  @override
  Future<String> createAnswer(String remoteOfferSdp,
      {bool isAudioOnly = true}) async {
    final cleanSdp = _sanitizeSdp(remoteOfferSdp);
    if (cleanSdp.trim().isEmpty) {
      AppLogger.e('WebRTC createAnswer failed: remoteOfferSdp is empty');
      throw ArgumentError('Remote offer SDP cannot be empty');
    }

    await _initPeerConnection(isAudioOnly);

    final remoteDescription = RTCSessionDescription(cleanSdp, 'offer');
    await _peerConnection!.setRemoteDescription(remoteDescription);
    await _drainPendingRemoteCandidates();

    final answerConstraints = {
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': isAudioOnly ? 0 : 1,
    };

    final answer = await _peerConnection!.createAnswer(answerConstraints);
    await _peerConnection!.setLocalDescription(answer);
    AppLogger.i('WebRTC local answer created (audioOnly: $isAudioOnly)');
    return _sanitizeSdp(answer.sdp);
  }

  @override
  Future<void> setRemoteAnswer(String remoteAnswerSdp) async {
    if (_peerConnection == null) return;
    final cleanSdp = _sanitizeSdp(remoteAnswerSdp);
    if (cleanSdp.trim().isEmpty) {
      AppLogger.e('WebRTC setRemoteAnswer failed: remoteAnswerSdp is empty');
      throw ArgumentError('Remote answer SDP cannot be empty');
    }
    final remoteDescription = RTCSessionDescription(cleanSdp, 'answer');
    await _peerConnection!.setRemoteDescription(remoteDescription);
    await _drainPendingRemoteCandidates();
    AppLogger.i('WebRTC remote answer set successfully');
  }

  Future<void> _drainPendingRemoteCandidates() async {
    if (_peerConnection == null) return;
    for (final candidate in _pendingRemoteCandidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
        AppLogger.d('WebRTC remote ICE candidate drained: ${candidate.sdpMid}');
      } catch (e) {
        AppLogger.w('Failed to drain remote ICE candidate: $e');
      }
    }
    _pendingRemoteCandidates.clear();
  }

  @override
  Future<void> addCandidate(Map<String, dynamic> candidateMap) async {
    final candidateStr = candidateMap['candidate'] as String?;
    final sdpMid = candidateMap['sdpMid'] as String?;
    final sdpMLineIndex = candidateMap['sdpMLineIndex'] is int
        ? candidateMap['sdpMLineIndex'] as int
        : (candidateMap['sdpMLineIndex'] != null
            ? int.tryParse(candidateMap['sdpMLineIndex'].toString())
            : 0);

    if (candidateStr != null && candidateStr.isNotEmpty) {
      final candidate = RTCIceCandidate(candidateStr, sdpMid, sdpMLineIndex);
      if (_peerConnection == null) {
        _pendingRemoteCandidates.add(candidate);
        return;
      }
      final remoteDesc = await _peerConnection!.getRemoteDescription();
      if (remoteDesc == null) {
        _pendingRemoteCandidates.add(candidate);
        return;
      }

      try {
        await _peerConnection!.addCandidate(candidate);
        AppLogger.d('WebRTC remote ICE candidate added: $sdpMid');
      } catch (e) {
        AppLogger.w('Failed to add remote ICE candidate: $e');
      }
    }
  }

  @override
  bool toggleMute() {
    _isMuted = !_isMuted;
    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
    AppLogger.i('WebRTC audio mute toggled: $_isMuted');
    return _isMuted;
  }

  @override
  bool toggleSpeaker() {
    _isSpeakerOn = !_isSpeakerOn;
    try {
      Helper.setSpeakerphoneOn(_isSpeakerOn);
      AppLogger.i('WebRTC speakerphone set: $_isSpeakerOn');
    } catch (e) {
      AppLogger.w('Failed to set speakerphone: $e');
    }
    return _isSpeakerOn;
  }

  @override
  bool toggleVideo() {
    _isVideoEnabled = !_isVideoEnabled;
    if (_localStream != null) {
      for (final track in _localStream!.getVideoTracks()) {
        track.enabled = _isVideoEnabled;
      }
    }
    AppLogger.i('WebRTC local video toggled: $_isVideoEnabled');
    return _isVideoEnabled;
  }

  @override
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        await Helper.switchCamera(videoTracks.first);
        _isFrontCamera = !_isFrontCamera;
        AppLogger.i('WebRTC camera switched. isFrontCamera: $_isFrontCamera');
      }
    }
  }

  @override
  Future<bool> startScreenShare() async {
    if (_peerConnection == null || _isScreenSharing) return false;
    try {
      if (Platform.isAndroid) {
        try {
          await _mediaProjectionChannel.invokeMethod('startService');
        } catch (e) {
          AppLogger.w('Failed to start media projection foreground service: $e');
        }
      }

      AppLogger.i('Requesting display media for WebRTC screen share');
      _screenStream = await navigator.mediaDevices.getDisplayMedia({
        'video': true,
        'audio': false,
      });

      if (_screenStream == null || _screenStream!.getVideoTracks().isEmpty) {
        AppLogger.w('No video track found in screen stream');
        return false;
      }

      final screenTrack = _screenStream!.getVideoTracks().first;

      screenTrack.onEnded = () {
        AppLogger.i('Screen share track ended by system');
        stopScreenShare();
      };

      final senders = await _peerConnection!.getSenders();
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await sender.replaceTrack(screenTrack);
          break;
        }
      }

      _localRenderer.srcObject = _screenStream;
      _isScreenSharing = true;
      AppLogger.i('Screen sharing successfully started');
      return true;
    } catch (e) {
      AppLogger.e('Failed to start screen share', e);
      await stopScreenShare();
      return false;
    }
  }

  @override
  Future<void> stopScreenShare() async {
    if (Platform.isAndroid) {
      try {
        await _mediaProjectionChannel.invokeMethod('stopService');
      } catch (e) {
        AppLogger.w('Failed to stop media projection foreground service: $e');
      }
    }

    if (!_isScreenSharing) return;
    try {
      AppLogger.i('Stopping WebRTC screen share');
      if (_screenStream != null) {
        for (final track in _screenStream!.getTracks()) {
          track.stop();
        }
        await _screenStream!.dispose();
        _screenStream = null;
      }

      if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
        final cameraTrack = _localStream!.getVideoTracks().first;
        if (_peerConnection != null) {
          final senders = await _peerConnection!.getSenders();
          for (final sender in senders) {
            if (sender.track == null || sender.track?.kind == 'video') {
              await sender.replaceTrack(cameraTrack);
              break;
            }
          }
        }
        _localRenderer.srcObject = _localStream;
      }

      _isScreenSharing = false;
      AppLogger.i('Screen sharing reverted to camera video');
    } catch (e) {
      AppLogger.e('Error stopping screen share', e);
      _isScreenSharing = false;
    }
  }

  @override
  Future<void> dispose() async {
    AppLogger.i('Disposing WebRTC resources');
    try {
      if (Platform.isAndroid) {
        try {
          await _mediaProjectionChannel.invokeMethod('stopService');
        } catch (_) {}
      }

      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;

      if (_screenStream != null) {
        for (final track in _screenStream!.getTracks()) {
          track.stop();
        }
        await _screenStream!.dispose();
        _screenStream = null;
      }

      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }

      if (_remoteStream != null) {
        for (final track in _remoteStream!.getTracks()) {
          track.stop();
        }
        await _remoteStream!.dispose();
        _remoteStream = null;
      }

      if (_peerConnection != null) {
        await _peerConnection!.close();
        await _peerConnection!.dispose();
        _peerConnection = null;
      }
      _pendingRemoteCandidates.clear();
    } catch (e) {
      AppLogger.e('Error disposing WebRTC connection', e);
    }

    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = true;
    _isFrontCamera = true;
    _isScreenSharing = false;
  }
}
