import 'dart:async';

import 'package:core/core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';

import 'core/crashlytics/crash_logger.dart';
import 'src/crashlytics/crashlytics.dart';
import 'src/router/admin_router.dart';
import 'src/theme/app_theme.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void validateEnvOrThrow() {
  if (supabaseUrl.trim().isEmpty) {
    throw StateError(
      'SUPABASE_URL tanımlı değil. Web/APK build için '
      '`--dart-define-from-file=.dart-define-admin-web.json` kullanın.',
    );
  }

  if (supabaseAnonKey.trim().isEmpty) {
    throw StateError(
      'SUPABASE_ANON_KEY tanımlı değil. Web/APK build için '
      '`--dart-define-from-file=.dart-define-admin-web.json` kullanın.',
    );
  }

  final uri = Uri.tryParse(supabaseUrl);
  final host = uri?.host ?? '';

  if (uri == null || !uri.hasScheme || host.isEmpty) {
    throw StateError(
      'SUPABASE_URL geçersiz: $supabaseUrl. Beklenen format: '
      'https://<project-id>.supabase.co',
    );
  }

  // Sık yapılan hata: Firebase Hosting URL'sini Supabase URL sanmak.
  if (host.endsWith('.web.app') || host.contains('firebaseapp.com')) {
    throw StateError(
      'SUPABASE_URL Firebase Hosting gibi görünüyor: $supabaseUrl. '
      'Supabase URL şu formatta olmalı: https://<project-id>.supabase.co',
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // runApp mümkün olduğunca erken çağrılsın; init işleri app içinde yapılır.
  runApp(const ProviderScope(child: _BootstrapHost()));
}

enum _BootstrapStatus {
  loading,
  ready,
  error,
}

class _BootstrapHost extends ConsumerStatefulWidget {
  const _BootstrapHost();

  @override
  ConsumerState<_BootstrapHost> createState() => _BootstrapHostState();
}

class _BootstrapHostState extends ConsumerState<_BootstrapHost> {
  _BootstrapStatus _status = _BootstrapStatus.loading;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _status = _BootstrapStatus.loading;
      _error = null;
    });

    try {
      await initializeDateFormatting('tr_TR', null)
          .timeout(const Duration(seconds: 2));

      validateEnvOrThrow();
      await core
          .initSupabase(
            url: supabaseUrl,
            anonKey: supabaseAnonKey,
          )
          .timeout(const Duration(seconds: 12));

      if (kDebugMode) {
        debugPrint(
          '[SUPABASE][BOOT] url=$supabaseUrl anonKeyLen=${supabaseAnonKey.length}',
        );
        final client = core.supabaseClient;
        final session = client.auth.currentSession;
        final user = client.auth.currentUser;
        debugPrint(
          '[SUPABASE][BOOT] restoredSession=${session != null} userId=${user?.id}',
        );
      }

      _setupSupabaseLogging();

      // Firebase Crashlytics (debug modda collection kapalı)
      await initCrashlytics();

      // Mevcut oturum varsa userId'yi Crashlytics'e bağla.
      await CrashLogger.setUserFromSupabaseAuth();

      // Auth state değişimlerinde (login/logout) userId'yi güncelle.
      core.supabaseClient.auth.onAuthStateChange.listen((data) {
        unawaited(CrashLogger.setUserFromSupabaseAuth());

        if (kDebugMode) {
          final event = data.event;
          final session = data.session;
          final userId = session?.user.id;
          // ignore: avoid_print
          print('AUTH STATE: $event');
          debugPrint('[AUTH][STATE] event=$event userId=$userId '
              'hasSession=${session != null}');
        }
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _status = _BootstrapStatus.ready;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _BootstrapStatus.error;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _BootstrapStatus.ready:
        return const AdminApp();
      case _BootstrapStatus.error:
        return MaterialApp(
          title: 'Karamanlar Ticaret',
          theme: AppTheme.light(),
          onGenerateRoute: (_) {
            return MaterialPageRoute<void>(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Uygulama başlatılamadı',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error.toString(),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _bootstrap,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tekrar Dene'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      case _BootstrapStatus.loading:
        return MaterialApp(
          title: 'Karamanlar Ticaret',
          theme: AppTheme.light(),
          onGenerateRoute: (_) {
            return MaterialPageRoute<void>(
              builder: (context) {
                return const Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              },
            );
          },
        );
    }
  }
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(adminRouterProvider);

    return MaterialApp.router(
      title: 'Karamanlar Ticaret',
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
        },
      ),
      routerConfig: router,
      builder: (context, child) {
        return core.AppResponsiveTheme(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

void _setupSupabaseLogging() {
  if (!kDebugMode) {
    return;
  }

  void listener(LogRecord record) {
    // Mesaj içindeki olası Bearer token'ları maskele.
    var message = record.message;
    message = message.replaceAllMapped(
      RegExp(r'Bearer\s+([A-Za-z0-9\-\._]+)'),
      (match) {
        final token = match.group(1) ?? '';
        final prefix = token.length > 10 ? token.substring(0, 10) : token;
        return 'Bearer $prefix...';
      },
    );

    // Mevcut auth durumunu da her kayıtla birlikte logla.
    try {
      final client = core.supabaseClient;
      final user = client.auth.currentUser;
      final session = client.auth.currentSession;
      final token = session?.accessToken;
      final tokenLen = token?.length ?? 0;
      final tokenPrefix = tokenLen > 0
          ? token!.substring(0, tokenLen > 10 ? 10 : tokenLen)
          : null;

      debugPrint(
        '[SUPABASE-HTTP] logger=${record.loggerName} '
        'level=${record.level.name} '
        'time=${record.time.toIso8601String()} '
        'message=$message',
      );

      final safeTokenPrefix = tokenPrefix != null ? '$tokenPrefix...' : 'null';

      debugPrint(
        '[AUTH][GLOBAL] '
        'uid=${user?.id} '
        'email=${user?.email} '
        'hasSession=${session != null} '
        'tokenLen=$tokenLen '
        'tokenPrefix=$safeTokenPrefix',
      );
    } catch (_) {
      debugPrint(
        '[SUPABASE-HTTP] logger=${record.loggerName} '
        'level=${record.level.name} '
        'time=${record.time.toIso8601String()} '
        'message=$message',
      );
    }
  }

  // Tüm Supabase logger'ları, hiyerarşik logger ağacı üzerinden
  // kök loggere akar. Root seviyesini ALL yapıp yalnızca
  // Supabase ile ilgili kayıtları dinliyoruz.
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('supabase')) {
      listener(record);
    }
  });
}
