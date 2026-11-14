import 'dart:developer' as developer;

class AppLogger {
  static void d(String message, [String tag = 'ChatAPP']) {
    developer.log('💙 [DEBUG] $message', name: tag);
  }

  static void i(String message, [String tag = 'ChatAPP']) {
    developer.log('💚 [INFO] $message', name: tag);
  }

  static void w(String message, [String tag = 'ChatAPP']) {
    developer.log('💛 [WARN] $message', name: tag);
  }

  static void e(String message, [dynamic error, StackTrace? stackTrace, String tag = 'ChatAPP']) {
    developer.log('❤️ [ERROR] $message', error: error, stackTrace: stackTrace, name: tag);
  }
}
