import 'package:chatapp/features/chat/data/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MessageModel', () {
    final testJson = {
      'id': 101,
      'sender_id': 1,
      'receiver_id': 2,
      'message_type': 'text',
      'ciphertext': 'ZDJWdVkyRjBkR1Z5ZEE9PQ==',
      'iv': 'YXNkZmFzZGZhc2Rm',
      'mac': 'MTIzNDU2Nzg5MDEyMzQ1Ng==',
      'media_url': null,
      'encrypted_media_key': null,
      'is_delivered': true,
      'is_read': false,
      'read_at': null,
      'created_at': '2026-10-17T03:00:00.000Z',
    };

    test('should correctly deserialize encrypted message from JSON', () {
      final model = MessageModel.fromJson(testJson);

      expect(model.id, 101);
      expect(model.senderId, 1);
      expect(model.receiverId, 2);
      expect(model.messageType, 'text');
      expect(model.ciphertext, 'ZDJWdVkyRjBkR1Z5ZEE9PQ==');
      expect(model.iv, 'YXNkZmFzZGZhc2Rm');
      expect(model.mac, 'MTIzNDU2Nzg5MDEyMzQ1Ng==');
      expect(model.isDelivered, true);
      expect(model.isRead, false);
      expect(model.readAt, isNull);
      expect(model.createdAt, DateTime.parse('2026-10-17T03:00:00.000Z'));
    });

    test('should correctly serialize to JSON maintaining zero-knowledge', () {
      final model = MessageModel.fromJson(testJson);
      final json = model.toJson();

      expect(json['id'], 101);
      expect(json['sender_id'], 1);
      expect(json['receiver_id'], 2);
      expect(json['ciphertext'], 'ZDJWdVkyRjBkR1Z5ZEE9PQ==');
      expect(json['iv'], 'YXNkZmFzZGZhc2Rm');
      expect(json['mac'], 'MTIzNDU2Nzg5MDEyMzQ1Ng==');
      expect(json['is_delivered'], true);
      expect(json['is_read'], false);
    });

    test('copyWith updates plaintext and read receipts accurately', () {
      final model = MessageModel.fromJson(testJson);
      final readAtTime = DateTime.parse('2026-10-17T03:05:00.000Z');

      final updated = model.copyWith(
        plaintext: 'Hello world!',
        isRead: true,
        readAt: readAtTime,
      );

      expect(updated.plaintext, 'Hello world!');
      expect(updated.isRead, true);
      expect(updated.readAt, readAtTime);
      expect(updated.ciphertext, model.ciphertext);
    });

    test('should correctly deserialize and serialize expires_at for disappearing messages', () {
      final jsonWithExpiry = Map<String, dynamic>.from(testJson);
      jsonWithExpiry['expires_at'] = '2026-10-17T15:00:00.000Z'; // 12 hours later

      final model = MessageModel.fromJson(jsonWithExpiry);
      expect(model.expiresAt, DateTime.parse('2026-10-17T15:00:00.000Z'));

      final serialized = model.toJson();
      expect(serialized['expires_at'], '2026-10-17T15:00:00.000Z');

      final copied = model.copyWith(
        expiresAt: DateTime.parse('2026-10-18T03:00:00.000Z'),
      );
      expect(copied.expiresAt, DateTime.parse('2026-10-18T03:00:00.000Z'));
    });

    test('should correctly deserialize and serialize delivered_at for delivery receipts', () {
      final jsonWithDelivery = Map<String, dynamic>.from(testJson);
      jsonWithDelivery['is_delivered'] = true;
      jsonWithDelivery['delivered_at'] = '2026-10-17T03:01:00.000Z';

      final model = MessageModel.fromJson(jsonWithDelivery);
      expect(model.isDelivered, true);
      expect(model.deliveredAt, DateTime.parse('2026-10-17T03:01:00.000Z'));

      final serialized = model.toJson();
      expect(serialized['is_delivered'], true);
      expect(serialized['delivered_at'], '2026-10-17T03:01:00.000Z');

      final copied = model.copyWith(
        isDelivered: true,
        deliveredAt: DateTime.parse('2026-10-17T03:02:00.000Z'),
      );
      expect(copied.isDelivered, true);
      expect(copied.deliveredAt, DateTime.parse('2026-10-17T03:02:00.000Z'));
    });

    test('should correctly deserialize and serialize sender_public_key', () {
      final jsonWithKey = Map<String, dynamic>.from(testJson);
      jsonWithKey['sender_public_key'] = 'zA3SauCFfLmCCmFkhA7A2xMgz7apQPpvMtVmPKgG+hs=';

      final model = MessageModel.fromJson(jsonWithKey);
      expect(model.senderPublicKey, 'zA3SauCFfLmCCmFkhA7A2xMgz7apQPpvMtVmPKgG+hs=');

      final serialized = model.toJson();
      expect(serialized['sender_public_key'], 'zA3SauCFfLmCCmFkhA7A2xMgz7apQPpvMtVmPKgG+hs=');

      final copied = model.copyWith(senderPublicKey: 'newKey123=');
      expect(copied.senderPublicKey, 'newKey123=');
    });
  });
}
