import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uygulama genelinde UI'ya güvenli şekilde taşınacak hata tipi.
///
/// - [message]: Kullanıcıya gösterilebilecek sade mesaj.
/// - [debugMessage]: Sadece debug loglarda kullanılacak detay.
class AppException implements Exception {
  AppException(
    this.message, {
    this.code,
    this.debugMessage,
    this.cause,
  });

  final String message;
  final String? code;
  final String? debugMessage;
  final Object? cause;

  @override
  String toString() => message;

  static String messageOf(Object error) {
    if (error is AppException) return error.message;
    if (error is PostgrestException || error is AuthException) {
      return mapSupabaseError(
        error,
        StackTrace.current,
        operation: 'ui',
      ).message;
    }
    return 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.';
  }
}

AppException mapSupabaseError(
  Object error,
  StackTrace stackTrace, {
  required String operation,
  String? fallbackMessage,
}) {
  if (error is AppException) {
    return error;
  }

  void debugLog(String msg) {
    if (!kDebugMode) return;
    debugPrint('[APP-ERROR] op=$operation $msg');
  }

  if (error is PostgrestException) {
    debugLog('PostgrestException code=${error.code} message=${error.message}');
    if (error.details != null && error.details!.toString().isNotEmpty) {
      debugLog('details=${error.details}');
    }
    if (error.hint != null && error.hint!.toString().isNotEmpty) {
      debugLog('hint=${error.hint}');
    }
    debugLog('stack=$stackTrace');

    final msg = error.message.toLowerCase();
    final String friendly;
    if (msg.contains('permission denied') ||
        msg.contains('row-level security') ||
        msg.contains('rls') ||
        msg.contains('not authorized') ||
        msg.contains('insufficient privilege')) {
      friendly = 'Bu işlem için yetkiniz yok.';
    } else if (error.code == '23503' || msg.contains('foreign key')) {
      friendly = 'İşlem gerçekleştirilemedi: İlişkili kayıt bulunamadı.';
    } else if (error.code == '23505' || msg.contains('duplicate key')) {
      friendly = 'Bu kayıt zaten mevcut.';
    } else if (error.code == '22P02' || msg.contains('invalid input')) {
      friendly = 'Geçersiz veri gönderildi. Lütfen alanları kontrol edin.';
    } else if (error.code == '23514' || msg.contains('check constraint')) {
      friendly = 'Geçersiz veri gönderildi. Lütfen alanları kontrol edin.';
    } else {
      friendly = fallbackMessage ?? 'İşlem gerçekleştirilemedi. Lütfen tekrar deneyin.';
    }

    return AppException(
      friendly,
      code: error.code,
      debugMessage: 'PostgrestException: ${error.message}',
      cause: error,
    );
  }

  if (error is AuthException) {
    debugLog('AuthException status=${error.statusCode} message=${error.message}');
    debugLog('stack=$stackTrace');

    final status = error.statusCode?.toString();
    final String friendly;
    if (status == '401') {
      friendly = 'Oturumunuz geçersiz veya süresi dolmuş. Lütfen tekrar giriş yapın.';
    } else {
      friendly = fallbackMessage ?? 'Kimlik doğrulama hatası. Lütfen tekrar deneyin.';
    }

    return AppException(
      friendly,
      code: status,
      debugMessage: 'AuthException: ${error.message}',
      cause: error,
    );
  }

  debugLog('Unknown error=$error');
  debugLog('stack=$stackTrace');

  return AppException(
    fallbackMessage ?? 'Beklenmeyen bir hata oluştu. Lütfen tekrar deneyin.',
    debugMessage: error.toString(),
    cause: error,
  );
}
