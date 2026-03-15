import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import 'auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return supabaseClient;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AuthRepository(client);
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

/// Kullanıcının admin yetkisine sahip olup olmadığını Supabase RPC'si üzerinden kontrol eder.
///
/// Backend'de tanımlı `is_admin` fonksiyonunu çağırır ve:
/// - Başarılıysa: dönen bool değeri kullanır.
/// - Hata veya beklenmeyen cevap durumunda: `false` döner.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  try {
    final dynamic result = await client.rpc('is_admin');

    if (result is bool) {
      return result;
    }

    if (result is Map) {
      final dynamic value = result['is_admin'];
      if (value is bool) return value;
    }

    return false;
  } catch (_) {
    // Herhangi bir hata durumunda admin değil varsay.
    return false;
  }
});
