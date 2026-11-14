import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/entities/call_entity.dart';
import '../bloc/call_bloc.dart';
import '../bloc/call_event.dart';
import '../bloc/call_state.dart';
import '../widgets/call_control_button.dart';

class VoiceCallPage extends StatefulWidget {
  final UserEntity peerUser;
  final bool isOutgoing;

  const VoiceCallPage({
    super.key,
    required this.peerUser,
    this.isOutgoing = true,
  });

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  @override
  void initState() {
    super.initState();
    if (widget.isOutgoing) {
      context.read<CallBloc>().add(StartOutgoingCallEvent(
            peerId: widget.peerUser.id,
            peerName: widget.peerUser.name,
            peerEmail: widget.peerUser.email,
            callType: 'voice',
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
          callType: 'voice',
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
          statusLabel = session.isCaller ? 'Calling...' : 'Incoming Voice Call...';
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
          backgroundColor: const Color(0xFF0F172A), // Dark slate / midnight
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Top Header / Encryption Banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, size: 14, color: AppColors.accent),
                      SizedBox(width: 6),
                      Text(
                        'WebRTC DTLS-SRTP Encrypted',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Contact Avatar with Pulsing Halo Effect
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (session.status == CallStatus.ringing ||
                          session.status == CallStatus.connecting)
                        Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withOpacity(0.12),
                          ),
                        ),
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primaryDark,
                              AppColors.primary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 30,
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
                              fontSize: 56,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Contact Name
                Text(
                  session.peerName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                // Call Status or Timer
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: isConnected ? 20 : 15,
                    fontWeight: isConnected ? FontWeight.w600 : FontWeight.w400,
                    color: isConnected ? AppColors.accent : Colors.white70,
                    letterSpacing: isConnected ? 1.2 : 0.5,
                  ),
                ),

                const Spacer(),

                // Bottom Call Action Controls
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
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
                              icon: Icons.call,
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
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Mute Toggle
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

                            // End Call Hangup Button
                            CallControlButton(
                              icon: Icons.call_end_rounded,
                              label: 'End Call',
                              backgroundColor: AppColors.accentRose,
                              onTap: () {
                                context
                                    .read<CallBloc>()
                                    .add(const HangupCallEvent());
                              },
                            ),

                            // Speakerphone Toggle
                            CallControlButton(
                              icon: session.isSpeakerOn
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_down_rounded,
                              label: session.isSpeakerOn ? 'Speaker' : 'Earpiece',
                              backgroundColor: session.isSpeakerOn
                                  ? AppColors.primary
                                  : Colors.white.withOpacity(0.12),
                              iconColor: Colors.white,
                              onTap: () {
                                context
                                    .read<CallBloc>()
                                    .add(const ToggleSpeakerEvent());
                              },
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
