import 'dart:convert';

import 'package:core/core.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../debug/debug_admin_context.dart';

import 'stock_import_export_download_stub.dart'
    if (dart.library.html) 'stock_import_export_download_web.dart'
    as download_helper;

class StockImportExportPage extends ConsumerStatefulWidget {
  const StockImportExportPage({super.key});

  @override
  ConsumerState<StockImportExportPage> createState() => _StockImportExportPageState();
}

class _StockImportExportPageState extends ConsumerState<StockImportExportPage> {
  bool _exporting = false;
  bool _importing = false;
  List<_ParsedImportRow>? _importRows;
  ImportResult? _lastResult;
  int? _previewInsertCount;
  int? _previewUpdateCount;
  int? _previewDeleteCount;

  Future<void> _showCsvPreviewDialog({
    required String fileName,
    required String csv,
    required String excelFileName,
    required Uint8List excelBytes,
    required ScaffoldMessengerState messenger,
  }) async {
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
                  fileName,
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
                final ok = await download_helper.saveBytesFile(
                  excelFileName,
                  excelBytes,
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

  String stocksToCsv(List<StockExportRow> rows) {
    final buffer = StringBuffer();

    // UTF-8 BOM ekle (Excel TR için doğru encoding ve ayırıcı algısı).
    buffer.write('\uFEFF');

    const sep = stockCsvDelimiter;

    // Nihai şablon: sadece istenen kolonlar, miktar alanı yok.
    buffer.writeln([
      'kod',
      'ad',
      'marka',
      'kdv_oran',
      'satis_fiyat1',
      'satis_fiyat2',
      'satis_fiyat3',
      'satis_fiyat4',
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
    ].join(sep));

    String escText(String? value) {
      final v = (value ?? '').replaceAll('"', '""');
      // Metin alanlarını her zaman tırnakla.
      return '"$v"';
    }

    String escRaw(String? value) {
      return value ?? '';
    }

    for (final row in rows) {
      final s = row.stock;
      final line = [
        escText(s.code), // kod
        escText(s.name), // ad
        escText(s.brand), // marka
        escRaw(s.taxRate.toString()), // kdv_oran (sayı)
        escRaw(s.salePrice1?.toString()), // satis_fiyat1
        escRaw(s.salePrice2?.toString()), // satis_fiyat2
        escRaw(s.salePrice3?.toString()), // satis_fiyat3
        escRaw(s.salePrice4?.toString()), // satis_fiyat4
        escText(s.barcode), // barkod
        escText(s.packBarcode), // paket_barkod
        escText(s.boxBarcode), // koli_barkod
        escRaw(row.packQty?.toString()), // paket_ici_adet
        escRaw(row.boxQty?.toString()), // koli_ici_adet
        escText(s.groupName), // grup_ad
        escText(s.subgroupName), // ara_grup_ad
        escText(s.subsubgroupName), // alt_grup_ad
        escRaw(s.isActive == false ? '0' : '1'), // aktif (0/1)
        escText(s.imagePath), // resim_yolu
      ].join(sep);
      buffer.writeln(line);
    }

    return buffer.toString();
  }

  Uint8List? stocksToXlsxBytes(List<StockExportRow> rows) {
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
      'kod',
      'ad',
      'marka',
      'kdv_oran',
      'satis_fiyat1',
      'satis_fiyat2',
      'satis_fiyat3',
      'satis_fiyat4',
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

    sheet.appendRow(textRow(headers));

    for (final row in rows) {
      final s = row.stock;
      sheet.appendRow(
        textRow([
          s.code,
          s.name,
          s.brand,
          s.taxRate.toString(),
          s.salePrice1?.toString() ?? '',
          s.salePrice2?.toString() ?? '',
          s.salePrice3?.toString() ?? '',
          s.salePrice4?.toString() ?? '',
          s.barcode ?? '',
          s.packBarcode ?? '',
          s.boxBarcode ?? '',
          row.packQty?.toString() ?? '',
          row.boxQty?.toString() ?? '',
          s.groupName ?? '',
          s.subgroupName ?? '',
          s.subsubgroupName ?? '',
          s.isActive == false ? '0' : '1',
          s.imagePath ?? '',
        ]),
      );
    }

    final bytes = excel.encode();
    if (bytes == null) return null;
    return Uint8List.fromList(bytes);
  }

  Future<void> _exportCsv() async {
    setState(() {
      _exporting = true;
    });

    try {
      final messenger = ScaffoldMessenger.of(context);
      final stocks = await stockRepository.fetchAllStocksForExport();
      final csv = stocksToCsv(stocks);
      final xlsxBytes = stocksToXlsxBytes(stocks);

      final now = DateTime.now();
      final ts =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final fileName = 'Stok Excel Şablonu $ts.csv';
      final excelFileName = 'Stok Excel Şablonu $ts.xlsx';

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
        if (!mounted) return;
        if (ok) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Excel şablonu indiriliyor.')),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Excel indirilemedi.')),
          );
        }
      } else {
        if (!mounted) return;
        if (xlsxBytes == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Excel dosyası oluşturulamadı.')),
          );
          return;
        }
        await _showCsvPreviewDialog(
          fileName: fileName,
          csv: csv,
          excelFileName: excelFileName,
          excelBytes: xlsxBytes,
          messenger: messenger,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dışa aktarma hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exporting = false;
        });
      }
    }
  }

  Future<void> _pickAndParseCsv() async {
    setState(() {
      _importRows = null;
      _lastResult = null;
      _previewInsertCount = null;
      _previewUpdateCount = null;
      _previewDeleteCount = null;
    });

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
      final fileName = file.name;
      final lowerName = fileName.toLowerCase();
      if (!lowerName.endsWith('.csv')) {
        if (kDebugMode) {
          debugPrint(
            '[ADMIN][DEBUG] _pickAndParseCsv invalid extension name=$fileName',
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sadece CSV (.csv) dosyaları desteklenir.'),
          ),
        );
        return;
      }

      if (file.bytes == null) {
        if (kDebugMode) {
          debugPrint(
            '[ADMIN][DEBUG] _pickAndParseCsv file.bytes is null for name=$fileName',
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seçilen dosya okunamadı (içerik boş).'),
          ),
        );
        return;
      }

      if (file.bytes!.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[ADMIN][DEBUG] _pickAndParseCsv file.bytes is empty for name=$fileName',
          );
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seçilen dosya boş görünüyor.'),
          ),
        );
        return;
      }

      final content = utf8.decode(file.bytes!);
      final rows = parseCsv(content);

      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV dosyası boş görünüyor.')),
        );
        return;
      }

      final parsed = <_ParsedImportRow>[];
      var lineNumber = 2; // header satırı 1 varsayıyoruz
      for (final row in rows) {
        final code = (row['code'] ?? row['kod'] ?? '').toString();
        final name = (row['name'] ?? row['ad'] ?? '').toString();

        final errors = <String>[];
        if (code.trim().isEmpty) {
          errors.add('kod (code) zorunlu');
        }
        if (name.trim().isEmpty) {
          errors.add('ad (name) zorunlu');
        }

        parsed.add(
          _ParsedImportRow(
            rowNumber: lineNumber,
            values: row,
            error: errors.isEmpty ? null : errors.join(', '),
          ),
        );
        lineNumber++;
      }

      if (!mounted) return;
      setState(() {
        _importRows = parsed;
      });

      // Hesaplanan satırlara göre (geçerli satırlar) önizleme amaçlı
      // eklenecek/güncellenecek/silinecek stok adetlerini hesapla.
      await _computePreviewCounts();
    } catch (e) {
      debugPrint('[ADMIN][DEBUG] _pickAndParseCsv error=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV okuma/parse hatası: $e')),
      );
    }
  }

  Future<void> _applyImport() async {
    final rows = _importRows;
    if (rows == null) return;

    final validRows = rows
        .where((r) => r.error == null)
        .map((r) => r.values)
        .toList(growable: false);

    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli satır bulunamadı.')),
      );
      return;
    }

    setState(() {
      _importing = true;
      _lastResult = null;
    });

    try {
      await debugAdminContext();
      final result = await stockRepository.importStocksFromCsvRows(validRows);
      if (!mounted) return;
      setState(() {
        _lastResult = result;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'İçe aktarma tamamlandı. Insert: ${result.insertedCount}, Update: ${result.updatedCount}, Atlanan: ${result.skippedCount}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İçe aktarma hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
    }
  }

  Future<void> _computePreviewCounts() async {
    final rows = _importRows;
    if (rows == null) {
      return;
    }

    try {
      // Sadece hatasız satırlardaki kod değerlerini kullan (trim + uppercase).
      final excelCodes = rows
          .where((r) => r.error == null)
          .map((r) {
            final rawCode = r.values['code'] ?? r.values['kod'];
            return rawCode?.trim().toUpperCase();
          })
          .whereType<String>()
          .where((c) => c.isNotEmpty)
          .toSet();

      if (excelCodes.isEmpty) {
        if (!mounted) return;
        setState(() {
          _previewInsertCount = 0;
          _previewUpdateCount = 0;
          _previewDeleteCount = 0;
        });
        return;
      }

      final allStocks = await stockRepository.fetchAllStocksForExport();
      final existingCodes = allStocks
          .map((e) => e.stock.code)
          .whereType<String>()
          .map((c) => c.trim().toUpperCase())
          .where((c) => c.isNotEmpty)
          .toSet();

      final willInsert = excelCodes.difference(existingCodes).length;
      final willUpdate = excelCodes.intersection(existingCodes).length;
      final willDelete = existingCodes.difference(excelCodes).length;

      if (!mounted) return;
      setState(() {
        _previewInsertCount = willInsert;
        _previewUpdateCount = willUpdate;
        _previewDeleteCount = willDelete;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Önizleme hesaplanırken hata oluştu: $e')),
      );
    }
  }

  List<Widget> _buildNotDeletedSection(ImportResult result) {
    final notDeletedStocks = result.notDeletedStocks;
    if (notDeletedStocks.isEmpty) {
      return const [];
    }

    return [
      const SizedBox(height: 12),
      Text(
        'Silinemeyen Ürünler',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 200,
        child: ListView.builder(
          itemCount: notDeletedStocks.length,
          itemBuilder: (context, index) {
            final item = notDeletedStocks[index];
            final name = item.name ?? '';
            return ListTile(
              dense: true,
              title: Text(
                '${item.code}${name.isNotEmpty ? ' - $name' : ''}',
              ),
              subtitle: Text(item.reason),
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final importRows = _importRows;
    final lastResult = _lastResult;

    final totalRows = importRows?.length ?? 0;
    final invalidRows =
        importRows?.where((r) => r.error != null).toList(growable: false) ?? [];
    final validCount = totalRows - invalidRows.length;

    return AppScaffold(
      title: 'Excel ile Ürün Senkronizasyonu',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bu ekran ürün listesini Excel dosyasına bire bir eşitler. '
                    'Excel’de olmayan ürünler sistemden silinir, olanlar eklenir/güncellenir.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.download_rounded,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '1) Şablonu indir',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '2) Excel’de düzenle',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.upload_file_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '3) Excel dosyasını yükle',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '4) Önizle',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              '5) Uygula',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Icon(
                                  Icons.grid_on_rounded,
                                  size: 32,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '📦 CSV ile Stok Aktarımı',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Stok kartlarını dışa aktar, Excel’de düzenle, tekrar yükle. '
                                      'Uygulamadan önce sistem sana önizleme gösterecek.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                        onPressed:
                                          _exporting ? null : _exportCsv,
                                      icon: _exporting
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.download_rounded),
                                      label: const Text('CSV Dışa Aktar'),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Mevcut ürün listesini indir (Excel’de açılır).',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color
                                                ?.withValues(alpha: 0.8),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 40),
                                      ),
                                      onPressed: _importing
                                          ? null
                                          : _pickAndParseCsv,
                                      icon: const Icon(
                                          Icons.upload_file_rounded),
                                        label: const Text('Excel İçe Aktar'),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Düzenlenmiş Excel/CSV dosyasını seç ve önizle.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.color
                                                ?.withValues(alpha: 0.8),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kritik Uyarı',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Excel’de olmayan ürünler sistemden silinir. Silinemeyenler raporlanır.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.red.shade700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Zorunlu: kod, ad'),
                          const Text('Opsiyonel: diğer kolonlar'),
                          const Text('Miktar: bu ekranda yönetilmez (yok sayılır)'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Excel Dosya Kolonları',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Temel Bilgiler',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('kod')),
                              Chip(label: Text('ad')),
                              Chip(label: Text('marka')),
                              Chip(label: Text('kdv_oran')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Fiyatlar',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('satis_fiyat1')),
                              Chip(label: Text('satis_fiyat2')),
                              Chip(label: Text('satis_fiyat3')),
                              Chip(label: Text('satis_fiyat4')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Barkod & Paket',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('barkod')),
                              Chip(label: Text('paket_barkod')),
                              Chip(label: Text('koli_barkod')),
                              Chip(label: Text('paket_ici_adet')),
                              Chip(label: Text('koli_ici_adet')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Gruplama',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('grup_ad')),
                              Chip(label: Text('ara_grup_ad')),
                              Chip(label: Text('alt_grup_ad')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Durum & Görsel',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          const Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text('aktif')),
                              Chip(label: Text('resim_yolu')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (importRows != null || lastResult != null) ...[
                    const SizedBox(height: 24),
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Son Yükleme Özeti',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                          fontWeight: FontWeight.bold),
                                ),
                                if (importRows != null)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 36),
                                    ),
                                    onPressed: validCount == 0 || _importing
                                        ? null
                                        : _applyImport,
                                    icon: _importing
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child:
                                                CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.playlist_add_check),
                                    label: const Text('Uygula'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (importRows != null)
                                  Chip(
                                    label:
                                        Text('Toplam satır: $totalRows'),
                                  ),
                                if (importRows != null)
                                  Chip(
                                    label: Text('Geçerli: $validCount'),
                                  ),
                                if (importRows != null)
                                  Chip(
                                    label: Text(
                                        'Hatalı: ${invalidRows.length}'),
                                  ),
                                if (_previewInsertCount != null)
                                  Chip(
                                    label: Text(
                                        'Eklenecek (tahmini): ${_previewInsertCount ?? 0}'),
                                  ),
                                if (_previewUpdateCount != null)
                                  Chip(
                                    label: Text(
                                        'Güncellenecek (tahmini): ${_previewUpdateCount ?? 0}'),
                                  ),
                                if (_previewDeleteCount != null)
                                  Chip(
                                    label: Text(
                                        'Silinecek (tahmini): ${_previewDeleteCount ?? 0}'),
                                  ),
                                if (lastResult != null)
                                  Chip(
                                    label: Text(
                                        'Atlanan: ${lastResult.skippedCount}'),
                                  ),
                              ],
                            ),
                            if (lastResult != null) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  Chip(
                                    label: Text(
                                        'Insert: ${lastResult.insertedCount}'),
                                  ),
                                  Chip(
                                    label: Text(
                                        'Update: ${lastResult.updatedCount}'),
                                  ),
                                  Chip(
                                    label: Text(
                                        'Silinen: ${lastResult.deletedCount}'),
                                  ),
                                  Chip(
                                    label: Text(
                                        'Silinemeyen: ${lastResult.notDeletedCount}'),
                                  ),
                                  Chip(
                                    label: Text(
                                        'Hatalı satır: ${lastResult.errorRows.length}'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (importRows != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (invalidRows.isNotEmpty) ...[
                              Text(
                                'Hatalı Satırlar',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 260,
                                child: ListView.builder(
                                  itemCount: invalidRows.length,
                                  itemBuilder: (context, index) {
                                    final row = invalidRows[index];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        'Satır ${row.rowNumber}: ${row.error}',
                                        style: const TextStyle(
                                            color: Colors.red),
                                      ),
                                      subtitle:
                                          Text(row.values['code'] ?? ''),
                                    );
                                  },
                                ),
                              ),
                              if (lastResult != null)
                                ..._buildNotDeletedSection(lastResult),
                            ] else if (importRows.isNotEmpty) ...[
                              Text(
                                'Örnek Geçerli Satırlar (ilk 20)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 260,
                                child: ListView.builder(
                                  itemCount: importRows.length > 20
                                      ? 20
                                      : importRows.length,
                                  itemBuilder: (context, index) {
                                    final row = importRows[index];
                                    final code = row.values['code'] ?? '';
                                    final name = row.values['name'] ?? '';
                                    return ListTile(
                                      dense: true,
                                      title: Text('$code - $name'),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParsedImportRow {
  const _ParsedImportRow({
    required this.rowNumber,
    required this.values,
    this.error,
  });

  final int rowNumber;
  final Map<String, String> values;
  final String? error;
}
