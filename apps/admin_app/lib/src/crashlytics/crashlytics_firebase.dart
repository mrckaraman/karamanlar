import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

bool _didInit = false;
bool _isReady = false;

bool get isCrashlyticsReady => _isReady;

Future<void> initCrashlytics() async {
  if (_didInit) return;
  _didInit = true;

  try {
    await Firebase.initializeApp();

    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    _isReady = true;
    if (kDebugMode) {
      debugPrint('[CRASHLYTICS] init ok enabled=${!kDebugMode}');
    }
  } catch (e, st) {
    _isReady = false;
    debugPrint('[CRASHLYTICS] init failed: $e');
    debugPrintStack(stackTrace: st);
  }
}

void testCrash() {
  if (kDebugMode) {
    unawaited(
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true),
    );
  }
  FirebaseCrashlytics.instance.crash();
}

Future<void> setUserIdentifier(String userId) async {
  await FirebaseCrashlytics.instance.setUserIdentifier(userId);
}

Future<void> setCustomKey(String key, Object value) async {
  await FirebaseCrashlytics.instance.setCustomKey(key, value);
}

void logMessage(String message) {
  FirebaseCrashlytics.instance.log(message);
}

Future<void> recordError(
  Object error,
  StackTrace stack, {
  String? reason,
  bool fatal = false,
}) async {
  await FirebaseCrashlytics.instance.recordError(
    error,
    stack,
    reason: reason,
    fatal: fatal,
  );
}
