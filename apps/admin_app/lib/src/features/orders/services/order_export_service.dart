import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../utils/pdf_fonts.dart';

class OrderExportFile {
  const OrderExportFile({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

class OrderExportService {
  OrderExportService({
    required AdminOrderRepository adminOrderRepository,
  }) : _repo = adminOrderRepository;

  final AdminOrderRepository _repo;

  static String buildTimestampedFileName({
    required String prefix,
    required String extension,
    DateTime? now,
  }) {
    final dt = now ?? DateTime.now();
    final ts = DateFormat('yyyy-MM-dd_HH-mm', 'tr_TR').format(dt);
    return '${prefix}_$ts.$extension';
  }

  Future<OrderExportFile> buildCsv({
    required List<AdminOrderListEntry> orders,
    DateTime? now,
  }) async {
    final fileName = buildTimestampedFileName(
      prefix: 'siparisler',
      extension: 'csv',
      now: now,
    );

    final rows = <List<String>>[
      <String>[
        'order_no',
        'created_at',
        'customer_name',
        'status',
        'total_amount',
        'note',
        'items_count',
      ],
    ];

    final dateFmt = DateFormat('yyyy-MM-dd HH:mm', 'tr_TR');

    for (final order in orders) {
      final items = await _repo.fetchOrderItems(order.id);
      final itemsCount = items.length;

      rows.add(
        <String>[
          (order.orderNo ?? '').toString(),
          dateFmt.format(order.createdAt.toLocal()),
          order.customerName,
          order.status,
          order.totalAmount.toStringAsFixed(2),
          (order.note ?? '').trim(),
          itemsCount.toString(),
        ],
      );
    }

    final csv = _toCsv(rows);

    // Excel-friendly UTF-8 BOM.
    final content = '\uFEFF$csv';
    final bytes = Uint8List.fromList(utf8.encode(content));

    return OrderExportFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'text/csv',
    );
  }

  Future<OrderExportFile> buildPdf({
    required List<AdminOrderListEntry> orders,
    DateTime? now,
    PdfPageFormat? pageFormat,
  }) async {
    final fileName = buildTimestampedFileName(
      prefix: 'siparisler',
      extension: 'pdf',
      now: now,
    );

    final details = await _fetchDetails(orders);

    final fontRegular = await PdfFonts.regular();
    final fontBold = await PdfFonts.bold();
    final theme = await PdfFonts.theme();

    final pdf = pw.Document();
    final fmtDate = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');
    final moneyFmt = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

    String formatMoney(double v) => moneyFmt.format(v);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat ?? PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: theme,
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text(
              'Karamanlar Ticaret – Sipariş Listesi',
              style: pw.TextStyle(
                fontSize: 16,
                font: fontBold,
              ),
            ),
            pw.SizedBox(height: 12),
          ];

          for (final d in details) {
            final orderNoText = d.orderNo != null ? '#${d.orderNo}' : d.id;
            final statusText = _statusLabelTr(d.status);
            final dateText = fmtDate.format(d.createdAt.toLocal());

            widgets.add(
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Sipariş $orderNoText',
                                style: pw.TextStyle(
                                  font: fontBold,
                                ),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Müşteri: ${d.customerName}',
                                style: pw.TextStyle(font: fontRegular),
                              ),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                'Tarih: $dateText',
                                style: pw.TextStyle(font: fontRegular),
                              ),
                              if ((d.note ?? '').trim().isNotEmpty) ...[
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'Not: ${(d.note ?? '').trim()}',
                                  style: pw.TextStyle(font: fontRegular),
                                ),
                              ],
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text(
                              'Durum: $statusText',
                              style: pw.TextStyle(font: fontRegular),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'Tutar: ${formatMoney(d.totalAmount)}',
                              style: pw.TextStyle(
                                font: fontBold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.TableHelper.fromTextArray(
                      headers: const <String>['Ürün', 'Adet', 'Birim'],
                      data: d.items
                          .map(
                            (i) => <String>[
                              i.name,
                              i.quantity.toString(),
                              i.unit,
                            ],
                          )
                          .toList(growable: false),
                      headerStyle: pw.TextStyle(
                        fontSize: 9,
                        font: fontBold,
                      ),
                      cellStyle: pw.TextStyle(
                        fontSize: 9,
                        font: fontRegular,
                      ),
                      headerDecoration:
                          const pw.BoxDecoration(color: PdfColors.grey200),
                      columnWidths: const <int, pw.TableColumnWidth>{
                        0: pw.FlexColumnWidth(3.2),
                        1: pw.FlexColumnWidth(0.8),
                        2: pw.FlexColumnWidth(1.0),
                      },
                      cellAlignments: const <int, pw.Alignment>{
                        0: pw.Alignment.centerLeft,
                        1: pw.Alignment.centerRight,
                        2: pw.Alignment.centerLeft,
                      },
                    ),
                  ],
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
          }

          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();

    return OrderExportFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }

  Future<List<AdminOrderDetail>> _fetchDetails(
    List<AdminOrderListEntry> orders,
  ) async {
    // Network-heavy. Keep concurrency small.
    const concurrency = 5;

    final results = <AdminOrderDetail>[];
    for (var i = 0; i < orders.length; i += concurrency) {
      final chunk = orders.skip(i).take(concurrency).toList(growable: false);
      final fetched = await Future.wait(
        chunk.map((o) => _repo.fetchOrderDetail(o.id)),
      );
      results.addAll(fetched);
    }

    return results;
  }
}

String _statusLabelTr(String status) {
  switch (status.trim().toLowerCase()) {
    case 'new':
      return 'Yeni';
    case 'approved':
      return 'Onaylı';
    case 'preparing':
      return 'Hazırlanıyor';
    case 'shipped':
      return 'Sevk edildi';
    case 'cancelled':
      return 'İptal';
    case 'completed':
      return 'Tamamlandı';
    default:
      return status;
  }
}

String _toCsv(List<List<String>> rows) {
  String esc(String v) {
    final needsQuote = v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    if (!needsQuote) return v;
    final escaped = v.replaceAll('"', '""');
    return '"$escaped"';
  }

  return rows
      .map((r) => r.map((c) => esc(c)).join(','))
      .join('\r\n');
}
