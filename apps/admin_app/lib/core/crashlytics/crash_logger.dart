import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import '../../src/crashlytics/crashlytics.dart' as app_crashlytics;

class CrashLogger {
  static String? _lastScreen;
  static DateTime? _lastScreenAt;

  static Future<void> setUserFromSupabaseAuth() async {
    try {
      final user = supabaseClient.auth.currentUser;
      if (user == null) return;

      await app_crashlytics.setUserIdentifier(user.id);
      await app_crashlytics.setCustomKey('supabase_user_id', user.id);
    } catch (e, st) {
      await app_crashlytics.recordError(
        e,
        st,
        reason: 'crashlogger_set_user_failed',
        fatal: false,
      );
    }
  }

  static void logScreen(String screenName) {
    if (kIsWeb) return;

    final now = DateTime.now();
    final lastAt = _lastScreenAt;

    // Aynı ekran için rebuild/log spam'ini azalt.
    if (_lastScreen == screenName &&
        lastAt != null &&
        now.difference(lastAt) < const Duration(seconds: 3)) {
      return;
    }

    _lastScreen = screenName;
    _lastScreenAt = now;

    app_crashlytics.setCustomKey('screen', screenName).ignore();
    app_crashlytics.logMessage('screen:$screenName');
  }

  static Future<void> recordError(
    Object error,
    StackTrace stack, {
    String? reason,
    bool fatal = false,
  }) async {
    await app_crashlytics.recordError(
      error,
      stack,
      reason: reason,
      fatal: fatal,
    );
  }

  static Future<void> recordSupabaseError(
    Object error,
    StackTrace stack, {
    required String reason,
    String? operation,
    String? table,
  }) async {
    final parts = <String>[reason];
    if (operation != null && operation.isNotEmpty) parts.add(operation);
    if (table != null && table.isNotEmpty) parts.add(table);

    await app_crashlytics.recordError(
      error,
      stack,
      reason: parts.join(' | '),
      fatal: false,
    );
  }
}

extension on Future<void> {
  void ignore() {}
}
