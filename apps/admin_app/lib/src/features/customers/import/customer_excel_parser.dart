import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import 'customer_excel_schema.dart';
import 'customer_import_models.dart';

/// Isolate icinde calisacak parser fonksiyonu.
Future<List<Map<String, dynamic>>> parseCustomerExcelForIsolate(
  Uint8List bytes,
) async {
  final excel = Excel.decodeBytes(bytes);
  if (excel.tables.isEmpty) {
    return const <Map<String, dynamic>>[];
  }

  final sheet = excel.tables.values.first;
  if (sheet.maxRows == 0) {
    return const <Map<String, dynamic>>[];
  }

  // Ilk dolu satiri header olarak al.
  int headerRowIndex = 0;
  while (headerRowIndex < sheet.maxRows) {
    final row = sheet.row(headerRowIndex);
    final hasAny = row.any((c) => (c?.value.toString().trim().isNotEmpty ?? false));
    if (hasAny) break;
    headerRowIndex++;
  }

  if (headerRowIndex >= sheet.maxRows) {
    return const <Map<String, dynamic>>[];
  }

  final headerRow = sheet.row(headerRowIndex);
  final headers = <String>[];
  for (final cell in headerRow) {
    final text = cell?.value.toString() ?? '';
    headers.add(canonicalCustomerHeader(text));
  }

  final rows = <CustomerImportRow>[];

  const maxRows = 10000;
  var logicalIndex = 0;

  for (var r = headerRowIndex + 1; r < sheet.maxRows; r++) {
    if (rows.length >= maxRows) break;
    final row = sheet.row(r);
    final map = <String, String>{};

    var isCompletelyEmpty = true;
    for (var c = 0; c < headers.length; c++) {
      final key = headers[c];
      if (key.isEmpty) continue;
      final cell = c < row.length ? row[c] : null;
      final raw = cell?.value?.toString() ?? '';
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        isCompletelyEmpty = false;
      }
      map[key] = trimmed;
    }

    if (isCompletelyEmpty) {
      continue;
    }

    logicalIndex++;
    final localIssues = _validateAndNormalize(map);

    rows.add(
      CustomerImportRow(
        index: logicalIndex,
        values: map,
        localIssues: localIssues,
      ),
    );
  }

  return rows.map((e) => e.toJson()).toList();
}

/// UI isolate tarafinda kullanisli wrapper.
Future<List<CustomerImportRow>> parseCustomerExcel(Uint8List bytes) async {
  final json = await compute(parseCustomerExcelForIsolate, bytes);
  return json.map(CustomerImportRow.fromJson).toList();
}

List<String> _validateAndNormalize(Map<String, String> values) {
  final issues = <String>[];

  String normalizeDigits(String input) {
    final buffer = StringBuffer();
    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }

  String? normalizePhone(String raw) {
    if (raw.isEmpty) return null;
    var text = raw.trim();
    if (text.startsWith('="') && text.endsWith('"')) {
      text = text.substring(2, text.length - 1);
    }
    final digits = normalizeDigits(text);
    if (digits.isEmpty) return null;
    if (digits.length < 10 || digits.length > 13) {
      issues.add('Telefon 10-13 haneli olmalı');
    }
    return digits;
  }

  String? normalizeTaxNo(String raw) {
    if (raw.isEmpty) return null;
    final digits = normalizeDigits(raw);
    if (digits.isEmpty) return null;
    if (digits.length != 10 && digits.length != 11) {
      issues.add('Vergi No / TCKN 10 veya 11 haneli olmalı');
    }
    return digits;
  }

  double? parseMoney(String raw) {
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll('.', '').replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) {
      issues.add('Para alanı sayısal olmalı');
      return null;
    }
    if (value < 0) {
      issues.add('Para alanı negatif olamaz');
    }
    return value;
  }

  int? parseInt(String raw) {
    if (raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null) {
      issues.add('Tam sayı alanı sayısal olmalı');
    }
    return value;
  }

  bool? parseBoolFlexible(String raw) {
    if (raw.isEmpty) return null;
    final v = raw.trim().toLowerCase();
    const truthy = {
      '1',
      'true',
      'evet',
      'aktif',
      'yes',
      'y',
      'on',
    };
    const falsy = {
      '0',
      'false',
      'hayir',
      'hayır',
      'pasif',
      'no',
      'n',
      'off',
    };
    if (truthy.contains(v)) return true;
    if (falsy.contains(v)) return false;
    return null;
  }

  String? normalizeCustomerType(String raw) {
    if (raw.isEmpty) return null;
    final v = raw.trim().toLowerCase();
    if (v.startsWith('ticari')) return 'commercial';
    if (v.startsWith('bireysel')) return 'individual';
    issues.add('Cari türü sadece Ticari veya Bireysel olmalı');
    return null;
  }

  // Zorunlu alanlar ve normalizasyon.
  final tradeTitle = values[CustomerExcelFields.tradeTitle] ?? '';
  final customerTypeRaw = values[CustomerExcelFields.customerType] ?? '';
  final phoneRaw = values[CustomerExcelFields.phone] ?? '';

  final normalizedCustomerType = normalizeCustomerType(customerTypeRaw);
  if (normalizedCustomerType == null) {
    issues.add('Cari Türü (Ticari/Bireysel) zorunludur');
  }

  if (tradeTitle.trim().length < 2) {
    issues.add('Ticari Ünvan en az 2 karakter olmalı');
  }

  final normalizedPhone = normalizePhone(phoneRaw);
  if (normalizedPhone == null) {
    issues.add('Telefon zorunludur');
  }

  final taxNoRaw = values[CustomerExcelFields.taxNo] ?? '';
  final normalizedTaxNo = normalizeTaxNo(taxNoRaw);

  final limitRaw = values[CustomerExcelFields.limitAmount] ?? '';
  final limitAmount = parseMoney(limitRaw) ?? 0;

  final dueDaysRaw = values[CustomerExcelFields.dueDays] ?? '';
  final dueDays = parseInt(dueDaysRaw);

  final warnRaw = values[CustomerExcelFields.warnOnLimitExceeded] ?? '';
  final warn = parseBoolFlexible(warnRaw);

  final activeRaw = values[CustomerExcelFields.isActive] ?? '';
  final isActive = parseBoolFlexible(activeRaw);

  // Normalize degerleri map'e geri yaz (backend'e daha temiz gondermek icin).
  if (normalizedCustomerType != null) {
    values[CustomerExcelFields.customerType] = normalizedCustomerType;
  }
  if (normalizedPhone != null) {
    values[CustomerExcelFields.phone] = normalizedPhone;
  }
  if (normalizedTaxNo != null) {
    values[CustomerExcelFields.taxNo] = normalizedTaxNo;
  }
  values[CustomerExcelFields.limitAmount] = limitAmount.toString();
  if (dueDays != null) {
    values[CustomerExcelFields.dueDays] = dueDays.toString();
  }
  if (warn != null) {
    values[CustomerExcelFields.warnOnLimitExceeded] = warn.toString();
  }
  if (isActive != null) {
    values[CustomerExcelFields.isActive] = isActive.toString();
  }

  // Etiketleri normalize et (virgülle ayrılmış).
  final rawTags = values[CustomerExcelFields.tagsCsv] ?? '';
  if (rawTags.isNotEmpty) {
    final tags = rawTags
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    values[CustomerExcelFields.tagsCsv] = tags.join(', ');
  }

  return issues;
}
