import 'dart:convert';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'stock_import_export_download_stub.dart'
  if (dart.library.html) 'stock_import_export_download_web.dart'
  as download_helper;

// ignore_for_file: deprecated_member_use, unused_element

final _movementStockSearchProvider = StateProvider<String>((ref) => '');
final _movementStockPageProvider = StateProvider<int>((ref) => 0);

final _movementStocksFutureProvider =
    FutureProvider.autoDispose<List<Stock>>((ref) async {
  final search = ref.watch(_movementStockSearchProvider);
  final page = ref.watch(_movementStockPageProvider);

  return stockRepository.fetchStocks(
    page: page,
    pageSize: 20,
    search: search.trim().isEmpty ? null : search.trim(),
    isActive: true,
  );
});

final _stockMovementsProvider =
    FutureProvider.autoDispose.family<List<StockMovement>, String>((ref, stockId) async {
  return stockMovementRepository.fetchMovements(
    stockId: stockId,
    page: 0,
    pageSize: 50,
  );
});

class StockMovementsPage extends ConsumerStatefulWidget {
  const StockMovementsPage({super.key});

  @override
  ConsumerState<StockMovementsPage> createState() => _StockMovementsPageState();
}

class _StockMovementsPageState extends ConsumerState<StockMovementsPage> {
  String? _selectedStockId;
  String? _selectedStockLabel;
  bool _excelTemplateExporting = false;
  bool _excelImporting = false;
  String _dateFilter = '7d'; // 7d, 30d, all

  _KpiMetrics _kpiMetrics = const _KpiMetrics();

  String _formatDate(DateTime dt) {
    return DateFormat('dd.MM.yyyy', 'tr_TR').format(dt);
  }

  double? _parseDouble(String text) {
    final raw = text.trim();
    if (raw.isEmpty) return null;

    // TR ve EN formatlarına dayanıklı sayısal parse:
    //  - "1.250,50"  -> 1250.50
    //  - "1250,50"   -> 1250.50
    //  - "1,250.50"  -> 1250.50
    //  - "1250.50"   -> 1250.50
    var normalized = raw.replaceAll(' ', '');
    final lastDot = normalized.lastIndexOf('.');
    final lastComma = normalized.lastIndexOf(',');

    if (lastDot == -1 && lastComma == -1) {
      return double.tryParse(normalized);
    }

    // En sondaki ayırıcıyı ondalık, diğerini binlik kabul et.
    late String decimalSep;
    late String thousandSep;
    if (lastDot > lastComma) {
      decimalSep = '.';
      thousandSep = ',';
    } else {
      decimalSep = ',';
      thousandSep = '.';
    }

    normalized = normalized.replaceAll(thousandSep, '');
    normalized = normalized.replaceAll(decimalSep, '.');
    return double.tryParse(normalized);
  }

