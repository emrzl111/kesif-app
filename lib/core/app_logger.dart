import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

/// Uygulama genelinde kullanılacak merkezi logger.
///
/// Kullanım:
///   AppLogger.info('Kullanıcı giriş yaptı', tag: 'AuthService');
///   AppLogger.error('DB hatası', error: e, stack: stack, tag: 'DatabaseService');
///
/// Release modunda sadece hata ve uyarılar loglanır.
class AppLogger {
  AppLogger._();

  static void info(String message, {String tag = 'App'}) {
    if (kDebugMode) {
      dev.log('ℹ️  $message', name: tag);
    }
  }

  static void warning(String message, {String tag = 'App'}) {
    dev.log('⚠️  $message', name: tag, level: 900);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stack,
    String tag = 'App',
  }) {
    dev.log(
      '❌ $message',
      name: tag,
      level: 1000,
      error: error,
      stackTrace: stack,
    );
  }

  static void debug(String message, {String tag = 'App'}) {
    if (kDebugMode) {
      dev.log('🐛 $message', name: tag);
    }
  }
}
