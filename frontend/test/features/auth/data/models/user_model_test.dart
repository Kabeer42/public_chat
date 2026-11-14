import 'package:chatapp/features/auth/data/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserModel', () {
    final testJson = {
      'id': 1,
      'name': 'Alice Johnson',
      'email': 'alice@example.com',
      'public_identity_key': 'testKey123',
      'public_signed_prekey': 'testPreKey456',
      'is_online': true,
      'last_seen_at': '2026-10-17T02:00:00.000Z',
      'created_at': '2026-10-17T01:00:00.000Z',
    };

    test('should correctly deserialize from JSON', () {
      final model = UserModel.fromJson(testJson);

      expect(model.id, 1);
      expect(model.name, 'Alice Johnson');
      expect(model.email, 'alice@example.com');
      expect(model.publicIdentityKey, 'testKey123');
      expect(model.publicSignedPrekey, 'testPreKey456');
      expect(model.isOnline, true);
      expect(model.lastSeenAt, DateTime.parse('2026-10-17T02:00:00.000Z'));
      expect(model.createdAt, DateTime.parse('2026-10-17T01:00:00.000Z'));
    });

    test('should correctly serialize to JSON', () {
      final model = UserModel.fromJson(testJson);
      final json = model.toJson();

      expect(json['id'], 1);
      expect(json['name'], 'Alice Johnson');
      expect(json['email'], 'alice@example.com');
      expect(json['public_identity_key'], 'testKey123');
      expect(json['is_online'], true);
    });
  });
}
