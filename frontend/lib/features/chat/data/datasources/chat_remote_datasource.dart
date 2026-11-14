import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/network/api_client.dart';
import '../models/message_model.dart';

abstract class ChatRemoteDataSource {
  Future<MessageModel> sendMessage(Map<String, dynamic> data);
  Future<({List<MessageModel> messages, bool hasMore})> getMessages(
    int peerId, {
    int? beforeId,
    int page = 1,
    int perPage = 50,
  });
  Future<bool> markAsDelivered(int messageId);
  Future<int> markConversationAsDelivered(int peerId);
  Future<bool> markAsRead(int messageId);
  Future<int> markConversationAsRead(int peerId);
  Future<Map<String, dynamic>> uploadEncryptedMedia(Uint8List encryptedBytes);
  Future<Uint8List> downloadEncryptedMedia(String mediaUrl);
  Future<List<int>> deleteMessages({required List<int> messageIds, required String type});
  Future<int> getDisappearingDuration(int peerId);
  Future<int> setDisappearingDuration(int peerId, int durationSeconds);
  Future<String?> getPublicKey(int userId);
}

class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final ApiClient _apiClient;

  ChatRemoteDataSourceImpl(this._apiClient);

  @override
  Future<MessageModel> sendMessage(Map<String, dynamic> data) async {
    final response = await _apiClient.post(
      ApiEndpoints.sendMessage,
      data: data,
    );

    final responseData = response.data['message'];
    return MessageModel.fromJson(responseData);
  }

  @override
  Future<({List<MessageModel> messages, bool hasMore})> getMessages(
    int peerId, {
    int? beforeId,
    int page = 1,
    int perPage = 50,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.getMessages(peerId),
      queryParameters: {
        if (beforeId != null) 'before_id': beforeId,
        'page': page,
        'per_page': perPage,
      },
    );

    final List items = response.data['data'] ?? [];
    final pagination = response.data['pagination'] as Map<String, dynamic>?;
    final hasMore = pagination?['has_more'] as bool? ?? (items.length >= perPage);
    final messages = items.map((json) => MessageModel.fromJson(json)).toList();
    return (messages: messages, hasMore: hasMore);
  }

  @override
  Future<bool> markAsDelivered(int messageId) async {
    final response = await _apiClient.post(
      ApiEndpoints.markAsDelivered(messageId),
    );
    return response.statusCode == 200;
  }

  @override
  Future<int> markConversationAsDelivered(int peerId) async {
    final response = await _apiClient.post(
      ApiEndpoints.markConversationAsDelivered(peerId),
    );
    return response.data['delivered_count'] ?? 0;
  }

  @override
  Future<bool> markAsRead(int messageId) async {
    final response = await _apiClient.post(
      ApiEndpoints.markAsRead(messageId),
    );
    return response.statusCode == 200;
  }

  @override
  Future<int> markConversationAsRead(int peerId) async {
    final response = await _apiClient.post(
      ApiEndpoints.markConversationAsRead(peerId),
    );
    return response.data['marked_count'] ?? 0;
  }

  @override
  Future<Map<String, dynamic>> uploadEncryptedMedia(Uint8List encryptedBytes) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        encryptedBytes,
        filename: 'payload.enc',
      ),
    });

    final response = await _apiClient.post(
      ApiEndpoints.uploadMedia,
      data: formData,
    );

    return Map<String, dynamic>.from(response.data);
  }

  @override
  Future<Uint8List> downloadEncryptedMedia(String mediaUrl) async {
    String cleanPath = mediaUrl.trim();
    if (cleanPath.startsWith('/api/v1/')) {
      cleanPath = cleanPath.substring('/api/v1'.length);
    } else if (cleanPath.startsWith('api/v1/')) {
      cleanPath = '/${cleanPath.substring('api/v1/'.length)}';
    } else if (!cleanPath.startsWith('/') && !cleanPath.startsWith('http')) {
      cleanPath = '/$cleanPath';
    }

    final response = await _apiClient.get<List<int>>(
      cleanPath,
      options: Options(responseType: ResponseType.bytes),
    );

    return Uint8List.fromList(response.data!);
  }

  @override
  Future<List<int>> deleteMessages({required List<int> messageIds, required String type}) async {
    final response = await _apiClient.delete(
      ApiEndpoints.deleteMessages,
      data: {
        'message_ids': messageIds,
        'type': type,
      },
    );

    final List deleted = response.data['deleted_ids'] ?? [];
    return deleted.map((e) => e as int).toList();
  }

  @override
  Future<int> getDisappearingDuration(int peerId) async {
    final response = await _apiClient.get(
      ApiEndpoints.conversationDisappearing(peerId),
    );
    return response.data['disappearing_duration_seconds'] as int? ?? 0;
  }

  @override
  Future<int> setDisappearingDuration(int peerId, int durationSeconds) async {
    final response = await _apiClient.post(
      ApiEndpoints.conversationDisappearing(peerId),
      data: {'duration': durationSeconds},
    );
    return response.data['disappearing_duration_seconds'] as int? ?? durationSeconds;
  }

  @override
  Future<String?> getPublicKey(int userId) async {
    try {
      final response = await _apiClient.get(ApiEndpoints.getPublicKey(userId));
      return response.data['public_identity_key'] as String?;
    } catch (_) {
      return null;
    }
  }
}
