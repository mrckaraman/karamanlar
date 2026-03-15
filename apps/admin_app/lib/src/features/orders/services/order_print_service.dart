import 'package:core/core.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../utils/pdf_fonts.dart';

class OrderPrintService {
  static Future<void> printOrder(AdminOrderDetail detail) async {
    final fontRegular = await PdfFonts.regular();
    final fontBold = await PdfFonts.bold();
    final theme = await PdfFonts.theme();

    final pdf = pw.Document();

    final dateFmt = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
    final moneyFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final qtyFmt = NumberFormat.decimalPattern('tr_TR');

    String formatQty(double v) {
      final rounded = v.roundToDouble();
      if ((v - rounded).abs() < 0.0000001) {
        return qtyFmt.format(rounded.toInt());
      }
      return qtyFmt.format(v);
    }

    String formatMoney(double v) => moneyFmt.format(v);

    final orderNo = detail.orderNo;
    final orderLabel = orderNo != null ? 'Sipariş #$orderNo' : 'Sipariş';
    final dateText = dateFmt.format(detail.createdAt);

    final headers = <String>['Ürün', 'Miktar', 'Birim Fiyat', 'Tutar'];
    final rows = detail.items
        .map(
          (item) => <String>[
            item.name,
            '${formatQty(item.quantity)} ${item.unit}',
            formatMoney(item.unitPrice),
            formatMoney(item.lineTotal),
          ],
        )
        .toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: theme,
        build: (context) {
          return <pw.Widget>[
            pw.Text(
              'KARAMANLAR TİCARET',
              style: pw.TextStyle(
                fontSize: 18,
                font: fontBold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Sipariş Fişi',
              style: pw.TextStyle(
                fontSize: 14,
                font: fontBold,
              ),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    orderLabel,
                    style: pw.TextStyle(font: fontRegular),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Müşteri: ${detail.customerName}',
                    style: pw.TextStyle(font: fontRegular),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Tarih: $dateText',
                    style: pw.TextStyle(font: fontRegular),
                  ),
                  if ((detail.note ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Not: ${(detail.note ?? '').trim()}',
                      style: pw.TextStyle(font: fontRegular),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows,
              headerStyle: pw.TextStyle(
                fontSize: 10,
                font: fontBold,
              ),
              cellStyle: pw.TextStyle(
                fontSize: 10,
                font: fontRegular,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const <int, pw.TableColumnWidth>{
                0: pw.FlexColumnWidth(3.2),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(1.3),
                3: pw.FlexColumnWidth(1.3),
              },
              cellAlignments: const <int, pw.Alignment>{
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Toplam: ${formatMoney(detail.totalAmount)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  font: fontBold,
                ),
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }
}
