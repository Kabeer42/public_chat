import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart' as callkit;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../constants/api_endpoints.dart';
import '../di/injection_container.dart';
import '../utils/app_logger.dart';
import '../../features/call/presentation/bloc/call_bloc.dart';
import '../../features/call/presentation/bloc/call_event.dart';
import 'api_client.dart';

/// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  final data = message.data;
  if (data['type'] == 'incoming_call') {
    final callId = data['call_id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    final callerName = data['caller_name'] ?? 'Incoming Call';
    final callType = data['call_type'] == 'video' ? 1 : 0;

    final params = callkit.CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'ChatAPP',
      avatar: '',
      handle: '',
      type: callType,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: <String, dynamic>{
        'call_id': callId,
        'caller_id': data['caller_id'],
        'caller_name': callerName,
        'call_type': data['call_type'] ?? 'audio',
        'sdp': data['sdp'] ?? '',
      },
      android: const callkit.AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        isShowCallID: false,
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } else if (data['type'] == 'call_ended') {
    final callId = data['call_id'];
    if (callId != null) {
      await FlutterCallkitIncoming.endCall(callId);
    }
  }
}

class PushNotificationService {
  final ApiClient _apiClient;

  PushNotificationService({required ApiClient apiClient})
      : _apiClient = apiClient;

  Future<void> initialize() async {
    // Only run on mobile platforms (Android / iOS)
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      AppLogger.i('Push notifications skipped: platform is not mobile');
      return;
    }

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permissions for Android 13+ & iOS in background
      FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      ).then((settings) {
        AppLogger.i('Push notification authorization status: ${settings.authorizationStatus}');
      }).catchError((_) {});

      // Listen for CallKit actions (User clicked Accept or Decline)
      FlutterCallkitIncoming.onEvent.listen((callkit.CallEvent? event) {
        if (event == null) return;
        final extra = (event.body is Map) ? (event.body['extra'] as Map? ?? {}) : {};
        final callerId = int.tryParse(extra['caller_id']?.toString() ?? '') ?? 0;
        final sdp = extra['sdp']?.toString() ?? '';
        final callType = extra['call_type']?.toString() ?? 'voice';
        final callId = extra['call_id']?.toString() ?? event.body?['id']?.toString();
        final callerName = extra['caller_name']?.toString() ?? event.body?['nameCaller']?.toString() ?? 'Caller';

        switch (event.event) {
          case callkit.Event.actionCallAccept:
            AppLogger.i('CallKit incoming call ACCEPTED by user');
            try {
              if (callerId > 0) {
                sl<CallBloc>().add(IncomingCallReceivedEvent(
                  callerId: callerId,
                  callerName: callerName,
                  sdpOffer: sdp,
                  callType: callType,
                  callId: callId,
                ));
              }
              sl<CallBloc>().add(const AcceptCallEvent());
            } catch (e) {
              AppLogger.w('Failed to dispatch AcceptCallEvent: $e');
            }
            break;
          case callkit.Event.actionCallDecline:
            AppLogger.i('CallKit incoming call DECLINED by user');
            try {
              sl<CallBloc>().add(const RejectCallEvent());
            } catch (e) {
              AppLogger.w('Failed to dispatch RejectCallEvent: $e');
            }
            break;
          case callkit.Event.actionCallEnded:
            AppLogger.i('CallKit incoming call ENDED');
            break;
          default:
            break;
        }
      });

      // Synchronize any active incoming call if the app was launched by tapping CallKit UI
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls is List && activeCalls.isNotEmpty) {
          final first = activeCalls.first;
          if (first is Map) {
            final extra = first['extra'] as Map? ?? {};
            final callerId = int.tryParse(extra['caller_id']?.toString() ?? '') ?? 0;
            final isAccepted = first['isAccepted'] == true;
            if (callerId > 0) {
              sl<CallBloc>().add(IncomingCallReceivedEvent(
                callerId: callerId,
                callerName: extra['caller_name']?.toString() ?? first['nameCaller']?.toString() ?? 'Caller',
                sdpOffer: extra['sdp']?.toString() ?? '',
                callType: extra['call_type']?.toString() ?? 'voice',
                callId: extra['call_id']?.toString() ?? first['id']?.toString(),
              ));
              if (isAccepted) {
                AppLogger.i('Active call was accepted from cold start, auto-dispatching AcceptCallEvent');
                sl<CallBloc>().add(const AcceptCallEvent());
              }
            }
          }
        }
      } catch (e) {
        AppLogger.w('Active calls check error: $e');
      }

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        AppLogger.d('Foreground push message received: ${message.data}');
        if (message.data['type'] == 'call_ended') {
          final callId = message.data['call_id'];
          if (callId != null) {
            FlutterCallkitIncoming.endCall(callId);
          }
        }
      });

      // Synchronize FCM Token in background without stalling boot
      syncToken();

      // Listen for Token Refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        AppLogger.i('FCM Token refreshed');
        uploadToken(newToken);
      });
    } catch (e) {
      AppLogger.w('PushNotificationService initialization error: $e');
    }
  }

  Future<void> syncToken() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await uploadToken(token);
      }
    } catch (e) {
      AppLogger.w('Failed to obtain FCM token: $e');
    }
  }

  Future<void> uploadToken(String token) async {
    try {
      await _apiClient.post(
        ApiEndpoints.updateFcmToken,
        data: {'fcm_token': token},
      );
      AppLogger.i('FCM device token synchronized with server.');
    } catch (e) {
      AppLogger.w('Could not send FCM token to backend: $e');
    }
  }
}
