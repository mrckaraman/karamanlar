import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fatura detayı ve kalemleri için paylaşılan provider'lar
final invoiceDetailProvider = FutureProvider.autoDispose
    .family<AdminInvoiceDetail, String>((ref, id) async {
  return adminInvoiceRepository.fetchInvoiceById(id);
});

final invoiceItemsProvider = FutureProvider.autoDispose
    .family<List<AdminInvoiceItemEntry>, String>((ref, id) async {
  return adminInvoiceRepository.fetchInvoiceItems(id);
});

/// Fatura listesi için manuel yenileme tetikleyicisi
final adminInvoicesReloadTokenProvider =
    StateProvider<int>((ref) => 0);
