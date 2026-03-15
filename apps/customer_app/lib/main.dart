import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core/core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/crashlytics/crash_logger.dart';
import 'src/crashlytics/crashlytics.dart';
import 'src/router/customer_router.dart';

// Production defaults (anon key is public by design).
const _prodSupabaseUrl = 'https://ajdsjfqybjsdokjgzsmq.supabase.co';
const _prodSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFqZHNqZnF5YmpzZG9ramd6c21xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njc3MDk1NjEsImV4cCI6MjA4MzI4NTU2MX0.zweOuMeeLNm6gUoxxS24a0-kF30ltxQg9ousvDH2JIU';

const supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: _prodSupabaseUrl);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: _prodSupabaseAnonKey,
);

void assertEnv() {
  assert(
    supabaseUrl.isNotEmpty,
    'SUPABASE_URL tanımlı değil. --dart-define ile verilmeli.',
  );
  assert(
    supabaseAnonKey.isNotEmpty,
    'SUPABASE_ANON_KEY tanımlı değil. --dart-define ile verilmeli.',
  );

  assert(() {
    debugPrint('[CUSTOMER] SUPABASE_URL=$supabaseUrl');
    final host = Uri.tryParse(supabaseUrl)?.host ?? '';
    if (host != 'ajdsjfqybjsdokjgzsmq.supabase.co') {
      debugPrint(
        '[CUSTOMER][WARN] Unexpected Supabase host: $host (expected ajdsjfqybjsdokjgzsmq.supabase.co)',
      );
    }
    return true;
  }());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TR locale için intl tarih/sayı verilerini yükle.
  await initializeDateFormatting('tr_TR', null);

  assertEnv();
  await initSupabase(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  await initCrashlytics();

  // Mevcut oturum varsa userId'yi Crashlytics'e bağla.
  await CrashLogger.setUserFromSupabaseAuth();

  // Auth state değişimlerinde (login/logout) userId'yi güncelle.
  supabaseClient.auth.onAuthStateChange.listen((_) {
    unawaited(CrashLogger.setUserFromSupabaseAuth());
  });

  runApp(const ProviderScope(child: CustomerApp()));
}

class CustomerApp extends ConsumerWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(customerRouterProvider);

    return MaterialApp.router(
      title: 'Karamanlar Müşteri',
      theme: AppTheme.light,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
        },
      ),
      routerConfig: router,
      builder: (context, child) {
        return AppResponsiveTheme(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
