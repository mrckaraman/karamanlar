import 'dart:convert';
import 'dart:typed_data';

import 'audit_repository.dart';

class AuditExportFile {
  const AuditExportFile({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

class AuditExportService {
  AuditExportService({
    required AuditRepository auditRepository,
  }) : _repo = auditRepository;

  final AuditRepository _repo;

  static String buildTimestampedFileName({
    DateTime? now,
  }) {
    final dt = now ?? DateTime.now();
    final ts = _formatTimestamp(dt);
    return 'audit_logs_$ts.csv';
  }

  Future<AuditExportFile> buildCsv({
    String? entity,
    String? action,
    DateTime? from,
    DateTime? to,
    String? createdBy,
    DateTime? now,
    int pageSize = 500,
  }) async {
    final fileName = buildTimestampedFileName(now: now);

    final rows = <List<String>>[
      <String>[
        'created_at',
        'created_by',
        'entity',
        'action',
        'entity_id',
        'old_value',
        'new_value',
      ],
    ];

    var offset = 0;
    while (true) {
      final batch = await _repo.fetchAuditLogs(
        entity: entity,
        action: action,
        from: from,
        to: to,
        createdBy: createdBy,
        limit: pageSize,
        offset: offset,
      );

      for (final e in batch) {
        rows.add(
          <String>[
            e.createdAt.toUtc().toIso8601String(),
            e.createdBy,
            e.entity,
            e.action,
            e.entityId,
            _encodeJsonCell(e.oldValue),
            _encodeJsonCell(e.newValue),
          ],
        );
      }

      if (batch.length < pageSize) break;
      offset += batch.length;
    }

    final csv = _toCsv(rows);

    // Excel-friendly UTF-8 BOM.
    final content = '\uFEFF$csv';
    final bytes = Uint8List.fromList(utf8.encode(content));

    return AuditExportFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/csv',
    );
  }
}

String _encodeJsonCell(Object? value) {
  if (value == null) return '';

  if (value is String) {
    // Hem raw string hem JSON string gelebilir; olduğu gibi yaz.
    return value;
  }

  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

String _toCsv(List<List<String>> rows) {
  String esc(String v) {
    final needsQuote = v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    if (!needsQuote) return v;
    final escaped = v.replaceAll('"', '""');
    return '"$escaped"';
  }

  return rows.map((r) => r.map((c) => esc(c)).join(',')).join('\r\n');
}

String _formatTimestamp(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  final y = dt.year.toString().padLeft(4, '0');
  final m = two(dt.month);
  final d = two(dt.day);
  final hh = two(dt.hour);
  final mm = two(dt.minute);
  return '$y-$m-${d}_$hh-$mm';
}
