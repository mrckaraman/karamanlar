import 'dart:convert';

import '../stock.dart';

/// CSV field delimiter tuned for Excel on Windows (TR locale usually uses ';').
const String stockCsvDelimiter = ';';

/// Canonical internal CSV header keys for stock import/export.
const List<String> stockCsvHeaders = [
  'code',
  'name',
  'brand',
  'tax_rate',
  'sale_price_1',
  'sale_price_2',
  'sale_price_3',
  'sale_price_4',
  'quantity',
  'barcode',
  'pack_barcode',
  'box_barcode',
  'pack_qty',
  'box_qty',
  'group_name',
  'subgroup_name',
  'subsubgroup_name',
  'is_active',
  'image_path',
];

/// Turkish header titles for export; order matches [stockCsvHeaders].
const List<String> stockCsvHeadersTr = [
  'kod',
  'ad',
  'marka',
  'kdv_oran',
  'satis_fiyat_1',
  'satis_fiyat_2',
  'satis_fiyat_3',
  'satis_fiyat_4',
  'miktar',
  'barkod',
  'paket_barkod',
  'koli_barkod',
  'paket_ici_adet',
  'koli_ici_adet',
  'grup_ad',
  'ara_grup_ad',
  'alt_grup_ad',
  'aktif',
  'resim_yolu',
];

/// Header aliases (lowercased) mapping to canonical internal keys.
const Map<String, String> _headerAliases = {
  // English headers (canonical)
  'code': 'code',
  'name': 'name',
  'brand': 'brand',
  'tax_rate': 'tax_rate',
  'sale_price_1': 'sale_price_1',
  'sale_price_2': 'sale_price_2',
  'sale_price_3': 'sale_price_3',
  'sale_price_4': 'sale_price_4',
  'quantity': 'quantity',
  'barcode': 'barcode',
  'pack_barcode': 'pack_barcode',
  'box_barcode': 'box_barcode',
  'pack_qty': 'pack_qty',
  'box_qty': 'box_qty',
  'group_name': 'group_name',
  'subgroup_name': 'subgroup_name',
  'subsubgroup_name': 'subsubgroup_name',
  'is_active': 'is_active',
  'image_path': 'image_path',

  // Turkish headers
  'kod': 'code',
  'ad': 'name',
  'marka': 'brand',
  'kdv_oran': 'tax_rate',
  'satis_fiyat_1': 'sale_price_1',
  'satis_fiyat_2': 'sale_price_2',
  'satis_fiyat_3': 'sale_price_3',
  'satis_fiyat_4': 'sale_price_4',
  'miktar': 'quantity',
  'barkod': 'barcode',
  'paket_barkod': 'pack_barcode',
  'koli_barkod': 'box_barcode',
  'paket_ici_adet': 'pack_qty',
  'koli_ici_adet': 'box_qty',
  'kategori_id': 'category_id',
  'grup_ad': 'group_name',
  'ara_grup_ad': 'subgroup_name',
  'alt_grup_ad': 'subsubgroup_name',
  'aktif': 'is_active',
  'resim_yolu': 'image_path',

  // Excel price-update / movements sheet aliases
  // Stock code
  'stok kodu': 'stock_code',
  'stok_kodu': 'stock_code',
  'stokkodu': 'stock_code',
  'stock_code': 'stock_code',
  'stockcode': 'stock_code',

  // Note / description
  'note': 'note',
  'not': 'note',
  'aciklama': 'note',
  'açıklama': 'note',

  // Flexible price columns: map various aliases to sale_price_1..4
  // Price 1
  'price1': 'sale_price_1',
  'price 1': 'sale_price_1',
  'price_1': 'sale_price_1',
  'fiyat1': 'sale_price_1',
  'fiyat 1': 'sale_price_1',
  'fiyat_1': 'sale_price_1',
  'satisfiyat1': 'sale_price_1',
  'satis_fiyat1': 'sale_price_1',

  // Price 2
  'price2': 'sale_price_2',
  'price 2': 'sale_price_2',
  'price_2': 'sale_price_2',
  'fiyat2': 'sale_price_2',
  'fiyat 2': 'sale_price_2',
  'fiyat_2': 'sale_price_2',
  'satisfiyat2': 'sale_price_2',
  'satis_fiyat2': 'sale_price_2',

  // Price 3
  'price3': 'sale_price_3',
  'price 3': 'sale_price_3',
  'price_3': 'sale_price_3',
  'fiyat3': 'sale_price_3',
  'fiyat 3': 'sale_price_3',
  'fiyat_3': 'sale_price_3',
  'satisfiyat3': 'sale_price_3',
  'satis_fiyat3': 'sale_price_3',

  // Price 4
  'price4': 'sale_price_4',
  'price 4': 'sale_price_4',
  'price_4': 'sale_price_4',
  'fiyat4': 'sale_price_4',
  'fiyat 4': 'sale_price_4',
  'fiyat_4': 'sale_price_4',
  'satisfiyat4': 'sale_price_4',
  'satis_fiyat4': 'sale_price_4',
};

/// DTO used for CSV export, combining stock with optional pack/box quantities.
class StockExportRow {
  const StockExportRow({
    required this.stock,
    this.packQty,
    this.boxQty,
  });

  final Stock stock;
  final int? packQty;
  final int? boxQty;
}

