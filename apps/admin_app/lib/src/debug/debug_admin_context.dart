import 'package:core/core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin panelinde Supabase auth/RPC bağlamını detaylı loglar.
///
/// - rpc('is_admin') sonucunu
/// - currentUser.id
/// - accessToken ilk 20 karakterini
/// - session.user.aud ve session.user.role
///
/// Eğer is_admin sonucu false ise ayrıca:
/// - Supabase proje URL
/// - Kullanılan SupabaseClient'in aynı projeye işaret edip etmediği
///   (instance kimliği karşılaştırması) loglanır.
Future<void> debugAdminContext() async {
  if (!kDebugMode) {
    return;
  }
  try {
    final client = core.supabaseClient;
    final session = client.auth.currentSession;
    final user = client.auth.currentUser;

    final accessToken = session?.accessToken;
    String? accessTokenPrefix;
    if (accessToken != null && accessToken.isNotEmpty) {
      final len = accessToken.length < 20 ? accessToken.length : 20;
      accessTokenPrefix = accessToken.substring(0, len);
    }

    debugPrint('[ADMIN][DEBUG] ==== debugAdminContext START ====');
    debugPrint('[ADMIN][DEBUG] currentUser.id=${user?.id}');
    debugPrint('[ADMIN][DEBUG] session.exists=${session != null}');
    debugPrint('[ADMIN][DEBUG] accessToken.prefix20=${accessTokenPrefix != null ? '$accessTokenPrefix...' : 'null'}');
    debugPrint('[ADMIN][DEBUG] session.user.aud=${session?.user.aud}');
    debugPrint('[ADMIN][DEBUG] session.user.role=${session?.user.role}');

    dynamic rpcResult;
    try {
      rpcResult = await client.rpc('is_admin');
      debugPrint(
        '[ADMIN][DEBUG] rpc("is_admin") raw_result=$rpcResult type=${rpcResult.runtimeType}',
      );
    } catch (e, st) {
      debugPrint('[ADMIN][DEBUG] rpc("is_admin") error=$e');
      debugPrintStack(stackTrace: st);
    }

    bool? isAdmin;
    if (rpcResult is bool) {
      isAdmin = rpcResult;
    } else if (rpcResult is Map) {
      final dynamic value = rpcResult['is_admin'];
      if (value is bool) {
        isAdmin = value;
      }
    }

    if (isAdmin == false) {
      final url = core.supabaseUrl;
      debugPrint('[ADMIN][DEBUG] Supabase core.supabaseUrl=$url');

      try {
        final globalClient = Supabase.instance.client;
        final sameInstance = identical(client, globalClient);

        debugPrint('[ADMIN][DEBUG] SupabaseClient identity check: '
            'sameInstance=$sameInstance '
            'localHash=${client.hashCode} '
            'globalHash=${globalClient.hashCode}');
      } catch (e) {
        debugPrint('[ADMIN][DEBUG] Supabase client project verification error=$e');
      }
    }

    debugPrint('[ADMIN][DEBUG] ==== debugAdminContext END ====');
  } catch (e, st) {
    debugPrint('[ADMIN][DEBUG] debugAdminContext unexpected error: $e');
    debugPrintStack(stackTrace: st);
  }
}
