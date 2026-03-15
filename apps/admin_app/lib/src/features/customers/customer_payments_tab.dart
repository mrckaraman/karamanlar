import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import 'customer_finance_providers.dart';

class CustomerPaymentsTab extends ConsumerStatefulWidget {
  const CustomerPaymentsTab({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  ConsumerState<CustomerPaymentsTab> createState() =>
      _CustomerPaymentsTabState();
}

class _CustomerPaymentsTabState extends ConsumerState<CustomerPaymentsTab> {
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 30));
  }

  CustomerPaymentsRequest _buildRequest() {
    return (
      customerId: widget.customerId,
      from: _from,
      to: _to,
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _buildRequest();
    final paymentsAsync = ref.watch(customerPaymentsProvider(request));

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(customerPaymentsProvider(request));
          },
          child: paymentsAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: 'Tahsilatlar yüklenemedi: ${AppException.messageOf(e)}',
              onRetry: () =>
                  ref.invalidate(customerPaymentsProvider(request)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return const AppEmptyState(
                  title: 'Tahsilat bulunamadı',
                  subtitle:
                      'Bu müşteri için seçilen tarih aralığında tahsilat yok.',
                );
              }

              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final amountText = _formatAmount(row.amount);
				  final dateText = _formatDate(row.date);

                  return AppListTile(
                    title: '$dateText • ${row.method.labelTr}',
                    subtitle: row.description,
                    trailing: Text(amountText),
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: () async {
              final router = GoRouter.of(context);
              final result = await router.push<bool>(
                '/customers/${widget.customerId}/payments/new',
              );
              if (result == true) {
                ref.invalidate(customerPaymentsProvider(request));
                ref.invalidate(customerStatementProvider((
                  customerId: widget.customerId,
                  from: null,
                  to: null,
                  type: 'all',
                )));
                ref.invalidate(customerBalanceProvider(widget.customerId));
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Tahsilat Ekle'),
          ),
        ),
      ],
    );
  }
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _formatDate(DateTime date) {
  return formatDate(date);
}
