import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import '../exceptions/app_exception.dart';

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.createdAt,
    required this.createdBy,
    required this.entity,
    required this.action,
    required this.entityId,
    required this.oldValue,
    required this.newValue,
  });

  final String id;
  final DateTime createdAt;
  final String createdBy;
  final String entity;
  final String action;
  final String entityId;
  final Object? oldValue;
  final Object? newValue;

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['created_at'];
    final createdAt = createdAtRaw is String
        ? DateTime.tryParse(createdAtRaw) ?? DateTime.fromMillisecondsSinceEpoch(0)
        : createdAtRaw is DateTime
            ? createdAtRaw
            : DateTime.fromMillisecondsSinceEpoch(0);

    return AuditLogEntry(
      id: map['id']?.toString() ?? '',
      createdAt: createdAt,
      createdBy: map['created_by']?.toString() ?? '',
      entity: map['entity']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      entityId: map['entity_id']?.toString() ?? '',
      oldValue: map['old_value'],
      newValue: map['new_value'],
    );
  }
}

class AuditRepository {
  AuditRepository(this._client);

  final SupabaseClient _client;

  Future<List<AuditLogEntry>> fetchAuditLogs({
    String? entity,
    String? action,
    DateTime? from,
    DateTime? to,
    String? createdBy,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      dynamic query = _client
          .from('audit_logs')
          .select(
            'id, created_at, created_by, entity, action, entity_id, old_value, new_value',
          );

      if (entity != null && entity.isNotEmpty) {
        query = query.eq('entity', entity);
      }
      if (action != null && action.isNotEmpty) {
        query = query.eq('action', action);
      }
      if (createdBy != null && createdBy.isNotEmpty) {
        query = query.eq('created_by', createdBy);
      }
      if (from != null) {
        query = query.gte('created_at', from.toUtc().toIso8601String());
      }
      if (to != null) {
        query = query.lte('created_at', to.toUtc().toIso8601String());
      }

      final start = offset;
      final end = offset + limit - 1;

      final data = await query
          .order('created_at', ascending: false)
          .range(start, end);

      return (data as List<dynamic>)
          .map((e) => AuditLogEntry.fromMap(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(growable: false);
    } catch (e, st) {
      throw mapSupabaseError(
        e,
        st,
        operation: 'audit.fetchAuditLogs',
        fallbackMessage: 'Audit kayıtları yüklenemedi. Lütfen tekrar deneyin.',
      );
    }
  }
}

final auditRepository = AuditRepository(supabaseClient);