  Future<void> _exportExcelTemplateCsv() async {
    setState(() {
      _excelTemplateExporting = true;
    });

    final messenger = ScaffoldMessenger.of(context);

    try {
      final rows = await stockRepository.fetchAllStocksForExport();
      final buffer = StringBuffer();
      buffer.write('\uFEFF');
      buffer.writeAll(
        const [
          'Stok Kodu',
          'Stok Adı',
          'Grup Adı',
          'Alt Grup Adı',
          'Alt Alt Grup Adı',
          'Not',
          'Fiyat 1',
          'Fiyat 2',
          'Fiyat 3',
          'Fiyat 4',
        ],
        stockCsvDelimiter,
      );
      buffer.write('\r\n');

      String escText(String? value) {
        final v = (value ?? '').replaceAll('"', '""');
        return '"$v"';
      }

      // Gruplara göre sıralama: group_name, subgroup_name, subsubgroup_name, name, code
      rows.sort((a, b) {
        final sa = a.stock;
        final sb = b.stock;

        int cmp(String? x, String? y) => (x ?? '').compareTo(y ?? '');

        var r = cmp(sa.groupName, sb.groupName);
        if (r != 0) return r;
        r = cmp(sa.subgroupName, sb.subgroupName);
        if (r != 0) return r;
        r = cmp(sa.subsubgroupName, sb.subsubgroupName);
        if (r != 0) return r;
        r = cmp(sa.name, sb.name);
        if (r != 0) return r;
        return cmp(sa.code, sb.code);
      });

      for (final row in rows) {
        final stock = row.stock;
        // Tercihen aktif stokları şablona dahil et.
        if (stock.isActive != true) continue;
        final code = stock.code;
        final name = stock.name;
        final groupName = stock.groupName ?? '';
        final subgroupName = stock.subgroupName ?? '';
        final subsubgroupName = stock.subsubgroupName ?? '';
        final p1 = stock.salePrice1?.toString() ?? '';
        final p2 = stock.salePrice2?.toString() ?? '';
        final p3 = stock.salePrice3?.toString() ?? '';
        final p4 = stock.salePrice4?.toString() ?? '';
        // Metin alanları (stock_code, stock_name, group_name, subgroup_name, subsubgroup_name, note) tırnaklanır ve tırnak işaretleri escape edilir.
        buffer.writeAll(
          [
            escText(code),
            escText(name),
            escText(groupName),
            escText(subgroupName),
            escText(subsubgroupName),
            escText(''),
            p1,
            p2,
            p3,
            p4,
          ],
          stockCsvDelimiter,
        );
        buffer.write('\r\n');
      }

      final csv = buffer.toString();

      Uint8List? buildXlsxBytes() {
        final excel = xls.Excel.createExcel();
        final sheet = excel.sheets[excel.getDefaultSheet()]!;

        List<xls.CellValue?> textRow(Iterable<dynamic> values) {
          return values
              .map<xls.CellValue?>(
                (v) => xls.TextCellValue((v ?? '').toString()),
              )
              .toList(growable: false);
        }

        const headers = [
          'Stok Kodu',
          'Stok Adı',
          'Grup Adı',
          'Alt Grup Adı',
          'Alt Alt Grup Adı',
          'Not',
          'Fiyat 1',
          'Fiyat 2',
          'Fiyat 3',
          'Fiyat 4',
        ];

        sheet.appendRow(textRow(headers));

        for (final row in rows) {
          final stock = row.stock;
          if (stock.isActive != true) continue;
          sheet.appendRow(
            textRow([
              stock.code,
              stock.name,
              stock.groupName ?? '',
              stock.subgroupName ?? '',
              stock.subsubgroupName ?? '',
              '',
              stock.salePrice1?.toString() ?? '',
              stock.salePrice2?.toString() ?? '',
              stock.salePrice3?.toString() ?? '',
              stock.salePrice4?.toString() ?? '',
            ]),
          );
        }

        // Header style (minimal, consistent).
        for (var col = 0; col < headers.length; col++) {
          final cell = sheet.cell(
            xls.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
          );
          cell.cellStyle = xls.CellStyle(bold: true);
        }

        final bytes = excel.encode();
        if (bytes == null) return null;
        return Uint8List.fromList(bytes);
      }

      final now = DateTime.now();
      final ts =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final csvFileName = 'Stok Excel Fiyat Güncel Şablonu $ts.csv';
      final excelFileName = 'Stok Excel Fiyat Güncel Şablonu $ts.xlsx';
      final xlsxBytes = buildXlsxBytes();

      if (kIsWeb) {
        if (xlsxBytes == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Excel dosyası oluşturulamadı.')),
          );
          return;
        }

        final ok = await download_helper.saveBytesFile(
          excelFileName,
          xlsxBytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        if (ok) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Excel şablonu indiriliyor.')),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Dosya indirilemedi.',
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final maxHeight = MediaQuery.sizeOf(dialogContext).height * 0.6;
            return AlertDialog(
              title: const Text('CSV Önizleme'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      csvFileName,
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: maxHeight,
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SelectableText(csv),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: csv));
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('CSV kopyalandı.')),
                    );
                  },
                  child: const Text('Kopyala'),
                ),
                TextButton(
                  onPressed: () async {
                    if (xlsxBytes == null) {
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Excel dosyası oluşturulamadı.'),
                        ),
                      );
                      return;
                    }

                    final ok = await download_helper.saveBytesFile(
                      excelFileName,
                      xlsxBytes,
                      mimeType:
                          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    );
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Excel/Sheets açılıyor…'
                              : 'Dosya açılamadı. Excel/Sheets yüklü olmayabilir.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Excel\'de Aç'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Kapat'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Excel şablonu oluşturma hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _excelTemplateExporting = false;
        });
      }
    }
  }

  Future<void> _importExcelFromCsv() async {
    setState(() {
      _excelImporting = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    NavigatorState? progressNavigator;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      if (file.bytes == null) {
        throw Exception('Dosya içeriği okunamadı.');
      }

      final content = utf8.decode(file.bytes!);
      if (kDebugMode) {
        debugPrint(
          '[ExcelImport] Picked file name=${file.name} bytes=${file.bytes!.length}',
        );
      }

      // Ham ilk 2-3 satırı logla
      final rawLines = const LineSplitter().convert(content);
      for (var i = 0; i < rawLines.length && i < 3; i++) {
        if (kDebugMode) {
          debugPrint('[ExcelImport] line${i + 1}: ${rawLines[i]}');
        }
      }

      // Header satırından ayırıcı ve kolon isimlerini kaba şekilde tespit et
      String? detectedDelimiter;
      String? rawHeaderLine;
      for (final line in rawLines) {
        if (line.trim().isEmpty) continue;
        rawHeaderLine = line.replaceFirst('\uFEFF', '');
        break;
      }
      if (rawHeaderLine != null) {
        var inQuotes = false;
        var commaCount = 0;
        var semicolonCount = 0;
        for (var i = 0; i < rawHeaderLine.length; i++) {
          final ch = rawHeaderLine[i];
          if (ch == '"') {
            inQuotes = !inQuotes;
          } else if (!inQuotes) {
            if (ch == ',') commaCount++;
            if (ch == ';') semicolonCount++;
          }
        }
        if (semicolonCount == 0 && commaCount == 0) {
          detectedDelimiter = stockCsvDelimiter;
        } else if (semicolonCount >= commaCount && semicolonCount > 0) {
          detectedDelimiter = ';';
        } else {
          detectedDelimiter = ',';
        }
        if (kDebugMode) {
          debugPrint(
            '[ExcelImport] Detected delimiter="$detectedDelimiter" from header',
          );
        }

        // Basit split ile ham header kolonlarını logla (debug amaçlı)
        final headerParts = rawHeaderLine.split(detectedDelimiter);
        final headerTrimmed =
            headerParts.map((e) => e.trim()).toList(growable: false);
        if (kDebugMode) {
          debugPrint(
            '[ExcelImport] Raw header columns: $headerTrimmed',
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint('[ExcelImport] No non-empty header line found in CSV');
        }
      }

      final rows = parseCsv(content);
      if (rows.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[ExcelImport] Parsed header keys (canonical): '
            '${rows.first.keys.toList(growable: false)}',
          );
        }
      }
      if (rows.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('CSV dosyası boş görünüyor.')),
        );
        return;
      }

      final parsedRows = <_ExcelImportRow>[];
      var emptyRowCount = 0;
      var lineNumber = 2; // header 1

        for (final row in rows) {
        // stock_code alanı yoksa code üzerinden de dene.
        final code = (row['stock_code'] ?? row['code'] ?? '').trim();
        final noteStr = (row['note'] ?? row['not'] ?? '').trim();
        // sale_price_* kolonları yoksa price_* alias'larını da kabul et.
        final p1Str =
          (row['sale_price_1'] ?? row['price_1'] ?? '').trim();
        final p2Str =
          (row['sale_price_2'] ?? row['price_2'] ?? '').trim();
        final p3Str =
          (row['sale_price_3'] ?? row['price_3'] ?? '').trim();
        final p4Str =
          (row['sale_price_4'] ?? row['price_4'] ?? '').trim();

        final allEmpty = code.isEmpty &&
            noteStr.isEmpty &&
            p1Str.isEmpty &&
            p2Str.isEmpty &&
            p3Str.isEmpty &&
            p4Str.isEmpty;

        if (allEmpty) {
          emptyRowCount++;
          lineNumber++;
          continue;
        }

        String? error;
        double? p1;
        double? p2;
        double? p3;
        double? p4;

        if (code.isEmpty) {
          error = 'stock_code zorunlu';
        }

        void parsePrice(String key, String valueStr, void Function(double value) assign) {
          if (valueStr.isEmpty) {
            return;
          }
          final parsed = _parseDouble(valueStr);
          if (parsed == null || parsed < 0) {
            error = (error == null)
                ? '$key >= 0 olmalıdır'
                : '$error, $key >= 0 olmalıdır';
          } else {
            assign(parsed);
          }
        }

        parsePrice('price_1', p1Str, (v) => p1 = v);
        parsePrice('price_2', p2Str, (v) => p2 = v);
        parsePrice('price_3', p3Str, (v) => p3 = v);
        parsePrice('price_4', p4Str, (v) => p4 = v);

        parsedRows.add(
          _ExcelImportRow(
            rowNumber: lineNumber,
            stockCode: code,
            note: noteStr.isEmpty ? null : noteStr,
            price1: p1,
            price2: p2,
            price3: p3,
            price4: p4,
            error: error,
          ),
        );
        lineNumber++;
      }

      final totalRows = emptyRowCount + parsedRows.length;

      final codes = parsedRows
          .where((r) => r.stockCode.isNotEmpty)
          .map((r) => r.stockCode)
          .toSet()
          .toList(growable: false);

      final stocks = await stockRepository.fetchStocksByCodes(codes);
      final byCode = <String, Stock>{
        for (final s in stocks) s.code: s,
      };

      for (final row in parsedRows) {
        if (row.error != null) continue;

        final stock = byCode[row.stockCode];
        if (stock == null) {
          row.error = 'stock_code için stok bulunamadı';
          continue;
        }

        row.oldPrice1 = stock.salePrice1;
        row.oldPrice2 = stock.salePrice2;
        row.oldPrice3 = stock.salePrice3;
        row.oldPrice4 = stock.salePrice4;

        final new1 = row.price1 ?? stock.salePrice1;
        final new2 = row.price2 ?? stock.salePrice2;
        final new3 = row.price3 ?? stock.salePrice3;
        final new4 = row.price4 ?? stock.salePrice4;

        row.newPrice1 = new1;
        row.newPrice2 = new2;
        row.newPrice3 = new3;
        row.newPrice4 = new4;

        bool priceChanged = false;
        if (row.price1 != null && new1 != stock.salePrice1) {
          priceChanged = true;
        }
        if (row.price2 != null && new2 != stock.salePrice2) {
          priceChanged = true;
        }
        if (row.price3 != null && new3 != stock.salePrice3) {
          priceChanged = true;
        }
        if (row.price4 != null && new4 != stock.salePrice4) {
          priceChanged = true;
        }

        row.hasPriceChange = priceChanged;
      }

      // Debug: ilk 5 satır için özet log
      for (var i = 0; i < parsedRows.length && i < 5; i++) {
        final r = parsedRows[i];
        if (kDebugMode) {
          debugPrint(
            '[ExcelImport] Row#${r.rowNumber} code=${r.stockCode} '
            'p1=${r.price1} p2=${r.price2} p3=${r.price3} p4=${r.price4} '
            'old=(${r.oldPrice1}, ${r.oldPrice2}, ${r.oldPrice3}, ${r.oldPrice4}) '
            'new=(${r.newPrice1}, ${r.newPrice2}, ${r.newPrice3}, ${r.newPrice4}) '
            'hasPriceChange=${r.hasPriceChange} error=${r.error}',
          );
        }
      }

      final formatErrorRows = parsedRows
          .where((r) =>
              r.error != null && !(r.error ?? '').contains('stok bulunamadı'))
          .toList(growable: false);
      final notFoundRows = parsedRows
          .where((r) => (r.error ?? '').contains('stok bulunamadı'))
          .toList(growable: false);
      final missingCodes = notFoundRows
          .map((r) => r.stockCode)
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();

      final priceRows = parsedRows
          .where((r) => r.error == null && r.hasPriceChange)
          .toList(growable: false);

        final priceInputRows = parsedRows
          .where((r) =>
            r.price1 != null ||
            r.price2 != null ||
            r.price3 != null ||
            r.price4 != null)
          .toList(growable: false);

      if (kDebugMode) {
        debugPrint(
        '[ExcelImport] totalParsed=${parsedRows.length} '
        'emptyRows=$emptyRowCount '
        'priceInputRows=${priceInputRows.length} '
        'priceChangeRows=${priceRows.length} '
        'formatErrors=${formatErrorRows.length} '
        'notFound=${notFoundRows.length}',
        );
      }

      if (priceRows.isEmpty) {
        final headerKeys = rows.isNotEmpty
            ? rows.first.keys.toList(growable: false)
            : const <String>[];

        if (kDebugMode) {
          debugPrint(
            '[ExcelImport] No price change rows. headerKeys=$headerKeys',
          );
        }

        final hasAnyPriceHeader = headerKeys.any(
          (k) =>
              k == 'sale_price_1' ||
              k == 'sale_price_2' ||
              k == 'sale_price_3' ||
              k == 'sale_price_4' ||
              k == 'price_1' ||
              k == 'price_2' ||
              k == 'price_3' ||
              k == 'price_4',
        );

        if (!hasAnyPriceHeader) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'CSV’de fiyat kolonları okunamadı. Bulunan kolonlar: '
                '${headerKeys.join(', ')}. '
                'Beklenen en az: stock_code/code ve sale_price_1..4 veya Fiyat 1..4. '
                'Dosya ayırıcı olarak genellikle ";" (noktalı virgül) kullanılmalıdır.',
              ),
            ),
          );
        } else if (priceInputRows.isEmpty) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'CSV’de fiyat alanları boş veya sayı formatı hatalı. '
                'Örnek formatlar: 1250,50 · 1.250,50 · 1,250.50',
              ),
            ),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Satırlardaki fiyatlar mevcut fiyatlarla aynı; uygulanacak değişiklik bulunamadı.',
              ),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

        final previewRows = parsedRows
          .where((r) => r.error == null && r.hasPriceChange)
          .toList(growable: false);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          const priceColor = Colors.green;
          return AlertDialog(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Excel İçe Aktarma Özeti'),
                const SizedBox(height: 4),
                Text(
                  'Bu Excel dosyası satış fiyatlarını toplu olarak güncelleyecektir.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Toplam satır: $totalRows'),
                  Text('Boş satır (atlanmış): $emptyRowCount'),
                  Text('Format hatası: ${formatErrorRows.length}'),
                  Text('Stok bulunamadı: ${notFoundRows.length}'),
                  const SizedBox(height: 12),
                  Text(
                    '💰 Fiyat Güncellemeleri',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Fiyat güncellenecek satır: ${priceRows.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (missingCodes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Stok bulunamayan kodlar (${missingCodes.length}):',
                      style: Theme.of(dialogContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        itemCount: missingCodes.length,
                        itemBuilder: (context, index) {
                          return Text(missingCodes[index]);
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          final text = missingCodes.join('\n');
                          Clipboard.setData(ClipboardData(text: text));
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Stok bulunamayan kodlar panoya kopyalandı.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Kodları panoya kopyala'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Örnek değişiklikler (ilk 10):',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      itemCount:
                          previewRows.length > 10 ? 10 : previewRows.length,
                      itemBuilder: (context, index) {
                        final r = previewRows[index];
                        return ListTile(
                          dense: true,
                          title: Text(r.stockCode),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (r.hasPriceChange) ...[
                                Text(
                                  'Fiyat değişiklikleri:',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (r.price1 != null &&
                                    r.newPrice1 != r.oldPrice1)
                                  Text(
                                    'Fiyat 1: ${r.oldPrice1} -> ${r.newPrice1}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: priceColor,
                                    ),
                                  ),
                                if (r.price2 != null &&
                                    r.newPrice2 != r.oldPrice2)
                                  Text(
                                    'Fiyat 2: ${r.oldPrice2} -> ${r.newPrice2}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: priceColor,
                                    ),
                                  ),
                                if (r.price3 != null &&
                                    r.newPrice3 != r.oldPrice3)
                                  Text(
                                    'Fiyat 3: ${r.oldPrice3} -> ${r.newPrice3}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: priceColor,
                                    ),
                                  ),
                                if (r.price4 != null &&
                                    r.newPrice4 != r.oldPrice4)
                                  Text(
                                    'Fiyat 4: ${r.oldPrice4} -> ${r.newPrice4}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: priceColor,
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'UYARI: Bu işlem geri alınamaz.',
                    style: Theme.of(dialogContext)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Vazgeç'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('İşlemleri Uygula'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      if (!mounted) return;

      progressNavigator = Navigator.of(context);
      // İşlemler sürerken kullanıcıya bekleme diyaloğu göster.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return const AlertDialog(
            content: SizedBox(
              height: 80,
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        },
      );

      int priceSuccess = 0;
      int priceFailed = 0;

      // Ardından fiyat güncellemelerini uygula
      for (final r in priceRows) {
        final stock = byCode[r.stockCode];
        if (stock == null) {
          priceFailed++;
          continue;
        }

        final updated = stock.copyWith(
          salePrice1: r.newPrice1,
          salePrice2: r.newPrice2,
          salePrice3: r.newPrice3,
          salePrice4: r.newPrice4,
        );

        try {
          // Debug: Excel import satırına karşılık gelen stok ve yeni fiyatlar
          if (kDebugMode) {
            debugPrint(
              '[ExcelImport] Updating stock id=${stock.id} code=${stock.code} '
              'oldPrices=(${stock.salePrice1}, ${stock.salePrice2}, ${stock.salePrice3}, ${stock.salePrice4}) '
              'newPrices=(${r.newPrice1}, ${r.newPrice2}, ${r.newPrice3}, ${r.newPrice4})',
            );
          }

          await stockRepository.updateStock(stock: updated);
          priceSuccess++;
        } catch (_) {
          priceFailed++;
        }
      }

      progressNavigator.pop();
      progressNavigator = null;

      // Import sonrası stok listesini ve hareketler provider'ını tazele.
      // 1) Stok listesini (chips) refresh et.
      if (kDebugMode) {
        debugPrint(
          '[ExcelImport] Invalidating _movementStocksFutureProvider after import',
        );
      }
      ref.invalidate(_movementStocksFutureProvider);

      final previousSelectedId = _selectedStockId;

      // 2) Eğer önceden seçili stok yoksa, güncel listeden ilk stoğu otomatik seç.
      if (previousSelectedId == null) {
        try {
          final refreshedStocks = await ref.read(_movementStocksFutureProvider.future);
          if (kDebugMode) {
            debugPrint(
              '[ExcelImport] Refetched stocks after import. count=${refreshedStocks.length}',
            );
          }
          if (refreshedStocks.isNotEmpty && mounted) {
            final first = refreshedStocks.first;
            setState(() {
              _selectedStockId = first.id;
              _selectedStockLabel = '${first.code} - ${first.name}';
            });
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[ExcelImport] Error while auto-selecting first stock after import: $e',
            );
          }
        }
      }

      final effectiveSelectedId = _selectedStockId;
      if (kDebugMode) {
        debugPrint(
          '[ExcelImport] Import summary: selectedStockId=$effectiveSelectedId '
          'priceSuccess=$priceSuccess priceFailed=$priceFailed '
          'notFound=${notFoundRows.length} formatErrors=${formatErrorRows.length}',
        );
      }

      // 3) Seçili stok için hareket listesini (fiyat geçmişi) yeniden fetch et.
      if (effectiveSelectedId != null) {
        if (kDebugMode) {
          debugPrint(
            '[ExcelImport] Invalidating _stockMovementsProvider for stockId=$effectiveSelectedId',
          );
        }
        ref.invalidate(_stockMovementsProvider(effectiveSelectedId));
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Fiyat: $priceSuccess başarılı, $priceFailed hata | Bulunamadı: ${notFoundRows.length} | Format hata: ${formatErrorRows.length}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Excel içe aktarma hatası: $e')),
      );
    } finally {
      // Hata olsa bile bekleme diyaloğu mutlaka kapansın.
      final navigator = progressNavigator;
      if (navigator != null && navigator.mounted) {
        navigator.pop();
      }
      if (mounted) {
        setState(() {
          _excelImporting = false;
        });
      }
    }
  }

  Future<void> _showUpdatePriceSheet(String stockId) async {
    final messenger = ScaffoldMessenger.of(context);

    Stock stock;
    try {
      stock = await stockRepository.getStock(stockId);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Stok bilgisi alınamadı: $e')),
      );
      return;
    }

    if (!mounted) return;

    final price1Controller = TextEditingController(
      text: stock.salePrice1?.toString() ?? '',
    );
    final price2Controller = TextEditingController(
      text: stock.salePrice2?.toString() ?? '',
    );
    final price3Controller = TextEditingController(
      text: stock.salePrice3?.toString() ?? '',
    );
    final price4Controller = TextEditingController(
      text: stock.salePrice4?.toString() ?? '',
    );

    bool isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: bottomInset + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> handleSave() async {
                if (isSaving) return;
                setModalState(() {
                  isSaving = true;
                });

                double? parsePrice(String text) {
                  if (text.trim().isEmpty) return null;
                  return _parseDouble(text.trim());
                }

                try {
                  final p1 = parsePrice(price1Controller.text);
                  if (p1 == null) {
                    throw Exception('Fiyat-1 zorunludur ve sayı olmalıdır.');
                  }
                  if (p1 < 0) {
                    throw Exception('Fiyat-1 0 veya daha büyük olmalıdır.');
                  }

                  final p2 = parsePrice(price2Controller.text);
                  final p3 = parsePrice(price3Controller.text);
                  final p4 = parsePrice(price4Controller.text);

                  if (p2 != null && p2 < 0) {
                    throw Exception('Fiyat-2 0 veya daha büyük olmalıdır.');
                  }
                  if (p3 != null && p3 < 0) {
                    throw Exception('Fiyat-3 0 veya daha büyük olmalıdır.');
                  }
                  if (p4 != null && p4 < 0) {
                    throw Exception('Fiyat-4 0 veya daha büyük olmalıdır.');
                  }

                  final new1 = p1;
                  final new2 = p2 ?? stock.salePrice2;
                  final new3 = p3 ?? stock.salePrice3;
                  final new4 = p4 ?? stock.salePrice4;

                  final updated = stock.copyWith(
                    salePrice1: new1,
                    salePrice2: new2,
                    salePrice3: new3,
                    salePrice4: new4,
                  );

                  try {
                    await stockRepository.updateStock(stock: updated);
                  } catch (e) {
                    final message = e.toString().toLowerCase();
                    if (message.contains('forbidden') ||
                        message.contains('permission denied') ||
                        message.contains('policy')) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Yetkiniz yok (forbidden). Policy engelledi.',
                          ),
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Fiyat güncellenemedi: $e'),
                        ),
                      );
                    }
                    return;
                  }

                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Fiyatlar güncellendi.')),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                } finally {
                  setModalState(() {
                    isSaving = false;
                  });
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fiyat Güncelle',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Boş bırakılan fiyatlar değişmez.',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: price1Controller,
                    decoration: const InputDecoration(
                      labelText: 'Fiyat-1 *',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price2Controller,
                    decoration: const InputDecoration(
                      labelText: 'Fiyat-2 (opsiyonel)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price3Controller,
                    decoration: const InputDecoration(
                      labelText: 'Fiyat-3 (opsiyonel)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: price4Controller,
                    decoration: const InputDecoration(
                      labelText: 'Fiyat-4 (opsiyonel)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () {
                                Navigator.of(sheetContext).pop();
                              },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        child: const Text('Vazgeç'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                        ),
                        onPressed: isSaving ? null : handleSave,
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Kaydet'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final stocksAsync = ref.watch(_movementStocksFutureProvider);
    final page = ref.watch(_movementStockPageProvider);

    return AppScaffold(
      title: 'Fiyat Yönetimi',
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          final isNarrow = constraints.maxWidth < 520;
          final padding = EdgeInsets.all(isWide ? 24 : 12);

          Widget buildExcelCard() {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: isNarrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Excel ile Fiyat Güncelle',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Bu Excel dosyası sadece fiyatları günceller. Ürün ekleme/silme için “Excel Master” ekranını kullanın.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                                onPressed: _excelTemplateExporting
                                    ? null
                                    : _exportExcelTemplateCsv,
                                icon: _excelTemplateExporting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download),
                                label: const Text('Şablon İndir'),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                                onPressed: _excelImporting
                                    ? null
                                    : _importExcelFromCsv,
                                icon: _excelImporting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.upload_file),
                                label: const Text('Excel İçe Aktar'),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Excel ile Fiyat Güncelle',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Bu Excel dosyası sadece fiyatları günceller. Ürün ekleme/silme için “Excel Master” ekranını kullanın.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                                onPressed: _excelTemplateExporting
                                    ? null
                                    : _exportExcelTemplateCsv,
                                icon: _excelTemplateExporting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.download),
                                label: const Text('Şablon İndir'),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                ),
                                onPressed: _excelImporting
                                    ? null
                                    : _importExcelFromCsv,
                                icon: _excelImporting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.upload_file),
                                label: const Text('Excel İçe Aktar'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            );
          }

          Widget buildHeroCard() {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: 'Stok ara',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (value) {
                              ref
                                  .read(_movementStockSearchProvider.notifier)
                                  .state = value;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('Sayfa: ${page + 1}'),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: page > 0
                              ? () {
                                  ref
                                      .read(_movementStockPageProvider
                                          .notifier)
                                      .state = page - 1;
                                }
                              : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () {
                            ref
                                .read(_movementStockPageProvider.notifier)
                                .state = page + 1;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      child: stocksAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (e, _) => const Center(
                          child: Text('Stoklar yüklenemedi.'),
                        ),
                        data: (stocks) {
                          if (stocks.isEmpty) {
                            return const Center(
                              child: Text('Kayıt bulunamadı.'),
                            );
                          }
                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: stocks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final stock = stocks[index];
                              final isSelected = stock.id != null &&
                                  stock.id == _selectedStockId;
                              return ChoiceChip(
                                label: Text(
                                  '${stock.code} - ${stock.name}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                selected: isSelected,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedStockId = stock.id;
                                    _selectedStockLabel =
                                        '${stock.code} - ${stock.name}';
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedStockId == null)
                      const Text('Henüz stok seçilmedi. Yukarıdan bir stok seçin.')
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (_selectedStockLabel != null)
                            Chip(
                              label: Text(
                                'Seçili: $_selectedStockLabel',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isWide)
                      SizedBox(
                        height: math.min(
                          360.0,
                          math.max(220.0, constraints.maxHeight * 0.55),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              isNarrow
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Fiyat Yönetimi',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          'Bir stok seçin, fiyatları güncelleyin. Yapılan her güncelleme fiyat geçmişine otomatik kaydedilir.',
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              style:
                                                  ElevatedButton.styleFrom(
                                                minimumSize:
                                                    const Size(0, 40),
                                              ),
                                              onPressed:
                                                  _selectedStockId == null
                                                      ? null
                                                      : () =>
                                                          _showUpdatePriceSheet(
                                                            _selectedStockId!,
                                                          ),
                                              icon: const Icon(
                                                  Icons.price_change),
                                              label: const Text(
                                                  'Fiyat Güncelle'),
                                            ),
                                            ElevatedButton.icon(
                                              style:
                                                  ElevatedButton.styleFrom(
                                                minimumSize:
                                                    const Size(0, 40),
                                              ),
                                              onPressed: _excelImporting
                                                  ? null
                                                  : _importExcelFromCsv,
                                              icon: const Icon(
                                                  Icons.upload_file),
                                              label: const Text(
                                                  'Excel ile Fiyat Güncelle'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Fiyat Yönetimi',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              const Text(
                                                'Bir stok seçin, fiyatları güncelleyin. Yapılan her güncelleme fiyat geçmişine otomatik kaydedilir.',
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              style:
                                                  ElevatedButton.styleFrom(
                                                minimumSize:
                                                    const Size(0, 40),
                                              ),
                                              onPressed:
                                                  _selectedStockId == null
                                                      ? null
                                                      : () =>
                                                          _showUpdatePriceSheet(
                                                            _selectedStockId!,
                                                          ),
                                              icon: const Icon(
                                                  Icons.price_change),
                                              label: const Text(
                                                  'Fiyat Güncelle'),
                                            ),
                                            ElevatedButton.icon(
                                              style:
                                                  ElevatedButton.styleFrom(
                                                minimumSize:
                                                    const Size(0, 40),
                                              ),
                                              onPressed: _excelImporting
                                                  ? null
                                                  : _importExcelFromCsv,
                                              icon: const Icon(
                                                  Icons.upload_file),
                                              label: const Text(
                                                  'Excel ile Fiyat Güncelle'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                              const SizedBox(height: 16),
                              buildHeroCard(),
                              const SizedBox(height: 16),
                              buildExcelCard(),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      isNarrow
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fiyat Yönetimi',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Bir stok seçin, fiyatları güncelleyin. Yapılan her güncelleme fiyat geçmişine otomatik kaydedilir.',
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                      onPressed: _selectedStockId == null
                                          ? null
                                          : () => _showUpdatePriceSheet(
                                                _selectedStockId!,
                                              ),
                                      icon: const Icon(Icons.price_change),
                                      label: const Text('Fiyat Güncelle'),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                      onPressed: _excelImporting
                                          ? null
                                          : _importExcelFromCsv,
                                      icon: const Icon(Icons.upload_file),
                                      label:
                                          const Text('Excel ile Fiyat Güncelle'),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Fiyat Yönetimi',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Bir stok seçin, fiyatları güncelleyin. Yapılan her güncelleme fiyat geçmişine otomatik kaydedilir.',
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                      onPressed: _selectedStockId == null
                                          ? null
                                          : () => _showUpdatePriceSheet(
                                                _selectedStockId!,
                                              ),
                                      icon: const Icon(Icons.price_change),
                                      label: const Text('Fiyat Güncelle'),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                      onPressed: _excelImporting
                                          ? null
                                          : _importExcelFromCsv,
                                      icon: const Icon(Icons.upload_file),
                                      label:
                                          const Text('Excel ile Fiyat Güncelle'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                      const SizedBox(height: 16),
                      buildHeroCard(),
                      const SizedBox(height: 16),
                    ],
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _selectedStockId == null
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(AppSpacing.s16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 48,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(height: AppSpacing.s8),
                                          Text(
                                            'Önce bir stok seçin.',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: AppSpacing.s4),
                                          Text(
                                            'Üstteki karttan stok seçerek hareketleri görüntüleyebilirsiniz.',
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: AppSpacing.s8),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            Wrap(
                                              spacing: AppSpacing.s8,
                                              children: [
                                                ChoiceChip(
                                                  label: const Text('Son 7g'),
                                                  selected: _dateFilter == '7d',
                                                  onSelected: (v) {
                                                    if (!v) return;
                                                    setState(() {
                                                      _dateFilter = '7d';
                                                    });
                                                  },
                                                ),
                                                ChoiceChip(
                                                  label: const Text('Son 30g'),
                                                  selected: _dateFilter == '30d',
                                                  onSelected: (v) {
                                                    if (!v) return;
                                                    setState(() {
                                                      _dateFilter = '30d';
                                                    });
                                                  },
                                                ),
                                                ChoiceChip(
                                                  label: const Text('Tümü'),
                                                  selected: _dateFilter == 'all',
                                                  onSelected: (v) {
                                                    if (!v) return;
                                                    setState(() {
                                                      _dateFilter = 'all';
                                                    });
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: AppSpacing.s8),
                                      Expanded(
                                        child: _buildMovementsSection(context),
                                      ),
                                    ],
                                  ),
                          ),
                          if (isWide) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Card(
                                      child: Padding(
                                        padding: AppSpacing.cardPadding,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Fiyat Özeti',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: AppSpacing.s8),
                                            Wrap(
                                              spacing: AppSpacing.s8,
                                              runSpacing: AppSpacing.s8,
                                              children: [
                                                _buildKpiTile(
                                                  context,
                                                  title: 'Son Fiyat Güncelleme',
                                                  value: _kpiMetrics.lastPriceLabel,
                                                ),
                                                _buildKpiTile(
                                                  context,
                                                  title: 'Son 7 günde fiyat güncelleme',
                                                  value: _kpiMetrics.last7dPriceCount.toString(),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    buildExcelCard(),
                                  ],
                                ),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMovementsSection(BuildContext context) {
    final stockId = _selectedStockId!;
    final movementsAsync = ref.watch(_stockMovementsProvider(stockId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (_selectedStockLabel != null)
                Chip(
                  label: Text(
                    'Seçili: $_selectedStockLabel',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                ),
                onPressed: () => _showUpdatePriceSheet(stockId),
                icon: const Icon(Icons.price_change),
                label: const Text('Fiyat Güncelle'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: movementsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) {
                        final message = e.toString();
                        final lower = message.toLowerCase();
                        final missingTable =
                            (lower.contains('pgrst205') ||
                                    lower.contains('404')) &&
                                lower.contains('stock_movements');
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              missingTable
                                  ? 'Fiyat geçmişi tablosu henüz kurulmamış.'
                                  : 'Fiyat geçmişi yüklenemedi.',
                            ),
                            if (missingTable) ...[
                              const SizedBox(height: AppSpacing.s4),
                              const Text(
                                'Supabase tarafında stock_movements tablosu oluşturulmalı.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    ExpansionTile(
                      title: const Text('Detay'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.s8),
                          child: Text(e.toString()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            data: (items) {
              // Debug: hareketlerin UI tarafında nasıl filtrelendiğini logla.
              if (kDebugMode) {
                debugPrint(
                  '[StockMovementsPage] Raw movements loaded for stockId=$stockId '
                  'total=${items.length} dateFilter=$_dateFilter table=stock_movements',
                );
              }

              // KPI metriklerini hesapla
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              DateTime? lastPriceAt;
              String? lastPriceNote;
              num last7dPriceCount = 0;

              for (final m in items) {
                final local = m.createdAt.toLocal();
                final d = DateTime(local.year, local.month, local.day);

                if (m.type == 'price') {
                  final sevenDaysAgo =
                      today.subtract(const Duration(days: 7));
                  if (!d.isBefore(sevenDaysAgo)) {
                    last7dPriceCount++;
                  }

                  if (lastPriceAt == null || local.isAfter(lastPriceAt)) {
                    lastPriceAt = local;
                    lastPriceNote =
                        (m.note != null && m.note!.trim().isNotEmpty)
                            ? m.note!.trim()
                            : 'Fiyat güncellendi';
                  }
                }
              }

              final String lastPriceLabel;
              if (lastPriceAt == null) {
                lastPriceLabel = '—';
              } else {
                final timeText =
                    TimeOfDay.fromDateTime(lastPriceAt).format(context);
                final dateText = _formatDate(lastPriceAt);
                lastPriceLabel = '$timeText • $dateText\n$lastPriceNote';
              }

              final newMetrics = _KpiMetrics(
                lastPriceLabel: lastPriceLabel,
                last7dPriceCount: last7dPriceCount,
              );

              if (_kpiMetrics != newMetrics) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _kpiMetrics = newMetrics;
                  });
                });
              }

              // Yalnızca fiyat hareketlerini al
              List<StockMovement> filtered =
                  items.where((m) => m.type == 'price').toList();

              if (kDebugMode) {
                debugPrint(
                  '[StockMovementsPage] Filtered price movements for stockId=$stockId '
                  'count=${filtered.length} type="price" dateFilter=$_dateFilter',
                );
              }

              // Tarih filtresi (local date)
              if (_dateFilter != 'all') {
                final now2 = DateTime.now();
                final today2 =
                    DateTime(now2.year, now2.month, now2.day);
                final from = _dateFilter == '7d'
                    ? today2.subtract(const Duration(days: 7))
                    : today2.subtract(const Duration(days: 30));
                filtered = filtered.where((m) {
                  final local = m.createdAt.toLocal();
                  final d =
                      DateTime(local.year, local.month, local.day);
                  return !d.isBefore(from);
                }).toList();
              }

              Widget buildMovementCard(StockMovement m) {
                final theme = Theme.of(context);
                final local = m.createdAt.toLocal();
                final timeText =
                    TimeOfDay.fromDateTime(local).format(context);
                final dateText = _formatDate(local);

                final note = m.note;
                final noteText =
                    (note != null && note.trim().isNotEmpty)
                        ? note.trim()
                        : '—';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 4,
                  ),
                  child: ListTile(
                    onTap: () {},
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE0E7FF),
                      child: Icon(
                        Icons.price_change,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                    title: Text(
                      noteText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(noteText),
                        const SizedBox(height: 4),
                        Text(
                          '$timeText • $dateText',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('Bu stok için henüz fiyat geçmişi yok.'),
                );
              }
              // Tarihe göre sıralanmış fiyat geçmişi listesi
              filtered.sort(
                (a, b) =>
                    b.createdAt.compareTo(a.createdAt),
              );

              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final m = filtered[index];
                  return buildMovementCard(m);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Eski sayım/fiyat CSV akışları (_exportCountTemplateCsv, _exportPriceTemplateCsv,
  // _importCountsFromCsv, _importPricesFromCsv) yeni tek Excel akışı ile
  // değiştirilmiştir ve koddan kaldırılmıştır.
}

class _ExcelImportRow {
  _ExcelImportRow({
    required this.rowNumber,
    required this.stockCode,
    this.note,
    this.price1,
    this.price2,
    this.price3,
    this.price4,
    this.error,
  });

  final int rowNumber;
  final String stockCode;
  final String? note;

  final double? price1;
  final double? price2;
  final double? price3;
  final double? price4;

  String? error;

  double? oldPrice1;
  double? oldPrice2;
  double? oldPrice3;
  double? oldPrice4;

  double? newPrice1;
  double? newPrice2;
  double? newPrice3;
  double? newPrice4;

  bool hasPriceChange = false;
}

class _KpiMetrics {
  const _KpiMetrics({
    this.lastPriceLabel = '—',
    this.last7dPriceCount = 0,
  });

  final String lastPriceLabel;
  final num last7dPriceCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _KpiMetrics &&
      other.lastPriceLabel == lastPriceLabel &&
      other.last7dPriceCount == last7dPriceCount;
  }

  @override
  int get hashCode => Object.hash(
        lastPriceLabel,
      last7dPriceCount,
      );
}

Widget _buildKpiTile(
  BuildContext context, {
  required String title,
  required String value,
}) {
  final theme = Theme.of(context);
  return SizedBox(
    width: 160,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
