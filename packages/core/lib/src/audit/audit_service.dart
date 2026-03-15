import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class AuditService {
  AuditService(this._client);

  final SupabaseClient _client;

  /// Best-effort audit logger.
  ///
  /// - Never throws (audit failure must not fail main operation).
  /// - In debug mode prints diagnostics.
  Future<void> logChange({
    required String entity,
    required String entityId,
    required String action,
    Map<String, dynamic>? oldValue,
    Map<String, dynamic>? newValue,
  }) async {
    try {
      await _client.from('audit_logs').insert(<String, dynamic>{
        'entity': entity,
        'entity_id': entityId,
        'action': action,
        if (oldValue != null) 'old_value': oldValue,
        if (newValue != null) 'new_value': newValue,
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          '[AUDIT] logChange failed entity=$entity entityId=$entityId action=$action error=$e',
        );
        debugPrintStack(stackTrace: st);
      }
    }
  }
}

final auditService = AuditService(supabaseClient);
