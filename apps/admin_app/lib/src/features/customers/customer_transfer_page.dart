import 'package:core/core.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import 'customer_transfer_download.dart';
import 'import/customer_excel_schema.dart';
import 'import/customer_excel_parser.dart';
import 'import/customer_import_models.dart';
import 'import/customer_import_service.dart';

enum _CustomerTransferTab {
  export,
  import,
}

// Yeni Excel şeması ile uyumlu kolon sırası ve başlıklar,
// customer_excel_schema.dart içinden geliyor.

String _normalizeDigits(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  final buffer = StringBuffer();
  for (final ch in raw.runes) {
    final c = String.fromCharCode(ch);
    if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
      buffer.write(c);
    }
  }
  return buffer.toString();
}

String _formatPhoneForExcel(String? phone) {
  final digits = _normalizeDigits(phone);
  if (digits.isEmpty) return '';
  return '="$digits"';
}

String _formatTaxNoForExcel(String? taxNo) {
  final digits = _normalizeDigits(taxNo);
  if (digits.isEmpty) return '';
  return '="$digits"';
}

Map<String, String> exportCustomerToMap(Customer c) {
  final hasTradeTitle = (c.tradeTitle ?? '').trim().isNotEmpty;
  final hasFullName = (c.fullName ?? '').trim().isNotEmpty;

  final tradeTitle = hasTradeTitle ? c.tradeTitle!.trim() : '';
  final fullName = hasFullName ? c.fullName!.trim() : '';

  final customerType = hasTradeTitle ? 'Ticari' : 'Bireysel';

  return <String, String>{
    CustomerExcelFields.customerType: customerType,
    CustomerExcelFields.tradeTitle: tradeTitle,
    CustomerExcelFields.fullName: fullName,
    CustomerExcelFields.customerCode: c.code,

  CustomerExcelFields.phone: _formatPhoneForExcel(c.phone),
  CustomerExcelFields.email: c.email ?? '',

  CustomerExcelFields.taxOffice: c.taxOffice ?? '',
  CustomerExcelFields.taxNo: _formatTaxNoForExcel(c.taxNo),

  CustomerExcelFields.address: c.address ?? '',
  CustomerExcelFields.city: c.city ?? '',
  CustomerExcelFields.district: c.district ?? '',

  // Sayısal alanlar: null ise defaultlarla doldur.
  // limit_amount -> 0
  CustomerExcelFields.limitAmount:
    (c.limitAmount ?? 0).toString(),
  CustomerExcelFields.warnOnLimitExceeded:
    (c.warnOnLimitExceeded ?? false) ? 'Evet' : 'Hayır',
  CustomerExcelFields.salesRepName: c.marketerName ?? '',
  CustomerExcelFields.riskNote: c.riskNote ?? '',

  CustomerExcelFields.tagsCsv:
    c.tags.isNotEmpty ? c.tags.join(', ') : '',
  CustomerExcelFields.isActive: c.isActive ? 'Aktif' : 'Pasif',

  // price_tier -> Excel'de "Liste X" metni; null ise 4.
  CustomerExcelFields.priceListName:
    'Liste ${c.priceListNo ?? 4}',
  // due_days -> null ise 30
  CustomerExcelFields.dueDays:
    (c.dueDays ?? 30).toString(),

  CustomerExcelFields.group: c.groupName ?? '',
  CustomerExcelFields.subGroup: c.subGroupName ?? '',
  CustomerExcelFields.subSubGroup: c.subSubGroupName ?? '',
  };
}


class CustomerTransferPage extends ConsumerStatefulWidget {
  const CustomerTransferPage({super.key});

  @override
  ConsumerState<CustomerTransferPage> createState() => _CustomerTransferPageState();
}

class _CustomerTransferPageState extends ConsumerState<CustomerTransferPage> {
  _CustomerTransferTab _tab = _CustomerTransferTab.export;

  // Export state
  String _exportStatusFilter = 'all';
  bool _isExportingExcel = false;

