import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import '../../constants/statement_labels_tr.dart';

import 'customer_finance_providers.dart';

enum _StatementRange { days30, days90, days180, all }

class CustomerStatementTab extends ConsumerStatefulWidget {
  const CustomerStatementTab({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  ConsumerState<CustomerStatementTab> createState() =>
      _CustomerStatementTabState();
}

class _CustomerStatementTabState
    extends ConsumerState<CustomerStatementTab> {
  _StatementRange _range = _StatementRange.days30;
  String _type = 'all';

  DateTime? get _from {
    final now = DateTime.now();
    switch (_range) {
      case _StatementRange.days30:
        return now.subtract(const Duration(days: 30));
      case _StatementRange.days90:
        return now.subtract(const Duration(days: 90));
      case _StatementRange.days180:
        return now.subtract(const Duration(days: 180));
      case _StatementRange.all:
        return null;
    }
  }

  DateTime? get _to => null;

  CustomerStatementRequest _buildRequest() {
    return (
      customerId: widget.customerId,
      from: _from,
      to: _to,
      type: _type,
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _buildRequest();
    final entriesAsync = ref.watch(customerStatementProvider(request));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s8,
          children: [
            ChoiceChip(
              label: const Text('Son 30 gün'),
              selected: _range == _StatementRange.days30,
              onSelected: (_) {
                setState(() => _range = _StatementRange.days30);
              },
            ),
            ChoiceChip(
              label: const Text('Son 90 gün'),
              selected: _range == _StatementRange.days90,
              onSelected: (_) {
                setState(() => _range = _StatementRange.days90);
              },
            ),
            ChoiceChip(
              label: const Text('Son 180 gün'),
              selected: _range == _StatementRange.days180,
              onSelected: (_) {
                setState(() => _range = _StatementRange.days180);
              },
            ),
            ChoiceChip(
              label: const Text('Tümü'),
              selected: _range == _StatementRange.all,
              onSelected: (_) {
                setState(() => _range = _StatementRange.all);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            const Text('Tür: '),
            const SizedBox(width: AppSpacing.s8),
            DropdownButton<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Tümü')),
                DropdownMenuItem(value: 'invoice', child: Text('Fatura')),
                DropdownMenuItem(value: 'payment', child: Text('Tahsilat')),
                DropdownMenuItem(value: 'opening', child: Text('Açılış')),
                DropdownMenuItem(value: 'adjustment', child: Text('Düzeltme')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _type = value);
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(customerStatementProvider(request));
            },
            child: entriesAsync.when(
              loading: () => const AppLoadingState(),
              error: (e, _) => AppErrorState(
                message: 'Ekstre yüklenemedi: ${AppException.messageOf(e)}',
                onRetry: () =>
                    ref.invalidate(customerStatementProvider(request)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const AppEmptyState(
                    title: 'Bu aralıkta hareket yok.',
                    subtitle:
                        'Seçilen tarih ve tür filtresine göre hareket bulunamadı.',
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Tarih')),
                      DataColumn(label: Text('Tür')),
                      DataColumn(label: Text('Açıklama')),
                      DataColumn(label: Text(kDebtLabel)),
                      DataColumn(label: Text(kCreditLabel)),
                      DataColumn(label: Text(kBalanceLabel)),
                    ],
                    rows: rows
                        .map(
                          (e) => DataRow(
                            cells: [
                              DataCell(Text(_formatDate(e.date))),
                              DataCell(Text(e.type)),
                              DataCell(Text(e.description)),
                              DataCell(Text(_formatAmount(e.debit))),
                              DataCell(Text(_formatAmount(e.credit))),
                              DataCell(Text(
                                  _formatAmount(e.runningBalance ?? 0))),
                            ],
                          ),
                        )
                        .toList(),
                  ),
                );
              },
            ),
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
