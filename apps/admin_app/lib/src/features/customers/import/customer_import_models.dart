/// Import sırasında satırın nihai durumunu temsil eder.
/// UI tarafında badge rengi ve metni için kullanılır.
enum ImportRowStatus {
  newItem,      // Yeni kayıt eklenecek
  willUpdate,   // Mevcut kayıt güncellenecek
  willSkip,     // Mevcut kayıt atlanacak
  error,        // Yerel veya sunucu hatası var
}

/// Çoğaltma (duplicate) stratejisi.
enum DuplicateStrategy {
  /// Cari koduna göre güncelle (upsert_by_customer_code)
  byCustomerCode,

  /// Vergi No / TCKN'ye göre güncelle (upsert_by_taxno)
  byTaxNo,

  /// Sadece yeni ekle, mevcutları atla (insert_only)
  insertOnly,
}

class CustomerImportRow {
  const CustomerImportRow({
    required this.index,
    required this.values,
    this.localIssues = const <String>[],
    this.serverStatus,
    this.serverIssues = const <String>[],
  });

  /// Excel içindeki satır numarası (header hariç, 1-based).
  final int index;

  /// Canonical kolon adı -> ham string değer.
  final Map<String, String> values;

  /// Flutter tarafındaki yerel validasyon hataları.
  final List<String> localIssues;

  /// Backend rpc_import_customers validate sonucundaki status.
  /// "insert" | "update" | "error" | "suspicious" vb.
  final String? serverStatus;

  /// Backend validate sonucundaki hata listesi.
  final List<String> serverIssues;

  bool get hasLocalError => localIssues.isNotEmpty;

  bool get hasServerError =>
      serverStatus == 'error' || serverStatus == 'suspicious';

  bool get hasAnyError => hasLocalError || hasServerError;

  List<String> get allIssues => <String>[...localIssues, ...serverIssues];

  CustomerImportRow copyWith({
    List<String>? localIssues,
    String? serverStatus,
    List<String>? serverIssues,
  }) {
    return CustomerImportRow(
      index: index,
      values: values,
      localIssues: localIssues ?? this.localIssues,
      serverStatus: serverStatus ?? this.serverStatus,
      serverIssues: serverIssues ?? this.serverIssues,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'index': index,
        'values': values,
        'localIssues': localIssues,
        'serverStatus': serverStatus,
        'serverIssues': serverIssues,
      };

  factory CustomerImportRow.fromJson(Map<String, dynamic> json) {
    return CustomerImportRow(
      index: json['index'] as int,
      values: (json['values'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      localIssues: (json['localIssues'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      serverStatus: json['serverStatus'] as String?,
      serverIssues: (json['serverIssues'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
    );
  }
}

class CustomerImportSummary {
  const CustomerImportSummary({
    required this.total,
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.failed,
  });

  final int total;
  final int inserted;
  final int updated;
  final int skipped;
  final int failed;
}

/// UI tarafında gösterilecek efektif durum hesaplaması.
ImportRowStatus effectiveStatus(
  CustomerImportRow row,
  DuplicateStrategy strategy,
) {
  if (row.hasAnyError) {
    return ImportRowStatus.error;
  }

  final status = row.serverStatus;
  if (status == 'insert') {
    return ImportRowStatus.newItem;
  }
  if (status == 'skip') {
    return ImportRowStatus.willSkip;
  }
  if (status == 'update') {
    switch (strategy) {
      case DuplicateStrategy.byCustomerCode:
      case DuplicateStrategy.byTaxNo:
        return ImportRowStatus.willUpdate;
      case DuplicateStrategy.insertOnly:
        return ImportRowStatus.willSkip;
    }
  }

  return ImportRowStatus.error;
}