  // Import state
  bool _isPickingFile = false;
  bool _isApplyRunning = false;
  String? _selectedFileName;
  List<CustomerImportRow> _importRows = <CustomerImportRow>[];
  DuplicateStrategy _strategy = DuplicateStrategy.byCustomerCode;
  CustomerImportSummary? _importSummary;
  String? _lastBatchId;

  List<CellValue?> _textRow(Iterable<dynamic> values) {
    return values
        .map<CellValue?>((v) => TextCellValue(v.toString()))
        .toList();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Cari İçe / Dışa Aktarma',
      actions: [
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => GoRouter.of(context).go('/customers/new'),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Yeni Cari Ekle'),
        ),
      ],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Excel ile cari listenizi dışa aktarın.',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            'Excel’de ekleme/silme/güncelleme yaptıktan sonra (yakında) tekrar içe aktarabileceksiniz.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                Wrap(
                  spacing: AppSpacing.s8,
                  children: [
                    ChoiceChip(
                      label: const Text('İçe Aktar'),
                      selected: _tab == _CustomerTransferTab.import,
                      onSelected: (_) {
                        setState(() => _tab = _CustomerTransferTab.import);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Dışa Aktar'),
                      selected: _tab == _CustomerTransferTab.export,
                      onSelected: (_) {
                        setState(() => _tab = _CustomerTransferTab.export);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s16),
                if (_tab == _CustomerTransferTab.import)
                  _buildImportTab(context)
                else
                  _buildExportTab(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExportTab(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = _exportStatusFilter == 'active'
        ? true
        : _exportStatusFilter == 'inactive'
            ? false
            : null;

    return FutureBuilder<List<Customer>>(
      future: customerRepository.fetchCustomers(
        isActive: isActive,
        limit: 1000,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppLoadingState();
        }

        if (snapshot.hasError) {
          return AppErrorState(
            message:
                'Cari listesi dışa aktarma için yüklenemedi: ${snapshot.error}',
            onRetry: () {
              setState(() {});
            },
          );
        }

        final customers = snapshot.data ?? const <Customer>[];

        if (customers.isEmpty) {
          return const AppEmptyState(
            title: 'Cari bulunamadı',
            subtitle: 'Dışa aktarılacak cari kaydı yok.',
          );
        }

        final previewCustomers = customers.take(20).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dışa Aktarma',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Row(
                      children: [
                        Checkbox(
                          value: _exportStatusFilter == 'active',
                          onChanged: (v) {
                            setState(() {
                              _exportStatusFilter =
                                  v == true ? 'active' : 'all';
                            });
                          },
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        const Expanded(
                          child: Text('Sadece aktifler'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        PrimaryButton(
                          label: _isExportingExcel
                              ? 'Excel oluşturuluyor...'
                              : 'Excel olarak dışa aktar (XLSX)',
                          icon: Icons.grid_on_rounded,
                          onPressed: _isExportingExcel
                              ? null
                              : () async {
                            if (customers.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Dışa aktarılacak kayıt bulunamadı.'),
                                ),
                              );
                              return;
                            }

                            setState(() {
                              _isExportingExcel = true;
                            });

                            try {
                              final excel = Excel.createExcel();
                              final sheet =
                                  excel.sheets[excel.getDefaultSheet()]!;

                                const exportOrder = customerExcelExportOrder;

                              // Başlık satırı (Türkçe, kurumsal tasarım).
                              final headersTr = exportOrder
                                  .map((key) =>
                                      customerExcelHeaderTr[key] ?? key)
                                  .toList();
                              sheet.appendRow(_textRow(headersTr));

                              // Header hücre stilini ayarla.
                              for (var col = 0;
                                  col < exportOrder.length;
                                  col++) {
                                final cell = sheet.cell(
                                  CellIndex.indexByColumnRow(
                                    columnIndex: col,
                                    rowIndex: 0,
                                  ),
                                );
                                cell.cellStyle = CellStyle(
                                  bold: true,
                                  backgroundColorHex:
                                      ExcelColor.fromHexString('#22A38C'),
                                  fontColorHex:
                                      ExcelColor.fromHexString('#FFFFFFFF'),
                                );
                              }

                              for (var i = 0; i < customers.length; i++) {
                                final c = customers[i];
                                final map = exportCustomerToMap(c);
                                final rowValues = exportOrder
                                    .map((h) => map[h] ?? '')
                                    .toList();
                                sheet.appendRow(_textRow(rowValues));

                                // Durum kolonunu renklendir (Aktif/Pasif).
                                final statusColIndex = exportOrder.indexOf(
                                  CustomerExcelFields.isActive,
                                );
                                if (statusColIndex >= 0) {
                                  final cell = sheet.cell(
                                    CellIndex.indexByColumnRow(
                                      columnIndex: statusColIndex,
                                      rowIndex: i + 1,
                                    ),
                                  );
                                  final text = map['is_active'] ?? '';
                                  if (text == 'Aktif') {
                                    cell.cellStyle = CellStyle(
                                      backgroundColorHex:
                                          ExcelColor.fromHexString(
                                              '#D1FAE5'),
                                    );
                                  } else if (text == 'Pasif') {
                                    cell.cellStyle = CellStyle(
                                      backgroundColorHex:
                                          ExcelColor.fromHexString(
                                              '#FEE2E2'),
                                    );
                                  }
                                }
                              }

                              final bytes = excel.encode();
                              if (bytes == null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Excel dosyası oluşturulamadı.'),
                                    ),
                                  );
                                }
                                return;
                              }

                              final now = DateTime.now();
                              final yyyy = now.year.toString().padLeft(4, '0');
                              final mm =
                                  now.month.toString().padLeft(2, '0');
                              final dd =
                                  now.day.toString().padLeft(2, '0');
                                    final filename =
                                      'cari_listesi_${yyyy}_${mm}_$dd.xlsx';

                              await saveBytesAsFile(
                                Uint8List.fromList(bytes),
                                filename,
                                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                context,
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isExportingExcel = false;
                                });
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Önizleme (ilk 20 kayıt)',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox.shrink(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Code')),
                          DataColumn(label: Text('Ünvan')),
                          DataColumn(label: Text('Telefon')),
                          DataColumn(label: Text('E-posta')),
                          DataColumn(label: Text('Aktif')),
                          DataColumn(label: Text('Tip')),
                        ],
                        rows: [
                          for (final c in previewCustomers)
                            DataRow(
                              cells: [
                                DataCell(Text(c.code)),
                                DataCell(Text(c.displayName)),
                                DataCell(Text(c.phone ?? '')),
                                DataCell(Text(c.email ?? '')),
                                DataCell(
                                  Text(c.isActive ? 'Aktif' : 'Pasif'),
                                ),
                                DataCell(
                                  Text(
                                    (c.tradeTitle ?? '')
                                            .trim()
                                            .isNotEmpty
                                        ? 'Ticari'
                                        : 'Bireysel',
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImportTab(BuildContext context) {
    final theme = Theme.of(context);
    final isAdminAsync = ref.watch(isAdminProvider);

    return isAdminAsync.when(
      data: (isAdmin) {
        if (!isAdmin) {
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      'Cari içe aktarma sadece admin yetkisine sahip kullanıcılar tarafından yapılabilir.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Adım 1: Excel seç
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adım 1: Excel dosyası seç (.xlsx)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Maksimum 5MB, en fazla 10.000 satır. Dosya seçildiğinde parse ve temel kontroller otomatik çalışır.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        PrimaryButton(
                          label: _isPickingFile
                              ? 'Excel okunuyor...'
                              : 'Excel seç (XLSX)',
                          icon: Icons.upload_file_rounded,
                          onPressed: _isPickingFile
                              ? null
                              : () => _pickAndParseExcel(),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        if (_selectedFileName != null)
                          Expanded(
                            child: Text(
                              _selectedFileName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),

            // Adım 2: Önizleme
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adım 2: Önizleme (ilk 20 kayıt)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    if (_importRows.isEmpty)
                      const AppEmptyState(
                        title: 'Henüz satır yok',
                        subtitle:
                            'Önce bir Excel dosyası seçip başarılı şekilde okutun.',
                      )
                    else
                      _buildImportPreviewTable(theme),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),

            // Adım 3: Strateji
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adım 3: Güncelleme stratejisi',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    SegmentedButton<DuplicateStrategy>(
                      segments: const <ButtonSegment<DuplicateStrategy>>[
                        ButtonSegment<DuplicateStrategy>(
                          value: DuplicateStrategy.byCustomerCode,
                          label: Text('Cari Koduna göre Güncelle'),
                        ),
                        ButtonSegment<DuplicateStrategy>(
                          value: DuplicateStrategy.byTaxNo,
                          label: Text('Vergi No/TCKN’ye göre Güncelle'),
                        ),
                        ButtonSegment<DuplicateStrategy>(
                          value: DuplicateStrategy.insertOnly,
                          label: Text('Mevcutları Atla'),
                        ),
                      ],
                      selected: <DuplicateStrategy>{_strategy},
                      onSelectionChanged: (Set<DuplicateStrategy> selection) {
                        if (selection.isEmpty) return;
                        final value = selection.first;
                        setState(() => _strategy = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Önerilen: Cari Koduna göre Güncelle. Seçtiğiniz strateji, Exceldeki kayıtların mevcut carilerle nasıl eşleştirileceğini belirler.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),

            // Adım 4: İçe Aktar + Özet
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adım 4: İçe Aktarmayı Başlat',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Önce Excel parse ve validasyon tamamlanır, ardından toplu olarak Supabase üzerinde transaction ile uygulanır.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    Row(
                      children: [
                        PrimaryButton(
                          label: _isApplyRunning
                              ? 'İçe aktarılıyor...'
                              : 'İçe Aktarmayı Başlat',
                          icon: Icons.playlist_add_check,
                          onPressed:
                              _isApplyRunning ? null : () => _startImport(),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        if (_isApplyRunning)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (_isApplyRunning)
                          const SizedBox(width: AppSpacing.s8),
                        TextButton.icon(
                          onPressed: _lastBatchId == null
                              ? null
                              : () => _downloadErrorReport(),
                          icon: const Icon(Icons.file_download),
                          label: const Text('Hata raporunu indir (XLSX)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    if (_importSummary != null)
                      _buildImportSummaryCard(theme, _importSummary!),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const AppLoadingState(),
      error: (e, _) => AppErrorState(
        message: 'Yetki bilgisi alınamadı: ${AppException.messageOf(e)}',
        onRetry: () => ref.invalidate(isAdminProvider),
      ),
    );
  }

  Widget _buildImportPreviewTable(ThemeData theme) {
    final preview = _importRows.take(20).toList();
    return SizedBox(
      height: 360,
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
        columns: const [
          DataColumn(label: Text('Cari Kodu')),
          DataColumn(label: Text('Cari Türü')),
          DataColumn(label: Text('Ünvan')),
          DataColumn(label: Text('Telefon')),
          DataColumn(label: Text('E-posta')),
          DataColumn(label: Text('Vergi No')),
          DataColumn(label: Text('İl')),
          DataColumn(label: Text('İlçe')),
          DataColumn(label: Text('Kredi Limiti')),
          DataColumn(label: Text('Aktif')),
          DataColumn(label: Text('Durum')),
        ],
        rows: [
          for (final row in preview)
            DataRow(
              cells: [
                DataCell(Text(
                  row.values[CustomerExcelFields.customerCode] ?? '-',
                )),
                DataCell(Text(
                  _formatCustomerTypeForPreview(
                    row.values[CustomerExcelFields.customerType],
                  ),
                )),
                DataCell(Text(
                  row.values[CustomerExcelFields.tradeTitle] ?? '-',
                )),
                DataCell(Text(
                  row.values[CustomerExcelFields.phone] ?? '-',
                )),
                DataCell(Text(
                  _stringOrDash(row.values[CustomerExcelFields.email]),
                )),
                DataCell(Text(
                  _stringOrDash(
                    row.values[CustomerExcelFields.taxNo],
                  ),
                )),
                DataCell(Text(
                  _stringOrDash(row.values[CustomerExcelFields.city]),
                )),
                DataCell(Text(
                  _stringOrDash(row.values[CustomerExcelFields.district]),
                )),
                DataCell(Text(
                  _formatLimitAmountForPreview(
                    row.values[CustomerExcelFields.limitAmount],
                  ),
                )),
                DataCell(Text(
                  (row.values[CustomerExcelFields.isActive] ??
                              'true') ==
                          'true'
                      ? 'Aktif'
                      : 'Pasif',
                )),
                DataCell(_buildStatusChip(theme, row)),
              ],
            ),
        ],
      ),
          ),
        ),
      ),
    );
  }

  String _stringOrDash(Object? value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _formatCustomerTypeForPreview(Object? raw) {
    final value = raw?.toString().toLowerCase().trim();
    if (value == 'commercial' || value == 'ticari') {
      return 'Ticari';
    }
    if (value == 'individual' || value == 'bireysel') {
      return 'Bireysel';
    }
    return '-';
  }

  String _formatLimitAmountForPreview(Object? raw) {
    if (raw == null) return '0';
    final text = raw.toString().trim();
    if (text.isEmpty) return '0';
    return text;
  }

  Widget _buildStatusChip(ThemeData theme, CustomerImportRow row) {
    final status = effectiveStatus(row, _strategy);
    String label;
    Color background;

    switch (status) {
      case ImportRowStatus.newItem:
        label = 'Yeni';
        background = const Color(0xFFD1FAE5);
      case ImportRowStatus.willUpdate:
        label = 'Güncellenecek';
        background = const Color(0xFFFFEDD5);
      case ImportRowStatus.willSkip:
        label = 'Atlanacak';
        background = const Color(0xFFE5E7EB);
      case ImportRowStatus.error:
        label = 'Hatalı';
        background = const Color(0xFFFECACA);
    }

    return Tooltip(
      message: row.allIssues.join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _buildImportSummaryCard(
    ThemeData theme,
    CustomerImportSummary summary,
  ) {
    return Card(
      color: const Color(0xFFECFDF5),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _summaryItem(theme, 'Toplam', summary.total.toString()),
            _summaryItem(theme, 'Eklendi', summary.inserted.toString()),
            _summaryItem(theme, 'Güncellendi', summary.updated.toString()),
            _summaryItem(theme, 'Atlandı', summary.skipped.toString()),
            _summaryItem(theme, 'Hatalı', summary.failed.toString()),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Future<void> _pickAndParseExcel() async {
    setState(() {
      _isPickingFile = true;
      _importRows = <CustomerImportRow>[];
      _importSummary = null;
      _lastBatchId = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['xlsx'],
        withData: true,
      );

      if (!mounted) return;

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.first;
      _selectedFileName = file.name;

      if (file.size > 5 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya boyutu 5MB sınırını aşıyor.'),
          ),
        );
        return;
      }

      final bytes = file.bytes;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Seçilen dosya okunamadı.'),
          ),
        );
        return;
      }

      final rows = await parseCustomerExcel(bytes);
      if (!mounted) return;

      setState(() {
        _importRows = rows;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Excel okunurken hata oluştu: ${AppException.messageOf(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingFile = false;
        });
      }
    }
  }

  Future<void> _startImport() async {
    if (kDebugMode) {
      debugPrint(
        'startImport clicked rows=${_importRows.length} strategy=$_strategy',
      );
    }

    if (_isApplyRunning) {
      return;
    }

    if (_importRows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Önce bir Excel dosyası seçin.'),
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isApplyRunning = true;
        _importSummary = null;
      });
    } else {
      _isApplyRunning = true;
      _importSummary = null;
    }

    final service = createCustomerImportService();

    try {
      // Önce validate çağrısı ile backend statülerini al.
      if (kDebugMode) {
        debugPrint(
          '[import] validate rows=${_importRows.length} strategy=$_strategy',
        );
      }
      final validateResult = await service.validate(
        _importRows,
        _selectedFileName ?? 'cari_import.xlsx',
        _strategy,
      );

      if (!mounted) return;

      final rowsReport =
          (validateResult['rows'] as List<dynamic>? ?? <dynamic>[]);
      final updatedRows = <CustomerImportRow>[];

      for (final row in _importRows) {
        final fromServer = rowsReport
            .cast<Map>()
            .map((e) => e.cast<String, dynamic>())
            .firstWhere(
              (e) => e['index'] == row.index,
              orElse: () => <String, dynamic>{},
            );

        if (fromServer.isEmpty) {
          updatedRows.add(row);
          continue;
        }

        final status = fromServer['status'] as String?;
        final issues = (fromServer['issues'] as List<dynamic>? ?? <dynamic>[])
            .map((e) => e.toString())
            .toList();

        updatedRows.add(
          row.copyWith(
            serverStatus: status,
            serverIssues: issues,
          ),
        );
      }

      setState(() {
        _importRows = updatedRows;
      });

      // Validate sonrası, server statülerine göre gerçekten işlenecek satır var mı kontrol et.
      final hasActionable = updatedRows.any((row) {
        final status = effectiveStatus(row, _strategy);
        return status == ImportRowStatus.newItem ||
            status == ImportRowStatus.willUpdate;
      });

      if (!hasActionable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İçe aktarılabilir satır bulunamadı.'),
          ),
        );
        return;
      }

      // Ardından apply çağrısı.
      if (kDebugMode) {
        debugPrint(
          '[import] apply rows=${_importRows.length} strategy=$_strategy',
        );
      }
      final applyResult = await service.apply(
        _importRows,
        _selectedFileName ?? 'cari_import.xlsx',
        _strategy,
      );

      if (!mounted) return;

      final summaryMap =
          (applyResult['summary'] as Map).cast<String, dynamic>();
      final batchId = applyResult['batch_id'] as String?;

      final total = summaryMap['total'] as int? ?? 0;
      final inserted = summaryMap['inserted'] as int? ?? 0;
      final updated = summaryMap['updated'] as int? ?? 0;
      final skipped = summaryMap['skipped'] as int? ?? 0;
      final errors = summaryMap['errors'] as int? ?? 0;

      setState(() {
        _lastBatchId = batchId;
        _importSummary = CustomerImportSummary(
          total: total,
          inserted: inserted,
          updated: updated,
          skipped: skipped,
          failed: errors,
        );
      });

      if (kDebugMode) {
        debugPrint(
          '[import] apply result summary={total:$total, inserted:$inserted, updated:$updated, skipped:$skipped, errors:$errors} batchId=$batchId',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cari içe aktarma işlemi tamamlandı.'),
        ),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('IMPORT ERROR: ${AppException.messageOf(e)}\n$st');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'İçe aktarma başarısız: ${AppException.messageOf(e)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isApplyRunning = false;
        });
      } else {
        _isApplyRunning = false;
      }
    }
  }

  Future<void> _downloadErrorReport() async {
    final batchId = _lastBatchId;
    if (batchId == null || !mounted) return;

    final service = createCustomerImportService();

    try {
      final items = await service.fetchErrorItems(batchId);
      if (!mounted) return;
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hata satırı bulunamadı.'),
          ),
        );
        return;
      }

      final excel = Excel.createExcel();
      final sheet = excel.sheets[excel.getDefaultSheet()]!;

      sheet.appendRow(
        _textRow(<String>['Satır No', 'Hata Nedeni', 'Cari Kodu', 'Ünvan', 'Telefon', 'Vergi No']),
      );

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final raw = (item['raw'] as Map).cast<String, dynamic>();

        final rowValues = <String?>[
          item['row_index']?.toString(),
          item['message']?.toString(),
          raw['customer_code']?.toString(),
          raw['trade_title']?.toString(),
          raw['phone']?.toString(),
          raw['tax_no']?.toString(),
        ];
        sheet.appendRow(_textRow(rowValues));
      }

      final bytes = excel.encode();
      if (bytes == null) return;

      if (!mounted) return;

      final now = DateTime.now();
      final yyyy = now.year.toString().padLeft(4, '0');
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final filename = 'cari_import_hata_${yyyy}_${mm}_$dd.xlsx';

      await saveBytesAsFile(
        Uint8List.fromList(bytes),
        filename,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        context,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Hata raporu oluşturulamadı: ${AppException.messageOf(e)}',
          ),
        ),
      );
    }
  }

}
