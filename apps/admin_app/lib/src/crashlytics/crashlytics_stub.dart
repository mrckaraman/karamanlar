import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

bool get isCrashlyticsReady => false;

Future<void> initCrashlytics() async {
  // Web'de Crashlytics desteklenmez; ama Firebase Core init'i denemek
  // istersek (FlutterFire options ile) burası hazır.
  if (!kIsWeb) return;

  try {
    final opts = DefaultFirebaseOptions.web;
    final hasMinimum =
        opts.apiKey.isNotEmpty && opts.appId.isNotEmpty && opts.projectId.isNotEmpty;
    if (!hasMinimum) {
      if (kDebugMode) {
        debugPrint('[CRASHLYTICS] web firebase options missing; skipping init');
      }
      return;
    }

    await Firebase.initializeApp(options: opts);
    if (kDebugMode) {
      debugPrint('[CRASHLYTICS] web firebase core init ok (crashlytics disabled)');
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[CRASHLYTICS] web init skipped: $e');
    }
  }
}

void testCrash() {
  throw UnsupportedError('Crashlytics is not supported on this platform');
}

Future<void> setUserIdentifier(String userId) async {
  // no-op (web)
}

Future<void> setCustomKey(String key, Object value) async {
  // no-op (web)
}

void logMessage(String message) {
  // no-op (web)
}

Future<void> recordError(
  Object error,
  StackTrace stack, {
  String? reason,
  bool fatal = false,
}) async {
  // no-op (web)
}
