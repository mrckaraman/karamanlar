class ImportErrorRow {
  const ImportErrorRow({
    required this.rowNumber,
    required this.message,
    required this.values,
  });

  /// 1-based row number in the original CSV (including header line).
  final int rowNumber;

  /// Human-readable error description for this row.
  final String message;

  /// Raw column values parsed from CSV for this row.
  final Map<String, String> values;
}

/// Details for a stock that could not be deleted during master sync.
class NotDeletedStock {
  const NotDeletedStock({
    required this.code,
    this.name,
    required this.reason,
  });

  /// Stock code.
  final String code;

  /// Optional stock name if available.
  final String? name;

  /// Human-readable reason why deletion failed (for example FK constraint).
  final String reason;
}

class ImportResult {
  const ImportResult({
    required this.insertedCount,
    required this.updatedCount,
    required this.deletedCount,
    required this.notDeletedCount,
    required this.skippedCount,
    required this.errorRows,
    this.notDeletedStocks = const [],
  });

  /// Number of new stocks inserted.
  final int insertedCount;

  /// Number of existing stocks updated (matched by code).
  final int updatedCount;

  /// Number of stocks successfully deleted because they were missing in CSV.
  final int deletedCount;

  /// Number of stocks that were planned to be deleted but could not be
  /// removed due to constraints.
  final int notDeletedCount;

  /// Number of CSV rows skipped before hitting the database
  /// (for example because of missing required fields).
  final int skippedCount;

  /// Rows that could not be processed because of validation errors.
  final List<ImportErrorRow> errorRows;

  /// Detailed information for stocks that could not be deleted.
  final List<NotDeletedStock> notDeletedStocks;
}
