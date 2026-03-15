import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../customers/customer_general_tab.dart';
import '../../utils/formatters_tr.dart';
import '../../utils/pdf_fonts.dart';
import 'settings_roles.dart';
import 'print_template_config.dart';
import 'a5_classic_template.dart';

enum PrintTemplateTab { invoice, orderReceipt, general }
enum InvoiceTemplateType { a4, thermal }
enum LogoAlignment { left, center, right }
enum ThermalWidth { w58, w80 }
enum PrintFontSize { small, normal, large }
enum PrintLineDensity { tight, normal }
enum CutType { auto, manual }

class SettingsPrintTemplatesPage extends ConsumerStatefulWidget {
  const SettingsPrintTemplatesPage({super.key});

  @override
  ConsumerState<SettingsPrintTemplatesPage> createState() =>
      _SettingsPrintTemplatesPageState();
}

class _SettingsPrintTemplatesPageState
    extends ConsumerState<SettingsPrintTemplatesPage> {
  static const PdfPageFormat _a5Format =
      PdfPageFormat(148 * PdfPageFormat.mm, 210 * PdfPageFormat.mm);

  static pw.Font? _pdfBaseFont;
  static pw.Font? _pdfBoldFont;
  static bool _pdfFontsInitialized = false;

  bool _dirty = false;
  bool _saving = false;
  String? _errorText;

  // Örnek belge seçimleri için son 20 fatura / sipariş listesi
  List<AdminInvoiceListEntry> _invoiceExamples = const [];
  bool _invoiceExamplesLoading = false;
  String? _invoiceExamplesError;

  List<AdminOrderListEntry> _orderExamples = const [];
  bool _orderExamplesLoading = false;
  String? _orderExamplesError;

  String? _selectedInvoiceId;
  String? _selectedOrderId;

  // Yazıcı ayarları (şimdilik local, ileride sistem yazıcı listesi ile
  // doldurulacak.)
  final List<String> _availablePrinters = const [
    'Varsayılan Yazıcı',
    'Ofis Yazıcı 1',
    'Ofis Yazıcı 2',
  ];

  String? _invoicePrinter;
  String? _orderPrinter;
  bool _autoPrintOrders = false;
  double _printScale = 100;
  double _marginMm = 5;
  PrintTemplateConfig _invoiceTemplateConfig =
      PrintTemplateConfig.invoiceDefaults();
  PrintTemplateConfig _orderTemplateConfig =
      PrintTemplateConfig.orderDefaults();

  Future<void> _ensurePdfFontsLoaded() async {
    if (_pdfFontsInitialized) return;

    _pdfBaseFont = await PdfFonts.regular();
    _pdfBoldFont = await PdfFonts.bold();
    _pdfFontsInitialized = true;
  }

  @override
  void initState() {
    super.initState();
    if (_availablePrinters.isNotEmpty) {
      _invoicePrinter = _availablePrinters.first;
      _orderPrinter = _availablePrinters.first;
    }
    _loadExampleDocuments();
    _loadTemplateConfigs();
  }

  Future<void> _loadTemplateConfigs() async {
    try {
      final invoiceCfg =
          await printTemplateConfigRepository.fetch(
        PrintTemplateConfigRepository.invoiceKey,
      );
      final orderCfg =
          await printTemplateConfigRepository.fetch(
        PrintTemplateConfigRepository.orderKey,
      );

      setState(() {
        _invoiceTemplateConfig = invoiceCfg;
        _orderTemplateConfig = orderCfg;
      });
    } catch (_) {
      // Varsayılanlarla devam et.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const role = currentSettingsRole;
    const canEdit =
        role == AdminSettingsRole.owner || role == AdminSettingsRole.admin;

    return AppScaffold(
      title: 'Yazdırma ve Şablon Yönetimi',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              'Fatura ve sipariş A5 baskılarını yönetin, yazıcı davranışını kontrol edin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Rol: ${adminSettingsRoleLabel(role)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            if (!canEdit)
              const AppEmptyState(
                title: 'Bu ayara erişim yetkiniz yok.',
                subtitle:
                    'Yazdırma ve şablon ayarları yalnızca Owner ve Admin roller tarafından düzenlenebilir.',
              )
            else
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDocumentTemplatesSection(theme),
                      const SizedBox(height: AppSpacing.s24),
                      _buildPrintTestPanelSection(theme),
                      const SizedBox(height: AppSpacing.s24),
                      _buildPrinterSettingsSection(theme),
                      if (_errorText != null) ...[
                        const SizedBox(height: AppSpacing.s12),
                        Text(
                          _errorText!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.s20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: PrimaryButton(
                          label:
                              _saving ? 'Kaydediliyor...' : 'Ayarları Kaydet',
                          onPressed:
                              (!_dirty || _saving) ? null : _saveSettings,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s32),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _loadExampleDocuments() async {
    setState(() {
      _invoiceExamplesLoading = true;
      _orderExamplesLoading = true;
      _invoiceExamplesError = null;
      _orderExamplesError = null;
    });

    try {
      final invoices = await adminInvoiceRepository.fetchInvoices(status: 'all');
      setState(() {
        _invoiceExamples = invoices.length > 20
            ? invoices.take(20).toList()
            : invoices;
        _invoiceExamplesLoading = false;
      });
    } catch (e) {
      setState(() {
        _invoiceExamplesLoading = false;
        _invoiceExamplesError = 'Fatura listesi yüklenemedi: $e';
      });
    }

    try {
      final orders = await adminOrderRepository.fetchOrders(
        status: 'all',
        limit: 20,
      );
      setState(() {
        _orderExamples = orders;
        _orderExamplesLoading = false;
      });
    } catch (e) {
      setState(() {
        _orderExamplesLoading = false;
        _orderExamplesError = 'Sipariş listesi yüklenemedi: $e';
      });
    }
  }

  Widget _buildDocumentTemplatesSection(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final crossAxisCount = isWide ? 2 : 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 20),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  'Belge Şablonları',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: AppSpacing.s16,
              mainAxisSpacing: AppSpacing.s16,
              childAspectRatio: isWide ? 2.3 : 1.9,
              children: [
                _buildTemplateCard(
                  theme: theme,
                  icon: Icons.receipt_long_outlined,
                  title: 'Fatura A5',
                  description:
                      'KDV ve ara toplam içermeyen sade A5 fatura şablonu.',
                  selector: _buildInvoiceExampleSelector(theme),
                  helperText: _selectedInvoiceId == null
                      ? 'Önce bir örnek belge seçin.'
                      : null,
                  onPreview: () => _showA5Preview(
                    context,
                    isInvoice: true,
                  ),
                  onTestPrint: () => _printA5Test(
                    context,
                    isInvoice: true,
                  ),
                  onEdit: () => GoRouter.of(context)
                      .go('/settings/print/edit/invoice-a5'),
                ),
                _buildTemplateCard(
                  theme: theme,
                  icon: Icons.description_outlined,
                  title: 'Sipariş A5',
                  description:
                      'Teslim fişi formatında, sade A5 sipariş şablonu.',
                  selector: _buildOrderExampleSelector(theme),
                  helperText: _selectedOrderId == null
                      ? 'Önce bir örnek belge seçin.'
                      : null,
                  onPreview: () => _showA5Preview(
                    context,
                    isInvoice: false,
                  ),
                  onTestPrint: () => _printA5Test(
                    context,
                    isInvoice: false,
                  ),
                  onEdit: () => GoRouter.of(context)
                      .go('/settings/print/edit/order-a5'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPrintTestPanelSection(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding
(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.science_outlined, size: 20),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  'Baskı Test Paneli',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Farklı ürün sayıları ile A5 sayfa kırılımını test edin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Wrap(
              spacing: AppSpacing.s8,
              children: [
                OutlinedButton(
                  onPressed: () => _showA5TestPreview(context, 5),
                  child: const Text('Test 5 Ürün'),
                ),
                OutlinedButton(
                  onPressed: () => _showA5TestPreview(context, 30),
                  child: const Text('Test 30 Ürün'),
                ),
                OutlinedButton(
                  onPressed: () => _showA5TestPreview(context, 60),
                  child: const Text('Test 60 Ürün'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String description,
    Widget? selector,
    String? helperText,
    required VoidCallback? onPreview,
    required VoidCallback? onTestPrint,
    required VoidCallback? onEdit,
  }) {
    final color = theme.colorScheme.primary;

    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onPreview,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'A5 • Dikey',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color
                                ?.withValues(alpha: 0.8),
                          ),
                        ),
                        if (selector != null) ...[
                          const SizedBox(height: AppSpacing.s12),
                          selector,
                        ],
                        if (helperText != null) ...[
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            helperText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kağıt boyutu: A5'),
                        SizedBox(height: AppSpacing.s4),
                        Text('Yön: Dikey'),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s16),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Wrap(
                        spacing: AppSpacing.s8,
                        children: [
                          OutlinedButton(
                            onPressed: onPreview,
                            child: const Text('Önizleme'),
                          ),
                          OutlinedButton(
                            onPressed: onTestPrint,
                            child: const Text('Test Yazdır'),
                          ),
                          OutlinedButton(
                            onPressed: onEdit,
                            child: const Text('Düzenle'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceExampleSelector(ThemeData theme) {
    if (_invoiceExamplesLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            'Son faturalar yükleniyor...',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    if (_invoiceExamplesError != null) {
      return Text(
        _invoiceExamplesError!,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    if (_invoiceExamples.isEmpty) {
      return Text(
        'Son örnek fatura bulunamadı.',
        style: theme.textTheme.bodySmall,
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedInvoiceId,
      decoration: const InputDecoration(
        labelText: 'Örnek Fatura',
      ),
      items: _invoiceExamples
          .map(
            (e) => DropdownMenuItem<String>(
              value: e.id,
              child: Text(
                '${e.invoiceNo.isNotEmpty ? e.invoiceNo : 'Fatura'} • '
                '${formatDate(e.issuedAt)} • '
                '${e.customerName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedInvoiceId = value;
        });
      },
    );
  }

  Widget _buildOrderExampleSelector(ThemeData theme) {
    if (_orderExamplesLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.s8),
          Text(
            'Son siparişler yükleniyor...',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }

    if (_orderExamplesError != null) {
      return Text(
        _orderExamplesError!,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    if (_orderExamples.isEmpty) {
      return Text(
        'Son örnek sipariş bulunamadı.',
        style: theme.textTheme.bodySmall,
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedOrderId,
      decoration: const InputDecoration(
        labelText: 'Örnek Sipariş',
      ),
      items: _orderExamples
          .map(
            (e) => DropdownMenuItem<String>(
              value: e.id,
              child: Text(
                '${e.orderNo != null ? 'SIP-${e.orderNo!.toString().padLeft(6, '0')}' : 'Sipariş'} • '
                '${formatDate(e.createdAt)} • '
                '${e.customerName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedOrderId = value;
        });
      },
    );
  }

  Widget _buildPrinterSettingsSection(ThemeData theme) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.print_outlined, size: 20),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  'Yazıcı Ayarları',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = AppResponsive.gridColumnsForWidth(
                  width,
                  mobile: 1,
                  tablet: 2,
                  desktop: 2,
                );
                const spacing = AppSpacing.s16;
                final columnWidth =
                    (width - (spacing * (columns - 1))) / columns;

                Widget field(Widget child) {
                  return SizedBox(width: columnWidth, child: child);
                }

                return Wrap(
                  spacing: spacing,
                  runSpacing: AppSpacing.s12,
                  children: [
                    field(
                      DropdownButtonFormField<String>(
                        key: ValueKey(_invoicePrinter),
                        initialValue: _invoicePrinter,
                        decoration: const InputDecoration(
                          labelText: 'Fatura Yazıcısı',
                        ),
                        items: _availablePrinters
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _invoicePrinter = value;
                            _dirty = true;
                          });
                        },
                      ),
                    ),
                    field(
                      DropdownButtonFormField<String>(
                        key: ValueKey(_orderPrinter),
                        initialValue: _orderPrinter,
                        decoration: const InputDecoration(
                          labelText: 'Sipariş Yazıcısı',
                        ),
                        items: _availablePrinters
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _orderPrinter = value;
                            _dirty = true;
                          });
                        },
                      ),
                    ),
                    field(
                      Row(
                        children: [
                          Switch(
                            value: _autoPrintOrders,
                            onChanged: (value) {
                              setState(() {
                                _autoPrintOrders = value;
                                _dirty = true;
                              });
                            },
                          ),
                          const SizedBox(width: AppSpacing.s4),
                          const Expanded(
                            child: Text(
                              'Otomatik sipariş yazdır',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_autoPrintOrders) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                'Sistem yeni siparişleri arka planda dinler ve yazıcıya gönderir.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color
                      ?.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Not: Supabase stream ile sipariş oluşturma olaylarını dinleyip seçili yazıcıya otomatik gönderme entegrasyonu planlanıyor.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary.withValues(alpha: 0.9),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s16),
            _buildScaleAndMarginRow(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildScaleAndMarginRow(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = AppResponsive.gridColumnsForWidth(
          width,
          mobile: 1,
          tablet: 2,
          desktop: 2,
        );
        const spacing = AppSpacing.s16;
        final columnWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: AppSpacing.s12,
          children: [
            SizedBox(
              width: columnWidth,
              child: TextFormField(
                initialValue: _printScale.toStringAsFixed(0),
                decoration: const InputDecoration(
                  labelText: 'Yazdırma ölçeği (%)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed =
                      double.tryParse(value.replaceAll(',', '.'));
                  if (parsed == null) return;
                  setState(() {
                    _printScale = parsed.clamp(10, 300);
                    _dirty = true;
                  });
                },
              ),
            ),
            SizedBox(
              width: columnWidth,
              child: TextFormField(
                initialValue: _marginMm.toStringAsFixed(0),
                decoration: const InputDecoration(
                  labelText: 'Kenar boşluğu (mm)',
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed =
                      double.tryParse(value.replaceAll(',', '.'));
                  if (parsed == null) return;
                  setState(() {
                    _marginMm = parsed.clamp(0, 50);
                    _dirty = true;
                  });
                },
              ),
            ),
          ],
        );
      },
    );
  }
  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });

    // Şimdilik sadece local state, Supabase entegrasyonu daha sonra.
    // Burada yazıcı seçimi, ölçek ve otomatik yazdırma bayrağı
    // Supabase / edge functions ayar tablosuna yazılabilir.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    setState(() {
      _saving = false;
      _dirty = false;
    });
  }

  void _showInfoSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<Uint8List> _buildInvoiceA5Pdf(
    PdfPageFormat format, {
    required PrintTemplateConfig config,
    required String documentNo,
    required String dateText,
    required String customerName,
    required String customerAddress,
    required String totalText,
    required String previousBalanceText,
    required String newBalanceText,
    required List<A5ClassicItem> items,
  }) async {
    AdminCompanySettings? company;
    try {
      company = await adminSettingsRepository.fetchCompanySettings();
    } catch (_) {}

    final companyTitle = (company?.companyTitle ?? '').trim();
    final companyAddress = (company?.address ?? '').trim();

    return _buildA5Pdf(
      format,
      config: config,
      companyTitle: companyTitle,
      companyAddress: companyAddress,
      title: 'FATURA',
      documentNo: documentNo,
      dateText: dateText,
      customerName: customerName,
      customerAddress: customerAddress,
      totalText: totalText,
      previousBalanceText: previousBalanceText,
      newBalanceText: newBalanceText,
      items: items,
    );
  }

  Future<Uint8List> _buildOrderA5Pdf(
    PdfPageFormat format, {
    required PrintTemplateConfig config,
    required String documentNo,
    required String dateText,
    required String customerName,
    required String customerAddress,
    required String totalText,
    required String previousBalanceText,
    required String newBalanceText,
    required List<A5ClassicItem> items,
  }) async {
    AdminCompanySettings? company;
    try {
      company = await adminSettingsRepository.fetchCompanySettings();
    } catch (_) {}

    final companyTitle = (company?.companyTitle ?? '').trim();
    final companyAddress = (company?.address ?? '').trim();

    return _buildA5Pdf(
      format,
      config: config,
      companyTitle: companyTitle,
      companyAddress: companyAddress,
      title: 'SİPARİŞ',
      documentNo: documentNo,
      dateText: dateText,
      customerName: customerName,
      customerAddress: customerAddress,
      totalText: totalText,
      previousBalanceText: previousBalanceText,
      newBalanceText: newBalanceText,
      items: items,
    );
  }

  Future<Uint8List> _buildA5Pdf(
    PdfPageFormat format, {
    required PrintTemplateConfig config,
    required String companyTitle,
    required String companyAddress,
    required String title,
    required String documentNo,
    required String dateText,
    required String customerName,
    required String customerAddress,
    required String totalText,
    required String previousBalanceText,
    required String newBalanceText,
    required List<A5ClassicItem> items,
  }) async {
    await _ensurePdfFontsLoaded();

    final fontRegular = _pdfBaseFont!;
    final fontBold = _pdfBoldFont!;

    final baseFontSize = config.fontSizeBase;

    final theme = pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
    );

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: pw.EdgeInsets.all(config.marginMm * PdfPageFormat.mm),
        theme: theme,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            a5BuildHeader(
              config: config,
              fontRegular: fontRegular,
              fontBold: fontBold,
              baseFontSize: baseFontSize,
              companyTitle: companyTitle,
              companyAddress: companyAddress,
              title: title,
              documentNo: documentNo,
              dateText: dateText,
              customerName: customerName,
              customerAddress: customerAddress,
            ),
            pw.SizedBox(height: 8),
            a5BuildItemsHeader(
              config: config,
              fontBold: fontBold,
              baseFontSize: baseFontSize,
            ),
            pw.SizedBox(height: 4),
          ],
        ),
        footer: (context) {
          if (context.pageNumber != context.pagesCount) {
            return pw.SizedBox();
          }
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 8),
              a5BuildTotals(
                config: config,
                fontRegular: fontRegular,
                fontBold: fontBold,
                baseFontSize: baseFontSize,
                totalText: totalText,
                previousBalanceText: previousBalanceText,
                newBalanceText: newBalanceText,
              ),
            ],
          );
        },
        build: (context) => [
          a5BuildItemsBody(
            config: config,
            fontRegular: fontRegular,
            baseFontSize: baseFontSize,
            items: items,
          ),
        ],
      ),
    );

    return doc.save();
  }


  Future<Uint8List> _buildA5TestPdf(
    PdfPageFormat format,
    int itemCount,
  ) async {
    final now = DateTime.now();

    final List<A5ClassicItem> items = [];
    double total = 0;

    for (var i = 0; i < itemCount; i++) {
      final index = i + 1;
      final qty = (index % 5) + 1;
      final unitPrice = 100 + index * 5;
      final lineTotal = qty * unitPrice;
      total += lineTotal;

      items.add(
        A5ClassicItem(
          name: 'Test Ürün ${index.toString().padLeft(2, '0')}',
          qty: qty.toStringAsFixed(0),
          unit: 'adet',
          unitPrice: formatMoney(unitPrice),
          lineTotal: formatMoney(lineTotal),
        ),
      );
    }

    final totalText = formatMoney(total);
    final previousBalanceText = formatMoney(0);
    final newBalanceText = totalText;
    AdminCompanySettings? company;
    try {
      company = await adminSettingsRepository.fetchCompanySettings();
    } catch (_) {}

    final companyTitle = (company?.companyTitle ?? '').trim();
    final companyAddress = (company?.address ?? '').trim();

    return _buildA5Pdf(
      format,
      config: _invoiceTemplateConfig,
      companyTitle: companyTitle,
      companyAddress: companyAddress,
      title: 'A5 TEST',
      documentNo: 'TEST-$itemCount',
      dateText: formatDate(now),
      customerName: 'Test Cari',
      customerAddress: 'Test adres satırı 1\nTest adres satırı 2',
      totalText: totalText,
      previousBalanceText: previousBalanceText,
      newBalanceText: newBalanceText,
      items: items,
    );
  }

  Future<Uint8List> _buildInvoicePdfFromId(
    String invoiceId,
    PdfPageFormat format,
  ) async {
    final detail = await adminInvoiceRepository.fetchInvoiceById(invoiceId);
    final items = await adminInvoiceRepository.fetchInvoiceItems(invoiceId);

    String customerName = 'Bilinmeyen Cari';
    String customerAddress = '';

    final customerId = detail.customerId;
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final customer = await ref
            .read(customerDetailProvider(customerId).future);
        customerName = customer.name;
        customerAddress = (customer.address ?? '').trim();
      } catch (_) {}
    }

    final effectiveDate = detail.invoiceDate ??
        detail.issuedAt ??
        detail.createdAt ??
        DateTime.now();

    final total = detail.totalAmount;
    double previousBalance = 0;
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final balanceAtDate = await adminCustomerLedgerRepository
            .fetchCustomerBalanceAt(customerId, effectiveDate);
        previousBalance = balanceAtDate.net;
      } catch (_) {}
    }
    final newBalance = previousBalance + total;

    final dateText = formatDate(effectiveDate);
    final totalText = formatMoney(total);
    final previousBalanceText = formatMoney(previousBalance);
    final newBalanceText = formatMoney(newBalance);

    final pdfItems = items
        .map(
          (e) => A5ClassicItem(
            name: e.stockName,
            qty: e.qty % 1 == 0
                ? e.qty.toStringAsFixed(0)
                : e.qty.toStringAsFixed(2),
            unit: e.unitName,
            unitPrice: formatMoney(e.unitPrice),
            lineTotal: formatMoney(e.lineTotal),
          ),
        )
        .toList();

    final documentNo =
        detail.invoiceNo.isNotEmpty ? detail.invoiceNo : 'Fatura';

    return _buildInvoiceA5Pdf(
      format,
      config: _invoiceTemplateConfig,
      documentNo: documentNo,
      dateText: dateText,
      customerName: customerName,
      customerAddress:
          customerAddress.isNotEmpty ? customerAddress : 'Adres bilgisi bulunamadı.',
      totalText: totalText,
      previousBalanceText: previousBalanceText,
      newBalanceText: newBalanceText,
      items: pdfItems,
    );
  }

  Future<Uint8List> _buildOrderPdfFromId(
    String orderId,
    PdfPageFormat format,
  ) async {
    final detail = await adminOrderRepository.fetchOrderDetail(orderId);

    String customerName = detail.customerName;
    String customerAddress = '';
    double previousBalance = 0;

    final customerId = detail.customerId;
    if (customerId != null && customerId.isNotEmpty) {
      try {
        final customer = await ref
            .read(customerDetailProvider(customerId).future);
        customerName = customer.name;
        customerAddress = (customer.address ?? '').trim();
      } catch (_) {}

      try {
        final balanceAtDate = await adminCustomerLedgerRepository
            .fetchCustomerBalanceAt(customerId, detail.createdAt);
        previousBalance = balanceAtDate.net;
      } catch (_) {}
    }

    final total = detail.totalAmount;
    final newBalance = previousBalance + total;

    final dateText = formatDate(detail.createdAt);
    final totalText = formatMoney(total);
    final previousBalanceText = formatMoney(previousBalance);
    final newBalanceText = formatMoney(newBalance);

    final pdfItems = detail.items
        .map(
          (e) => A5ClassicItem(
            name: e.name,
            qty: e.quantity % 1 == 0
                ? e.quantity.toStringAsFixed(0)
                : e.quantity.toStringAsFixed(2),
            unit: e.unit,
            unitPrice: formatMoney(e.unitPrice),
            lineTotal: formatMoney(e.lineTotal),
          ),
        )
        .toList();

    final String documentNo;
    if (detail.orderNo != null) {
      documentNo =
          'SIP-${detail.orderNo!.toString().padLeft(6, '0')}';
    } else {
      documentNo = 'Sipariş';
    }

    return _buildOrderA5Pdf(
      format,
      config: _orderTemplateConfig,
      documentNo: documentNo,
      dateText: dateText,
      customerName: customerName,
      customerAddress:
          customerAddress.isNotEmpty ? customerAddress : 'Adres bilgisi bulunamadı.',
      totalText: totalText,
      previousBalanceText: previousBalanceText,
      newBalanceText: newBalanceText,
      items: pdfItems,
    );
  }

  void _showA5TestPreview(BuildContext context, int itemCount) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext).size;
        final height = media.height * 0.8;
        final width = media.width >= 920 ? 900.0 : media.width * 0.95;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: width,
              height: height,
              child: PdfPreview(
                build: (format) => _buildA5TestPdf(format, itemCount),
                initialPageFormat: _a5Format,
                canChangePageFormat: false,
                allowPrinting: true,
                allowSharing: false,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showA5Preview(BuildContext context, {required bool isInvoice}) {
    final selectedId =
        isInvoice ? _selectedInvoiceId : _selectedOrderId;

    if (selectedId == null || selectedId.isEmpty) {
      _showInfoSnack(context, 'Önce bir örnek belge seçin.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext).size;
        final height = media.height * 0.8;
        final width = media.width >= 920 ? 900.0 : media.width * 0.95;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: width,
              height: height,
              child: PdfPreview(
                build: (format) => isInvoice
                    ? _buildInvoicePdfFromId(selectedId, format)
                    : _buildOrderPdfFromId(selectedId, format),
                initialPageFormat: _a5Format,
                canChangePageFormat: false,
                allowPrinting: true,
                allowSharing: false,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _printA5Test(BuildContext context, {required bool isInvoice}) async {
    final selectedId =
        isInvoice ? _selectedInvoiceId : _selectedOrderId;

    if (selectedId == null || selectedId.isEmpty) {
      _showInfoSnack(context, 'Önce bir örnek belge seçin.');
      return;
    }

    try {
      await Printing.layoutPdf(
        format: _a5Format,
        onLayout: (_) => isInvoice
            ? _buildInvoicePdfFromId(selectedId, _a5Format)
            : _buildOrderPdfFromId(selectedId, _a5Format),
      );
    } catch (e) {
      if (!context.mounted) return;
      _showInfoSnack(context, 'Yazdırma sırasında hata oluştu: $e');
    }
  }
}

