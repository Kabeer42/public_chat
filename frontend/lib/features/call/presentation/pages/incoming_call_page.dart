import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../domain/entities/call_entity.dart';
import '../bloc/call_bloc.dart';
import '../bloc/call_event.dart';
import '../bloc/call_state.dart';
import '../widgets/call_control_button.dart';
import 'video_call_page.dart';
import 'voice_call_page.dart';

class IncomingCallPage extends StatefulWidget {
  final UserEntity caller;
  final String callType; // 'voice' or 'video'

  const IncomingCallPage({
    super.key,
    required this.caller,
    required this.callType,
  });

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rippleController;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _rippleController.dispose();
    super.dispose();
  }

  void _onAccept(BuildContext context) {
    context.read<CallBloc>().add(const AcceptCallEvent());

    // Navigate to the respective call screen
    if (widget.callType == 'video') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VideoCallPage(
            peerUser: widget.caller,
            isOutgoing: false,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceCallPage(
            peerUser: widget.caller,
            isOutgoing: false,
          ),
        ),
      );
    }
  }

  void _onDecline(BuildContext context) {
    context.read<CallBloc>().add(const RejectCallEvent());
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.callType == 'video';

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
        String callStatus = isVideo
            ? 'Incoming Video Call...'
            : 'Incoming Voice Call...';

        if (state is CallSessionState) {
          if (state.session.status == CallStatus.ended) {
            callStatus = 'Call Cancelled';
          }
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),

                // Encryption pill badge
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
                      Icon(Icons.lock_rounded,
                          size: 13, color: AppColors.accent),
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

                // Animated Ripple Pulsing Avatar
                Center(
                  child: AnimatedBuilder(
                    animation: _rippleController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 150 + (_rippleController.value * 40),
                            height: 150 + (_rippleController.value * 40),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withOpacity(
                                (1.0 - _rippleController.value) * 0.35,
                              ),
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
                                  color: AppColors.primary.withOpacity(0.5),
                                  blurRadius: 28,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                widget.caller.name.isNotEmpty
                                    ? widget.caller.name[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontSize: 54,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 32),

                // Caller Name
                Text(
                  widget.caller.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                // Call Type & Ringing Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      callStatus,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // Action Controls (Decline vs Accept)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Decline Action Button
                      CallControlButton(
                        icon: Icons.call_end_rounded,
                        label: 'Decline',
                        backgroundColor: AppColors.accentRose,
                        onTap: () => _onDecline(context),
                      ),

                      // Accept Action Button
                      CallControlButton(
                        icon: isVideo
                            ? Icons.videocam_rounded
                            : Icons.call_rounded,
                        label: 'Accept',
                        backgroundColor: AppColors.accent,
                        onTap: () => _onAccept(context),
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