/// Parse CSV content into a list of rows, each represented as
/// a map from column name to raw string value.
///
/// The first non-empty line is treated as header.
///
/// Import tarafı hem ';' hem de ',' ayırıcıyı destekler; ilk satırdaki
/// (header) ayırıcıya göre otomatik algılama yapılır. Metin içindeki
/// tırnaklar ve kaçışlar `_parseCsvLine` içerisinde doğru ele alınır.
List<Map<String, String>> parseCsv(String content) {
  final lines = const LineSplitter().convert(content);
  if (lines.isEmpty) return const [];

  // Skip leading empty lines.
  int headerIndex = 0;
  while (headerIndex < lines.length && lines[headerIndex].trim().isEmpty) {
    headerIndex++;
  }
  if (headerIndex >= lines.length) {
    return const [];
  }

  // Strip BOM if present from the first header line.
  final rawHeaderLine = lines[headerIndex].replaceFirst('\uFEFF', '');

  // Detect delimiter from header line (supports ';' or ',').
  final delimiter = _detectCsvDelimiter(rawHeaderLine);

  final rawHeader = _parseCsvLine(rawHeaderLine, delimiter);
  final header = rawHeader.map(_canonicalHeaderKey).toList();
  final List<Map<String, String>> rows = [];

  for (var i = headerIndex + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final values = _parseCsvLine(line, delimiter);
    final map = <String, String>{};
    for (var c = 0; c < header.length; c++) {
      final key = header[c];
      final value = c < values.length ? values[c] : '';
      map[key] = value;
    }
    rows.add(map);
  }

  return rows;
}

/// Convert a list of export rows to CSV string using the fixed header order.
///
/// Note: pack_qty and box_qty columns are left empty here because the
/// pack/case information lives in the separate stock_units table. They
/// can still be populated on import.
String stocksToCsv(List<StockExportRow> rows) {
  final buffer = StringBuffer();
  // Write UTF-8 BOM so that Excel detects encoding and delimiter correctly.
  buffer.write('\uFEFF');
  buffer.writeAll(stockCsvHeadersTr, stockCsvDelimiter);
  buffer.write('\r\n');

  for (final exportRow in rows) {
    final stock = exportRow.stock;
    final csvRow = <String?>[
      stock.code,
      stock.name,
      stock.brand,
      stock.taxRate.toString(),
      stock.salePrice1?.toString(),
      stock.salePrice2?.toString(),
      stock.salePrice3?.toString(),
      stock.salePrice4?.toString(),
      stock.quantity?.toString(),
      stock.barcode,
      stock.packBarcode,
      stock.boxBarcode,
      exportRow.packQty?.toString(), // pack_qty
      exportRow.boxQty?.toString(), // box_qty
      stock.groupName,
      stock.subgroupName,
      stock.subsubgroupName,
      stock.isActive.toString(),
      stock.imagePath,
    ];
    buffer.writeAll(csvRow.map(_escapeCsvField), stockCsvDelimiter);
    buffer.write('\r\n');
  }

  return buffer.toString();
}

/// Normalize empty strings to null.
String? nullIfEmpty(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Parse a localized numeric string (accepts both comma and dot).
DoubleOrNull parseNum(String? value) {
  if (value == null) return const DoubleOrNull(null);
  final trimmed = value.trim();
  if (trimmed.isEmpty) return const DoubleOrNull(null);
  final normalized = trimmed.replaceAll(',', '.');
  final parsed = double.tryParse(normalized);
  return DoubleOrNull(parsed);
}

class DoubleOrNull {
  const DoubleOrNull(this.value);
  final double? value;
}

/// Parse various truthy/falsy representations into bool.
bool? parseBoolFlexible(String? value) {
  if (value == null) return null;
  final v = value.trim().toLowerCase();
  if (v.isEmpty) return null;

  const truthy = {
    '1',
    'aktif',
    'evet',
    'yes',
    'y',
    'on',
  };
  const falsy = {
    '0',
    'false',
    'hayir',
    'hayır',
    'no',
    'n',
    'off',
  };

  if (truthy.contains(v)) return true;
  if (falsy.contains(v)) return false;
  return null;
}

bool isValidUuid(String? value) {
  if (value == null) return false;
  final v = value.trim();
  if (v.isEmpty) return false;
  final regex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}�?$',
  );
  return regex.hasMatch(v);
}

/// Detect CSV delimiter for a header line. Prefers ';' if it appears
/// more often than ',' outside of quoted segments. Falls back to the
/// default [stockCsvDelimiter] if no separator is clearly present.
String _detectCsvDelimiter(String line) {
  var inQuotes = false;
  var commaCount = 0;
  var semicolonCount = 0;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      // Basit toggle; header satırında iç içe tırnak beklenmiyor.
      inQuotes = !inQuotes;
    } else if (!inQuotes) {
      if (char == ',') {
        commaCount++;
      } else if (char == ';') {
        semicolonCount++;
      }
    }
  }

  if (semicolonCount == 0 && commaCount == 0) {
    return stockCsvDelimiter;
  }
  if (semicolonCount >= commaCount && semicolonCount > 0) {
    return ';';
  }
  return ',';
}

List<String> _parseCsvLine(String line, String delimiter) {
  final List<String> result = [];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        // Escaped quote
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == delimiter && !inQuotes) {
      result.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }

  result.add(buffer.toString());
  return result;
}

String _escapeCsvField(String? value) {
  if (value == null) return '';
  final needsQuoting = value.contains(stockCsvDelimiter) ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) {
    return value;
  }
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String _canonicalHeaderKey(String header) {
  final normalized = header.trim().toLowerCase();
  return _headerAliases[normalized] ?? header;
}
