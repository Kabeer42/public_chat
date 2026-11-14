import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/api_client.dart';

abstract class CallSignalingRemoteDataSource {
  Future<Map<String, dynamic>> sendOffer({
    required int receiverId,
    required String callType,
    required String sdpOffer,
    String? callId,
  });

  Future<Map<String, dynamic>> sendAnswer({
    required int callerId,
    required String sdpAnswer,
    String? callId,
  });

  Future<void> sendIceCandidate({
    required int targetUserId,
    required Map<String, dynamic> candidate,
    String? callId,
  });

  Future<void> endCall({
    required int targetUserId,
    String? reason,
    String? callId,
  });
}

class CallSignalingRemoteDataSourceImpl implements CallSignalingRemoteDataSource {
  final ApiClient _apiClient;

  CallSignalingRemoteDataSourceImpl(this._apiClient);

  @override
  Future<Map<String, dynamic>> sendOffer({
    required int receiverId,
    required String callType,
    required String sdpOffer,
    String? callId,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.callOffer,
      data: {
        'receiver_id': receiverId,
        'call_type': callType,
        'sdp': sdpOffer,
        'sdp_offer': sdpOffer,
        if (callId != null) 'call_id': callId,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> sendAnswer({
    required int callerId,
    required String sdpAnswer,
    String? callId,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.callAnswer,
      data: {
        'receiver_id': callerId,
        'caller_id': callerId,
        'sdp': sdpAnswer,
        'sdp_answer': sdpAnswer,
        if (callId != null) 'call_id': callId,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<void> sendIceCandidate({
    required int targetUserId,
    required Map<String, dynamic> candidate,
    String? callId,
  }) async {
    await _apiClient.post(
      ApiEndpoints.iceCandidate,
      data: {
        'receiver_id': targetUserId,
        'target_user_id': targetUserId,
        'candidate': candidate,
        if (callId != null) 'call_id': callId,
      },
    );
  }

  @override
  Future<void> endCall({
    required int targetUserId,
    String? reason,
    String? callId,
  }) async {
    await _apiClient.post(
      ApiEndpoints.callEnd,
      data: {
        'receiver_id': targetUserId,
        'target_user_id': targetUserId,
        'reason': reason ?? 'normal_hangup',
        if (callId != null) 'call_id': callId,
      },
    );
  }
}
