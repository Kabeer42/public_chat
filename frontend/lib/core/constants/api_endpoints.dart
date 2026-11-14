class ApiEndpoints {
  // Health
  static const String health = '/health';

  // Auth & Profile
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';
  static const String updateProfile = '/auth/profile';
  static const String updatePassword = '/auth/password';
  static const String updatePrivacy = '/auth/privacy';

  // User Directory
  static const String users = '/users';
  static const String updateFcmToken = '/user/fcm-token';

  // E2EE Public Keys & Key Backup
  static const String publishKey = '/keys/publish';
  static const String keyBackup = '/keys/backup';
  static const String resetKeys = '/keys/reset';
  static String getPublicKey(int userId) => '/keys/$userId';

  // Messages (E2EE)
  static const String sendMessage = '/messages/send';
  static String getMessages(int peerId) => '/messages/$peerId';
  static String markAsDelivered(int messageId) => '/messages/$messageId/delivered';
  static String markConversationAsDelivered(int peerId) => '/messages/conversation/$peerId/delivered';
  static String markAsRead(int messageId) => '/messages/$messageId/read';
  static String markConversationAsRead(int peerId) => '/messages/conversation/$peerId/read';
  static const String deleteMessages = '/messages';

  // Conversation Settings (Disappearing Messages)
  static String conversationDisappearing(int peerId) => '/conversations/$peerId/disappearing';

  // Encrypted Media Blobs
  static const String uploadMedia = '/media/upload';
  static String downloadMedia(String uuid) => '/media/$uuid';

  // WebRTC Signaling
  static const String callOffer = '/call/offer';
  static const String callAnswer = '/call/answer';
  static const String iceCandidate = '/call/ice-candidate';
  static const String callEnd = '/call/end';

  // Error Auditing & Diagnostics
  static const String clientErrorLog = '/errors/client';
  static String errorLookup(String refCode) => '/errors/$refCode';
}
