import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/entities/call_entity.dart';
import '../bloc/call_bloc.dart';
import '../bloc/call_event.dart';
import '../bloc/call_state.dart';
import '../widgets/call_control_button.dart';

class VideoCallPage extends StatefulWidget {
  final UserEntity peerUser;
  final bool isOutgoing;

  const VideoCallPage({
    super.key,
    required this.peerUser,
    this.isOutgoing = true,
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  @override
  void initState() {
    super.initState();
    if (widget.isOutgoing) {
      context.read<CallBloc>().add(StartOutgoingCallEvent(
            peerId: widget.peerUser.id,
            peerName: widget.peerUser.name,
            peerEmail: widget.peerUser.email,
            callType: 'video',
          ));
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final callBloc = context.read<CallBloc>();
    final webRtcService = callBloc.callRepository.webRtcService;

    return BlocConsumer<CallBloc, CallState>(
      listener: (context, state) {
        if (state is CallSessionState) {
          if (state.session.status == CallStatus.ended ||
              state.session.status == CallStatus.rejected) {
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            });
          }
        }
      },
      builder: (context, state) {
        CallSessionEntity session = CallSessionEntity(
          peerId: widget.peerUser.id,
          peerName: widget.peerUser.name,
          peerEmail: widget.peerUser.email,
          callType: 'video',
          isCaller: widget.isOutgoing,
          status: widget.isOutgoing ? CallStatus.connecting : CallStatus.idle,
        );

        if (state is CallSessionState) {
          session = state.session;
        }

        final isConnected = session.status == CallStatus.connected;
        final isIncomingRinging =
            session.status == CallStatus.ringing && !session.isCaller;

        String statusLabel = 'Calling...';
        if (session.status == CallStatus.ringing) {
          statusLabel = session.isCaller ? 'Calling...' : 'Incoming Video Call...';
        } else if (session.status == CallStatus.connecting) {
          statusLabel = 'Calling...';
        } else if (session.status == CallStatus.connected) {
          statusLabel = _formatDuration(session.durationSeconds);
        } else if (session.status == CallStatus.ended) {
          statusLabel = session.errorMessage ?? 'Call Ended';
        } else if (session.status == CallStatus.rejected) {
          statusLabel = 'Call Declined';
        } else if (session.status == CallStatus.error) {
          final err = session.errorMessage ?? '';
          if (err.toLowerCase().contains('away') || err.toLowerCase().contains('offline')) {
            statusLabel = 'User is Away';
          } else {
            statusLabel = 'User Unavailable';
          }
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // 1. Fullscreen Remote Video or Placeholder
              Positioned.fill(
                child: isConnected
                    ? RTCVideoView(
                        webRtcService.remoteRenderer,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      )
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF0F172A),
                              Color(0xFF1E293B),
                              Color(0xFF0B1120),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 130,
                                height: 130,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primaryDark,
                                      AppColors.primary,
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppColors.primary.withOpacity(0.4),
                                      blurRadius: 24,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    session.peerName.isNotEmpty
                                        ? session.peerName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 52,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                session.peerName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                statusLabel,
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // Screen Sharing Active Banner
              if (session.isScreenSharing)
                Positioned(
                  top: 36,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.screen_share, color: Colors.white, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'You are sharing your screen',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 2. Floating Local Camera Preview (Picture-in-Picture)
              if (session.status != CallStatus.ended &&
                  session.status != CallStatus.rejected)
                Positioned(
                  top: 90,
                  right: 18,
                  child: Container(
                    width: 110,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: session.isVideoEnabled
                        ? RTCVideoView(
                            webRtcService.localRenderer,
                            mirror: session.isFrontCamera && !session.isScreenSharing,
                            objectFit:
                                RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_off,
                                  color: Colors.white54,
                                  size: 28,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Camera Off',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),

              // 3. Top Status Header & Encryption Indicator
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              session.peerName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.lock,
                                    size: 11, color: AppColors.accent),
                                const SizedBox(width: 4),
                                Text(
                                  isConnected
                                      ? statusLabel
                                      : 'DTLS-SRTP P2P Encrypted',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (isConnected)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.accent.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.accent,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 4. Bottom Controls Floating Bar
              Positioned(
                bottom: 30,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: isIncomingRinging
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Decline Button
                            CallControlButton(
                              icon: Icons.call_end,
                              label: 'Decline',
                              backgroundColor: AppColors.accentRose,
                              onTap: () {
                                context
                                    .read<CallBloc>()
                                    .add(const RejectCallEvent());
                              },
                            ),
                            // Accept Button
                            CallControlButton(
                              icon: Icons.videocam,
                              label: 'Accept',
                              backgroundColor: AppColors.accent,
                              onTap: () {
                                context
                                    .read<CallBloc>()
                                    .add(const AcceptCallEvent());
                              },
                            ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Switch Camera (Front/Back)
                              CallControlButton(
                                icon: Icons.flip_camera_ios_rounded,
                                label: 'Flip',
                                backgroundColor:
                                    Colors.white.withOpacity(0.12),
                                onTap: () {
                                  context
                                      .read<CallBloc>()
                                      .add(const SwitchCameraEvent());
                                },
                              ),

                              // Toggle Camera (Video On/Off)
                              CallControlButton(
                                icon: session.isVideoEnabled
                                    ? Icons.videocam_rounded
                                    : Icons.videocam_off_rounded,
                                label: session.isVideoEnabled
                                    ? 'Camera'
                                    : 'Cam Off',
                                backgroundColor: session.isVideoEnabled
                                    ? Colors.white.withOpacity(0.12)
                                    : Colors.white.withOpacity(0.25),
                                iconColor: session.isVideoEnabled
                                    ? Colors.white
                                    : AppColors.accentRose,
                                onTap: () {
                                  context
                                      .read<CallBloc>()
                                      .add(const ToggleVideoEvent());
                                },
                              ),

                              // Audio Mute Toggle
                              CallControlButton(
                                icon: session.isMuted
                                    ? Icons.mic_off
                                    : Icons.mic_none_rounded,
                                label: session.isMuted ? 'Unmute' : 'Mute',
                                backgroundColor: session.isMuted
                                    ? Colors.white.withOpacity(0.25)
                                    : Colors.white.withOpacity(0.12),
                                iconColor: session.isMuted
                                    ? AppColors.accentRose
                                    : Colors.white,
                                onTap: () {
                                  context
                                      .read<CallBloc>()
                                      .add(const ToggleMuteEvent());
                                },
                              ),

                              // Screen Share Toggle
                              CallControlButton(
                                icon: session.isScreenSharing
                                    ? Icons.stop_screen_share_rounded
                                    : Icons.screen_share_rounded,
                                label: session.isScreenSharing ? 'Stop Share' : 'Share',
                                backgroundColor: session.isScreenSharing
                                    ? AppColors.primary
                                    : Colors.white.withOpacity(0.12),
                                iconColor: session.isScreenSharing
                                    ? Colors.white
                                    : Colors.white,
                                onTap: () {
                                  context
                                      .read<CallBloc>()
                                      .add(const ToggleScreenShareEvent());
                                },
                              ),

                              // Hangup Button
                              CallControlButton(
                                icon: Icons.call_end_rounded,
                                label: 'End',
                                backgroundColor: AppColors.accentRose,
                                onTap: () {
                                  context
                                      .read<CallBloc>()
                                      .add(const HangupCallEvent());
                                },
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
