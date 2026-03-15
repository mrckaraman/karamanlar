import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef CustomerStatementRequest = ({
  String customerId,
  DateTime? from,
  DateTime? to,
  String? type,
});

typedef CustomerPaymentsRequest = ({
  String customerId,
  DateTime? from,
  DateTime? to,
});

typedef CustomerPaymentsSummaryRequest = ({
  String customerId,
});

/// Elle girilen iade işlemleri için repository erişimi.
final manualRefundRepositoryProvider =
    Provider<AdminCustomerLedgerRepository>((ref) {
  return adminCustomerLedgerRepository;
});

final customerStatementProvider = FutureProvider.autoDispose
    .family<List<LedgerRow>, CustomerStatementRequest>((ref, params) async {
  final repo = adminCustomerLedgerRepository;
  return repo.fetchStatement(
    params.customerId,
    from: params.from,
    to: params.to,
    type: params.type,
  );
});

final customerPaymentsProvider = FutureProvider.autoDispose
    .family<List<PaymentRow>, CustomerPaymentsRequest>((ref, params) async {
  final repo = adminCustomerLedgerRepository;
  return repo.fetchPayments(
    params.customerId,
    from: params.from,
    to: params.to,
  );
});

final customerAgingProvider = FutureProvider.autoDispose
    .family<List<AgingRow>, String>((ref, customerId) async {
  final repo = adminCustomerLedgerRepository;
  return repo.fetchAging(customerId);
});

final customerBalanceProvider = FutureProvider.autoDispose
    .family<CustomerBalance, String>((ref, customerId) async {
  final repo = adminCustomerLedgerRepository;
  return repo.fetchBalance(customerId);
});

final customerPaymentsSummaryProvider = FutureProvider.autoDispose
    .family<CustomerPaymentsSummary, CustomerPaymentsSummaryRequest>(
        (ref, params) async {
  final repo = adminCustomerLedgerRepository;
  return repo.fetchPaymentsSummary(params.customerId);
});
