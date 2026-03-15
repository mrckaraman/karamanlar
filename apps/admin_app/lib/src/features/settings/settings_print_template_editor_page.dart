import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../utils/formatters_tr.dart';
import '../../utils/pdf_fonts.dart';
import 'print_template_config.dart';
import 'a5_classic_template.dart';

class SettingsPrintTemplateEditorPage extends StatefulWidget {
  const SettingsPrintTemplateEditorPage({
    super.key,
    required this.templateKey,
    required this.title,
    required this.isInvoice,
  });

  final String templateKey;
  final String title;
  final bool isInvoice;

  @override
  State<SettingsPrintTemplateEditorPage> createState() => _SettingsPrintTemplateEditorPageState();
}

class _SettingsPrintTemplateEditorPageState
    extends State<SettingsPrintTemplateEditorPage> {
  late PrintTemplateConfig _config;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await printTemplateConfigRepository.fetch(widget.templateKey);
    setState(() {
      _config = cfg;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    await printTemplateConfigRepository.save(_config);
    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    context.go('/settings/print');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Sol: form
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Şablon Ayarları',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _config.addressLine,
                      decoration: const InputDecoration(
                        labelText: 'Adres satırı (tek satır)',
                        hintText: 'Örn. DEMİRÇELİK (2. CADDE)',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _config = _config.copyWith(addressLine: value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Text('Kenar boşluğu (mm): ${_config.marginMm.toStringAsFixed(0)}'),
                    Slider(
                      min: 6,
                      max: 18,
                      divisions: 12,
                      value: _config.marginMm,
                      label: _config.marginMm.toStringAsFixed(0),
                      onChanged: (value) {
                        setState(() {
                          _config = _config.copyWith(marginMm: value);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('Temel font boyutu: ${_config.fontSizeBase.toStringAsFixed(1)}'),
                    Slider(
                      min: 7.5,
                      max: 10,
                      divisions: 10,
                      value: _config.fontSizeBase,
                      label: _config.fontSizeBase.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() {
                          _config = _config.copyWith(fontSizeBase: value);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Cari Önceki Bakiye göster'),
                      value: _config.showPrevBalance,
                      onChanged: (value) {
                        setState(() {
                          _config = _config.copyWith(showPrevBalance: value);
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Yeni Bakiye göster'),
                      value: _config.showNewBalance,
                      onChanged: (value) {
                        setState(() {
                          _config = _config.copyWith(showNewBalance: value);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text('Kolon genişlikleri (flex)'),
                    _buildFlexSlider(
                      label: 'Ürün Adı',
                      value: _config.colProductFlex,
                      onChanged: (v) =>
                          _updateFlex(colProductFlex: v),
                    ),
                    _buildFlexSlider(
                      label: 'Miktar',
                      value: _config.colQtyFlex,
                      onChanged: (v) => _updateFlex(colQtyFlex: v),
                    ),
                    _buildFlexSlider(
                      label: 'Birim',
                      value: _config.colUnitFlex,
                      onChanged: (v) => _updateFlex(colUnitFlex: v),
                    ),
                    _buildFlexSlider(
                      label: 'Birim Fiyat',
                      value: _config.colUnitPriceFlex,
                      onChanged: (v) => _updateFlex(colUnitPriceFlex: v),
                    ),
                    _buildFlexSlider(
                      label: 'Tutar',
                      value: _config.colTotalFlex,
                      onChanged: (v) => _updateFlex(colTotalFlex: v),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            // Sağ: PDF önizleme
            Expanded(
              flex: 3,
              child: _buildPreview(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlexSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}'),
        Slider(
          min: 0.5,
          max: 4,
          divisions: 7,
          value: value,
          label: value.toStringAsFixed(1),
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _updateFlex({
    double? colProductFlex,
    double? colQtyFlex,
    double? colUnitFlex,
    double? colUnitPriceFlex,
    double? colTotalFlex,
  }) {
    setState(() {
      _config = _config.copyWith(
        colProductFlex: colProductFlex,
        colQtyFlex: colQtyFlex,
        colUnitFlex: colUnitFlex,
        colUnitPriceFlex: colUnitPriceFlex,
        colTotalFlex: colTotalFlex,
      );
    });
  }

  Widget _buildPreview() {
    return PdfPreview(
      initialPageFormat: const PdfPageFormat(
        148 * PdfPageFormat.mm,
        210 * PdfPageFormat.mm,
      ),
      canChangePageFormat: false,
      allowPrinting: true,
      allowSharing: false,
      build: (format) => _buildPreviewPdf(format),
    );
  }

  Future<Uint8List> _buildPreviewPdf(PdfPageFormat format) async {
    final fontRegular = await PdfFonts.regular();
    final fontBold = await PdfFonts.bold();
    final theme = await PdfFonts.theme();

    final doc = pw.Document();

    final base = _config.fontSizeBase;

    AdminCompanySettings? company;
    try {
      company = await adminSettingsRepository.fetchCompanySettings();
    } catch (_) {}

    final companyTitle = (company?.companyTitle ?? '').trim();
    final companyAddress = (company?.address ?? '').trim();

    final items = <A5ClassicItem>[];
    double total = 0;
    for (var i = 0; i < 10; i++) {
      final qty = (i % 5) + 1;
      final unitPrice = 100 + i * 10;
      final lineTotal = qty * unitPrice;
      total += lineTotal;
      items.add(
        A5ClassicItem(
          name: 'Örnek Ürün ${i + 1}',
          qty: qty.toStringAsFixed(0),
          unit: 'ADET',
          unitPrice: formatMoney(unitPrice.toDouble()),
          lineTotal: formatMoney(lineTotal.toDouble()),
        ),
      );
    }

    final margin = _config.marginMm * PdfPageFormat.mm;
    final title = widget.isInvoice ? 'FATURA' : 'SİPARİŞ';

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin),
        theme: theme,
        header: (context) => a5BuildHeader(
          config: _config,
          fontRegular: fontRegular,
          fontBold: fontBold,
          baseFontSize: base,
          companyTitle: companyTitle,
          companyAddress: companyAddress,
          title: title,
          documentNo:
              widget.isInvoice ? 'FTR-000001' : 'SIP-000001',
          dateText: '15.02.2026',
          customerName: 'ÖRNEK CARİ LTD. ŞTİ.',
          customerAddress: _config.addressLine.isNotEmpty
              ? _config.addressLine
              : 'Örnek adres satırı 1',
        ),
        footer: (context) => _buildFooter(
          context,
          base,
          total,
          fontRegular: fontRegular,
          fontBold: fontBold,
        ),
        build: (context) => [
          a5BuildItemsHeader(
            config: _config,
            fontBold: fontBold,
            baseFontSize: base,
          ),
          a5BuildItemsBody(
            config: _config,
            fontRegular: fontRegular,
            baseFontSize: base,
            items: items,
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildFooter(
    pw.Context context,
    double base,
    double total, {
    required pw.Font fontRegular,
    required pw.Font fontBold,
  }) {
    if (context.pageNumber != context.pagesCount) {
      return pw.SizedBox();
    }

    final totalText = formatMoney(total.toDouble());

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: a5BuildTotals(
        config: _config,
        fontRegular: fontRegular,
        fontBold: fontBold,
        baseFontSize: base,
        totalText: totalText,
        previousBalanceText: formatMoney(0),
        newBalanceText: totalText,
      ),
    );
  }
}

