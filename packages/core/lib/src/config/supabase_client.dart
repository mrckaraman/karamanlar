import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Proje genelinde kullanılacak Supabase istemcisini initialize eder.
///
/// Bu fonksiyon her iki uygulamanın main() içinde, runApp çağrısından önce
/// bir kez çağrılmalıdır.
late String _supabaseUrl;
late String _supabaseAnonKey;
bool _didInitSupabase = false;

enum _AuthRefreshOutcome {
  refreshed,
  timeout,
  error,
}

void _validateSupabaseConfig({
  required String url,
  required String anonKey,
}) {
  if (url.trim().isEmpty) {
    throw ArgumentError.value(url, 'url', 'Supabase URL boş olamaz.');
  }
  if (anonKey.trim().isEmpty) {
    throw ArgumentError.value(
      anonKey,
      'anonKey',
      'Supabase anon key boş olamaz.',
    );
  }

  final uri = Uri.tryParse(url);
  final host = uri?.host ?? '';
  if (uri == null || !uri.hasScheme || host.isEmpty) {
    throw ArgumentError.value(
      url,
      'url',
      'Supabase URL geçersiz. Beklenen format: https://<project-id>.supabase.co',
    );
  }

  // En yaygın yanlış konfig: Firebase Hosting URL'si.
  if (host.endsWith('.web.app') || host.contains('firebaseapp.com')) {
    throw ArgumentError.value(
      url,
      'url',
      'Supabase URL Firebase Hosting gibi görünüyor. '
          'Beklenen format: https://<project-id>.supabase.co',
    );
  }

  // Custom domain kullanımı mümkün; sadece debug modda uyar.
  if (kDebugMode && !host.contains('supabase')) {
    debugPrint('[SUPABASE][WARN] URL host unexpected: $host');
  }
}

Future<void> initSupabase({
  required String url,
  required String anonKey,
}) async {
  if (_didInitSupabase) {
    if (url != _supabaseUrl || anonKey != _supabaseAnonKey) {
      throw StateError(
        '[SUPABASE] initSupabase called more than once with different config. '
        'urlChanged=${url != _supabaseUrl} anonKeyChanged=${anonKey != _supabaseAnonKey}',
      );
    }

    if (kDebugMode) {
      debugPrint('[SUPABASE] initSupabase skipped (already initialized)');
    }
    return;
  }

  _validateSupabaseConfig(url: url, anonKey: anonKey);
  _supabaseUrl = url;
  _supabaseAnonKey = anonKey;
  await Supabase.initialize(
    url: url,
    anonKey: anonKey,
  );
  _didInitSupabase = true;

  // Bazı cihazlarda/ortamlarda kalıcı storage'da eski bir refresh token kalabiliyor.
  // Token Supabase tarafında artık geçersizse uygulama açılışında sürekli hata logu
  // basmamak için local session'ı temizleyip login akışına düşürüyoruz.
  final client = Supabase.instance.client;
  final existingSession = client.auth.currentSession;
  var refreshSummary = 'no-session';
  if (existingSession != null) {
    // Web'de (ve bazı ağ koşullarında) refreshSession bazen uzun süre
    // bekleyebilir/hang'e girebilir. Ayrıca Future.timeout() alttaki Future'ı
    // iptal etmediği için, timeout sonrası gelen hatalar "unhandled" olabilir.
    // Bu yüzden refreshSession sonucunu asla error olarak bırakmıyoruz;
    // her durumda bir outcome'a map'leyip burada ele alıyoruz.
    final refreshOutcomeFuture = client.auth
        .refreshSession()
        .then<_AuthRefreshOutcome>((_) => _AuthRefreshOutcome.refreshed)
        .catchError((_) => _AuthRefreshOutcome.error);

    final outcome = await Future.any<_AuthRefreshOutcome>([
      refreshOutcomeFuture,
      Future<_AuthRefreshOutcome>.delayed(
        const Duration(seconds: 8),
        () => _AuthRefreshOutcome.timeout,
      ),
    ]);

    if (outcome == _AuthRefreshOutcome.refreshed) {
      refreshSummary = 'refreshed';
    } else {
      final Object e = (outcome == _AuthRefreshOutcome.timeout)
          ? TimeoutException('refreshSession timeout')
          : Exception('refreshSession failed');

      final message = e.toString().toLowerCase();
      final isTimeout = e is TimeoutException;
      final looksLikeInvalidRefreshToken =
          message.contains('invalid refresh token') ||
          message.contains('refresh_token_not_found') ||
          message.contains('refresh token not found');

      final looksLikeFetchFailure =
          message.contains('failed to fetch') ||
          message.contains('authretryablefetchexception') ||
          message.contains('xmlhttprequest') ||
          message.contains('networkerror') ||
          message.contains('cors');

      // İstenilen davranış:
      // - Timeout / Failed to fetch: startup bloklanmasın, session yokmuş gibi devam et.
      // - Invalid refresh token: local signOut ile temiz state.
      // - Diğer hatalarda da açılışı engelleme; yine session'ı temizle.
      if (looksLikeInvalidRefreshToken) {
        refreshSummary = 'cleared(invalid)';
      } else if (isTimeout || looksLikeFetchFailure) {
        refreshSummary = isTimeout ? 'cleared(timeout)' : 'cleared(fetch)';
      } else {
        refreshSummary = 'cleared(error)';
      }

      try {
        await client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Local signOut başarısız olsa bile açılışı engellemeyelim.
      }
    }
  } else {
    refreshSummary = 'no-session';
  }

  // Tek satır özet log (spam azaltma)
  if (kDebugMode) {
    debugPrint('[SUPABASE] init ok refresh=$refreshSummary');
  }
}

SupabaseClient get supabaseClient => Supabase.instance.client;

/// Supabase URL (raw HTTP çağrıları için saklanır).
String get supabaseUrl => _supabaseUrl;

/// Supabase anon key (raw HTTP çağrıları için saklanır).
String get supabaseAnonKey => _supabaseAnonKey;

/// PostgREST çağrılarını sarmalayıp hata detaylarını merkezi olarak loglar.
Future<T> guardPostgrest<T>(
  String label,
  Future<T> Function() run,
) async {
  try {
    return await run();
  } on PostgrestException catch (e, st) {
    debugPrint('[SUPABASE-ERROR] label=$label');
    debugPrint('[SUPABASE-ERROR] code=${e.code} message=${e.message}');
    if (e.details != null && e.details!.toString().isNotEmpty) {
      debugPrint('[SUPABASE-ERROR] details=${e.details}');
    }
    if (e.hint != null && e.hint!.toString().isNotEmpty) {
      debugPrint('[SUPABASE-ERROR] hint=${e.hint}');
    }
    debugPrintStack(stackTrace: st);
    rethrow;
  } catch (e, st) {
    debugPrint('[SUPABASE-ERROR] label=$label generic-error=$e');
    debugPrintStack(stackTrace: st);
    rethrow;
  }
}
