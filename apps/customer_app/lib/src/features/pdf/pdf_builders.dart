import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../utils/formatters_tr.dart';
import '../invoices/services/pdf_fonts.dart';

class InvoicePdfHeader {
  const InvoicePdfHeader({
    required this.invoiceNo,
    required this.date,
    required this.total,
    required this.paid,
    required this.remaining,
  });

  final String invoiceNo;
  final DateTime date;
  final double total;
  final double paid;
  final double remaining;
}

class InvoicePdfItem {
  const InvoicePdfItem({
    required this.name,
    required this.qty,
    required this.unitName,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String name;
  final double qty;
  final String unitName;
  final double unitPrice;
  final double lineTotal;
}

class StatementPdfRow {
  const StatementPdfRow({
    required this.date,
    required this.type,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final DateTime date;
  final String type;
  final String description;
  final double debit;
  final double credit;
  final double balance;
}

class StatementHeaderInfo {
  const StatementHeaderInfo({
    required this.customerName,
    required this.rangeLabel,
    required this.currentBalance,
    required this.totalDebit,
    required this.totalCredit,
    required this.net,
  });

  final String customerName;
  final String rangeLabel;
  final double currentBalance;
  final double totalDebit;
  final double totalCredit;
  final double net;
}

Future<Uint8List> buildInvoicePdf(
  InvoicePdfHeader invoice,
  List<InvoicePdfItem> items,
  String customerName,
) async {
  final fonts = await PdfFonts.load();
  final theme = pw.ThemeData.withFont(
    base: fonts.regular,
    bold: fonts.bold,
  );

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) {
        final dateText = formatDate(invoice.date);
        final totalText = formatMoney(invoice.total);
        final paidText = formatMoney(invoice.paid);
        final remainingText =
            formatMoney(invoice.remaining.clamp(0, double.infinity));

        return [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Fatura ${invoice.invoiceNo.isEmpty ? '' : invoice.invoiceNo}',
                    style: pw.TextStyle(
                      fontSize: 18,
                      font: fonts.bold,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text('Tarih: $dateText'),
                  pw.SizedBox(height: 4),
                  pw.Text('Cari: ${customerName.isEmpty ? '- ' : customerName}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              _metricBox('Toplam', totalText, fonts: fonts),
              pw.SizedBox(width: 8),
              _metricBox('Ödenen', paidText, fonts: fonts),
              pw.SizedBox(width: 8),
              _metricBox('Kalan', remainingText, fonts: fonts),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Kalemler',
            style: pw.TextStyle(
              fontSize: 12,
              font: fonts.bold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          if (items.isEmpty)
            pw.Text('Bu fatura için kalem bulunamadı.')
          else
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'Ürün',
                'Miktar',
                'Birim',
                'Fiyat',
                'Tutar',
              ],
              headerStyle: pw.TextStyle(
                font: fonts.bold,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(
                font: fonts.regular,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE0E0E0),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              data: items
                  .map(
                    (e) => [
                      e.name,
                      _formatQuantity(e.qty),
                      e.unitName,
                      formatMoney(e.unitPrice),
                      formatMoney(e.lineTotal),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Genel Toplam: $totalText',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ];
      },
    ),
  );

  return doc.save();
}

Future<Uint8List> buildStatementPdf(
  List<StatementPdfRow> statementRows,
  StatementHeaderInfo headerInfo,
) async {
  final fonts = await PdfFonts.load();
  final theme = pw.ThemeData.withFont(
    base: fonts.regular,
    bold: fonts.bold,
  );

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) {
        final balanceText = formatMoney(headerInfo.currentBalance);
        final totalDebitText = formatMoney(headerInfo.totalDebit);
        final totalCreditText = formatMoney(headerInfo.totalCredit);
        final netText = formatMoney(headerInfo.net);

        String formatStatementDate(DateTime date) => formatDateTime(date);

        return [
          pw.Text(
            'Cari Ekstre',
            style: pw.TextStyle(
              fontSize: 18,
              font: fonts.bold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Cari: ${headerInfo.customerName}'),
          pw.Text('Aralık: ${headerInfo.rangeLabel}'),
          pw.SizedBox(height: 8),
          pw.Text('Güncel Bakiye: $balanceText'),
          pw.SizedBox(height: 16),
          if (statementRows.isEmpty)
            pw.Text('Seçilen aralıkta hareket bulunamadı.')
          else
            pw.TableHelper.fromTextArray(
              headers: const <String>[
                'Tarih',
                'Tür',
                'Açıklama',
                'Borç',
                'Alacak',
                'Bakiye',
              ],
              headerStyle: pw.TextStyle(
                font: fonts.bold,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(
                font: fonts.regular,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFE0E0E0),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              data: statementRows
                  .map(
                    (e) => [
                      formatStatementDate(e.date),
                      e.type,
                      e.description,
                      formatMoney(e.debit),
                      formatMoney(e.credit),
                      formatMoney(e.balance),
                    ],
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Toplam Borç: $totalDebitText'),
                  pw.Text('Toplam Alacak: $totalCreditText'),
                  pw.Text(
                    'Net: $netText',
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ];
      },
    ),
  );

  return doc.save();
}

pw.Widget _metricBox(
  String title,
  String value, {
  required PdfFontBundle fonts,
}) {
  return pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(
          color: PdfColor.fromInt(0xFFE0E0E0),
          width: 1,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 10,
              font: fonts.regular,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 12,
              font: fonts.bold,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

String _formatQuantity(double value) {
  if (value % 1 == 0) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(2);
}
