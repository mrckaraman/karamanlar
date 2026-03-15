import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'print_template_config.dart';

class A5ClassicItem {
  const A5ClassicItem({
    required this.name,
    required this.qty,
    required this.unit,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final String qty;
  final String unit;
  final String unitPrice;
  final String lineTotal;
}

class A5ClassicLayout {
  const A5ClassicLayout._();

  static double labelFontSize(double base) => base * 0.95;
  static double valueFontSize(double base) => base;
  static double titleFontSize(double base) => base * 1.8;

  static String _firstLine(String? text) {
    if (text == null || text.trim().isEmpty) return '';
    return text.split(RegExp(r'\r?\n')).first.trim();
  }

  /// Müşteri adresi için tek satır seçimi.
  /// Önce config.addressLine, yoksa customerAddress'in ilk satırı.
  static String customerAddressLine(
    PrintTemplateConfig config,
    String customerAddress,
  ) {
    final override = _firstLine(config.addressLine);
    if (override.isNotEmpty) return override;
    return _firstLine(customerAddress);
  }

  /// Şirket adresini tek satıra indirger.
  static String companyAddressLine(String address) => _firstLine(address);
}

pw.Widget a5BuildHeader({
  required PrintTemplateConfig config,
  required pw.Font fontRegular,
  required pw.Font fontBold,
  required double baseFontSize,
  required String companyTitle,
  required String companyAddress,
  required String title,
  required String documentNo,
  required String dateText,
  required String customerName,
  required String customerAddress,
}) {
  final effectiveCompanyTitle =
      companyTitle.trim().isNotEmpty ? companyTitle.trim() : 'ŞİRKET ÜNVANI';
  final effectiveCompanyAddress =
      A5ClassicLayout.companyAddressLine(companyAddress);

  final label = A5ClassicLayout.labelFontSize(baseFontSize);
  final value = A5ClassicLayout.valueFontSize(baseFontSize);
  final titleSize = A5ClassicLayout.titleFontSize(baseFontSize);

  final resolvedCustomerAddress =
      A5ClassicLayout.customerAddressLine(config, customerAddress);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  effectiveCompanyTitle,
                  style: pw.TextStyle(
                    fontSize: value,
                    font: fontBold,
                  ),
                ),
                if (effectiveCompanyAddress.isNotEmpty)
                  pw.Text(
                    effectiveCompanyAddress,
                    style: pw.TextStyle(
                      fontSize: label,
                      font: fontRegular,
                    ),
                  ),
              ],
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Center(
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: titleSize,
                  font: fontBold,
                ),
              ),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Tarih : $dateText',
                  style: pw.TextStyle(
                    fontSize: label,
                    font: fontRegular,
                  ),
                ),
                pw.Text(
                  'Belge No : $documentNo',
                  style: pw.TextStyle(
                    fontSize: label,
                    font: fontRegular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Müşteri / Ticari Ünvan',
            style: pw.TextStyle(
              fontSize: label,
              font: fontRegular,
            ),
          ),
          pw.Text(
            customerName,
            style: pw.TextStyle(
              fontSize: value + 0.5,
              font: fontBold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Adres',
            style: pw.TextStyle(
              fontSize: label,
              font: fontRegular,
            ),
          ),
          pw.Text(
            resolvedCustomerAddress,
            style: pw.TextStyle(
              fontSize: value,
              font: fontRegular,
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget a5BuildItemsHeader({
  required PrintTemplateConfig config,
  required pw.Font fontBold,
  required double baseFontSize,
}) {
  final headers = [
    'Ürün Adı',
    'Miktar',
    'Birim',
    'Birim Fiyat',
    'Tutar',
  ];

  return pw.Table(
    border: const pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.grey700),
      top: pw.BorderSide(width: 0.6, color: PdfColors.grey700),
      right: pw.BorderSide(width: 0.6, color: PdfColors.grey700),
      bottom: pw.BorderSide.none,
    ),
    columnWidths: {
      0: pw.FlexColumnWidth(config.colProductFlex),
      1: pw.FlexColumnWidth(config.colQtyFlex),
      2: pw.FlexColumnWidth(config.colUnitFlex),
      3: pw.FlexColumnWidth(config.colUnitPriceFlex),
      4: pw.FlexColumnWidth(config.colTotalFlex),
    },
    children: [
      pw.TableRow(
        children: [
          for (final h in headers)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 4,
                horizontal: 4,
              ),
              child: pw.Text(
                h,
                style: pw.TextStyle(
                  fontSize: baseFontSize,
                  font: fontBold,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

pw.Widget a5BuildItemsBody({
  required PrintTemplateConfig config,
  required pw.Font fontRegular,
  required double baseFontSize,
  required List<A5ClassicItem> items,
}) {
  return pw.Table(
    border: const pw.TableBorder(
      left: pw.BorderSide(width: 0.6, color: PdfColors.grey700),
      top: pw.BorderSide.none,
      right: pw.BorderSide(width: 0.6, color: PdfColors.grey700),
      bottom: pw.BorderSide(width: 0.6, color: PdfColors.grey700),
    ),
    columnWidths: {
      0: pw.FlexColumnWidth(config.colProductFlex),
      1: pw.FlexColumnWidth(config.colQtyFlex),
      2: pw.FlexColumnWidth(config.colUnitFlex),
      3: pw.FlexColumnWidth(config.colUnitPriceFlex),
      4: pw.FlexColumnWidth(config.colTotalFlex),
    },
    children: [
      for (final item in items)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  item.name,
                  style: pw.TextStyle(
                    fontSize: baseFontSize,
                    font: fontRegular,
                  ),
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  item.qty,
                  style: pw.TextStyle(
                    fontSize: baseFontSize,
                    font: fontRegular,
                  ),
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  item.unit,
                  style: pw.TextStyle(
                    fontSize: baseFontSize,
                    font: fontRegular,
                  ),
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  item.unitPrice,
                  style: pw.TextStyle(
                    fontSize: baseFontSize,
                    font: fontRegular,
                  ),
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  item.lineTotal,
                  style: pw.TextStyle(
                    fontSize: baseFontSize,
                    font: fontRegular,
                  ),
                ),
              ),
            ),
          ],
        ),
    ],
  );
}

pw.Widget a5BuildTotals({
  required PrintTemplateConfig config,
  required pw.Font fontRegular,
  required pw.Font fontBold,
  required double baseFontSize,
  required String totalText,
  required String previousBalanceText,
  required String newBalanceText,
}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 3,
        child: pw.Text(
          'Yalnız: $totalText',
          style: pw.TextStyle(
            fontSize: baseFontSize,
            font: fontRegular,
          ),
        ),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(
        flex: 2,
        child: pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
              width: 0.6,
              color: PdfColors.grey700,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Genel Toplam',
                    style: pw.TextStyle(
                      fontSize: baseFontSize,
                      font: fontBold,
                    ),
                  ),
                  pw.Text(
                    totalText,
                    style: pw.TextStyle(
                      fontSize: baseFontSize,
                      font: fontBold,
                    ),
                  ),
                ],
              ),
              if (config.showPrevBalance)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Cari Önceki Bakiye',
                      style: pw.TextStyle(
                        fontSize: baseFontSize,
                        font: fontRegular,
                      ),
                    ),
                    pw.Text(
                      previousBalanceText,
                      style: pw.TextStyle(
                        fontSize: baseFontSize,
                        font: fontRegular,
                      ),
                    ),
                  ],
                ),
              if (config.showNewBalance)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Yeni Bakiye',
                      style: pw.TextStyle(
                        fontSize: baseFontSize,
                        font: fontBold,
                      ),
                    ),
                    pw.Text(
                      newBalanceText,
                      style: pw.TextStyle(
                        fontSize: baseFontSize,
                        font: fontBold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
