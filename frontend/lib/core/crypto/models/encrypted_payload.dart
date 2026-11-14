import 'package:equatable/equatable.dart';

class EncryptedPayload extends Equatable {
  final String ciphertext; // Base64 encoded encrypted data
  final String iv;         // Base64 encoded 12-byte initialization vector / nonce
  final String mac;        // Base64 encoded 16-byte authentication tag

  const EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
  });

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      ciphertext: json['ciphertext'] as String? ?? '',
      iv: json['iv'] as String? ?? '',
      mac: json['mac'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ciphertext': ciphertext,
      'iv': iv,
      'mac': mac,
    };
  }

  @override
  List<Object?> get props => [ciphertext, iv, mac];
}
