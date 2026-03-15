import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../../constants/statement_labels_tr.dart';
import 'customer_finance_providers.dart';
import 'customer_general_tab.dart';

enum _LedgerRange { days30, days90, all }

enum _MovementFilter { all, invoice, payment, other }

class CustomerLedgerPage extends ConsumerStatefulWidget {
  const CustomerLedgerPage({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  ConsumerState<CustomerLedgerPage> createState() => _CustomerLedgerPageState();
}

class _CustomerLedgerPageState extends ConsumerState<CustomerLedgerPage> {
  _LedgerRange _range = _LedgerRange.days30;
  _MovementFilter _movementFilter = _MovementFilter.all;
  String? _selectedRowId;

  DateTime? get _from {
    final now = DateTime.now();
    switch (_range) {
      case _LedgerRange.days30:
        return now.subtract(const Duration(days: 30));
      case _LedgerRange.days90:
        return now.subtract(const Duration(days: 90));
      case _LedgerRange.all:
        return null;
    }
  }

  DateTime? get _to => null;

  String? get _typeParam {
    switch (_movementFilter) {
      case _MovementFilter.invoice:
        return 'invoice';
      case _MovementFilter.payment:
        return 'payment';
      case _MovementFilter.all:
      case _MovementFilter.other:
        return 'all';
    }
  }

  CustomerStatementRequest _buildRequest() {
    return (
      customerId: widget.customerId,
      from: _from,
      to: _to,
      type: _typeParam,
    );
  }

  Future<void> _onEditPayment(LedgerRow row) async {
    final paymentId = row.refId;
    if (paymentId == null || paymentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hareketle ilişkili tahsilat kaydı bulunamadı.'),
        ),
      );
      return;
    }

    final scaffold = ScaffoldMessenger.of(context);
    final request = _buildRequest();

    PaymentRow? payment;
    final fetchResult = await AsyncValue.guard(() async {
      payment = await adminCustomerLedgerRepository.fetchPaymentById(paymentId);
    });

    if (!mounted) return;

    if (fetchResult.hasError || payment == null) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            'Tahsilat düzenlenemedi: ${AppException.messageOf(fetchResult.error ?? AppException('Tahsilat bulunamadı.'))}',
          ),
        ),
      );
      return;
    }

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditPaymentFromLedgerSheet(row: payment!),
    );

    if (!mounted) return;

    if (updated == true) {
      ref.invalidate(customerStatementProvider(request));
      ref.invalidate(customerBalanceProvider(widget.customerId));
      ref.invalidate(customerPaymentsProvider((
        customerId: widget.customerId,
        from: null,
        to: null,
      )));

      scaffold.showSnackBar(
        const SnackBar(content: Text('Tahsilat güncellendi.')),
      );
    }
  }

  Future<void> _onDeletePayment(LedgerRow row) async {
    final paymentId = row.refId;
    if (paymentId == null || paymentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hareketle ilişkili tahsilat kaydı bulunamadı.'),
        ),
      );
      return;
    }

    final scaffold = ScaffoldMessenger.of(context);

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tahsilatı İptal Et'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bu tahsilatı iptal etmek cari bakiyesini değiştirecektir. Devam etmek istiyor musunuz?',
            ),
            const SizedBox(height: 12),
            const Text('İptal sebebi (opsiyonel):'),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Örn: Hatalı kayıt, yanlış tahsilat vb.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    final request = _buildRequest();

    final reason = reasonController.text.trim();
    final result = await AsyncValue.guard(() async {
      await adminCustomerLedgerRepository.cancelPayment(paymentId, reason);
    });

    if (result.hasError) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            'Tahsilat iptal edilemedi: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

      ref.invalidate(customerStatementProvider(request));
      ref.invalidate(customerBalanceProvider(widget.customerId));
      ref.invalidate(customerPaymentsProvider((
        customerId: widget.customerId,
        from: null,
        to: null,
      )));

    scaffold.showSnackBar(
      const SnackBar(content: Text('Tahsilat iptal edildi.')),
    );
  }

  void _onEditInvoice(LedgerRow row) {
    final invoiceId = row.refId;
    if (invoiceId == null || invoiceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hareketle ilişkili fatura kaydı bulunamadı.'),
        ),
      );
      return;
    }

    context.go('/invoices/$invoiceId');
  }

  Future<void> _onDeleteInvoice(LedgerRow row) async {
    final invoiceId = row.refId;
    if (invoiceId == null || invoiceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hareketle ilişkili fatura kaydı bulunamadı.'),
        ),
      );
      return;
    }

    final scaffold = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Faturayı Sil'),
        content: const Text(
          'Bu işlemi silmek cari bakiyesini değiştirecektir. Devam etmek istiyor musunuz?\n\nNot: Fatura silme işlemi bu sürümde fatura modülünden yönetilecektir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }
    scaffold.showSnackBar(
      const SnackBar(
        content: Text(
          'Fatura silme işlemi henüz bu ekrandan aktif değil. Lütfen fatura modülünden yönetin.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _buildRequest();
    final entriesAsync = ref.watch(customerStatementProvider(request));
    final customerAsync = ref.watch(customerDetailProvider(widget.customerId));

    final customerName = customerAsync.maybeWhen(
      data: (c) => c.name,
      orElse: () => '',
    );
    final customerCode = customerAsync.maybeWhen(
      data: (c) => c.code,
      orElse: () => '',
    );
    return AppScaffold(
      title: 'Cari Hesap / Ekstre',
      actions: [
        TextButton.icon(
          onPressed: () async {
            await context.push('/returns/new?customerId=${widget.customerId}');

            if (!mounted) return;
            ref.invalidate(customerStatementProvider(request));
            ref.invalidate(customerBalanceProvider(widget.customerId));
          },
          icon: const Icon(Icons.assignment_return_outlined),
          label: const Text('İade (Elle)'),
        ),
      ],
      body: entriesAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Ekstre yüklenemedi: ${AppException.messageOf(e)}',
          onRetry: () => ref.invalidate(customerStatementProvider(request)),
        ),
        data: (rows) {
          // Özet bilgileri doğrudan statement satırlarından hesapla ki
          // admin ve müşteri uygulamaları aynı kaynağa baksın.
          final totalDebit = rows.fold<double>(0, (sum, row) => sum + row.debit);
          final totalCredit = rows.fold<double>(0, (sum, row) => sum + row.credit);
          final netBalanceValue = totalDebit - totalCredit;

          final netBalanceText = formatMoney(netBalanceValue);
          final totalDebitText = formatMoney(totalDebit);
          final totalCreditText = formatMoney(totalCredit);

          if (kDebugMode) {
            debugPrint(
              '[ADMIN][LEDGER][SUMMARY] customerId=${widget.customerId} '
              'range=$_range rows=${rows.length} '
              'totalDebit=$totalDebit totalCredit=$totalCredit net=$netBalanceValue',
            );
          }
          final filteredRows = rows.where((e) {
            switch (_movementFilter) {
              case _MovementFilter.all:
                return true;
              case _MovementFilter.invoice:
                return e.type == 'invoice';
              case _MovementFilter.payment:
                return e.type == 'payment';
              case _MovementFilter.other:
                // Fatura ve tahsilat dışındaki tüm hareketler (iade dahil)
                return e.type != 'invoice' && e.type != 'payment';
            }
          }).toList();

          if (filteredRows.isEmpty) {
            return const AppEmptyState(
              title: 'Bu aralıkta hareket yok.',
              subtitle:
                  'Seçilen tarih ve tür filtresine göre hareket bulunamadı.',
            );
          }

          const spec = _LedgerColumnSpec(
            dateWidth: 110,
            typeWidth: 120,
            debitWidth: 120,
            creditWidth: 120,
            balanceWidth: 140,
            actionWidth: 44,
          );

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(customerStatementProvider(request));
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.s16,
                      right: AppSpacing.s16,
                      top: AppSpacing.s8,
                      bottom: AppSpacing.s8,
                    ),
                    child: _LedgerSummaryCard(
                      customerName: customerName,
                      customerCode: customerCode,
                      netBalanceText: netBalanceText,
                      totalDebitText: totalDebitText,
                      totalCreditText: totalCreditText,
                      netBalanceValue: netBalanceValue,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16,
                      vertical: AppSpacing.s8,
                    ),
                    child: _LedgerFilters(
                      range: _range,
                      movementFilter: _movementFilter,
                      onRangeChanged: (value) {
                        setState(() => _range = value);
                      },
                      onMovementFilterChanged: (value) {
                        setState(() => _movementFilter = value);
                      },
                    ),
                  ),
                ),
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _LedgerHeaderDelegate(spec: spec),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final items = _buildLedgerListItems(filteredRows);
                      final item = items[index];

                      if (item is DateTime) {
                        return _LedgerDayHeader(date: item);
                      }

                      final listRow = item as _LedgerListRow;
                      final row = listRow.row;
                      final isSelected = row.id == _selectedRowId;

                      return _LedgerGridRow(
                        row: row,
                        spec: spec,
                        isZebra: listRow.isZebra,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() => _selectedRowId = row.id);
                        },
                        onEditPayment: row.type == 'payment'
                            ? () => _onEditPayment(row)
                            : null,
                        onDeletePayment: row.type == 'payment'
                            ? () => _onDeletePayment(row)
                            : null,
                        onEditInvoice: row.type == 'invoice'
                            ? () => _onEditInvoice(row)
                            : null,
                        onDeleteInvoice: row.type == 'invoice'
                            ? () => _onDeleteInvoice(row)
                            : null,
                      );
                    },
                    childCount: _buildLedgerListItems(filteredRows).length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s16,
                      vertical: AppSpacing.s12,
                    ),
                    child: _LedgerTotalsFooter(
                      totalDebit: filteredRows.fold<double>(
                        0,
                        (sum, row) => sum + row.debit,
                      ),
                      totalCredit: filteredRows.fold<double>(
                        0,
                        (sum, row) => sum + row.credit,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _formatAmount(double value) => formatMoney(value);

String _formatDate(DateTime date) => formatDate(date);

String _formatLedgerDescription(LedgerRow row) {
  final refId = row.refId;

  if (refId != null && refId.isNotEmpty) {
    switch (row.type) {
      case 'invoice':
        return 'Fatura #$refId';
      case 'payment':
        final method = row.description.trim();
        if (method.isNotEmpty) {
          return 'Tahsilat ($method) #$refId';
        }
        return 'Tahsilat #$refId';
      case 'refund':
        final desc = row.description.trim();
        if (desc.isNotEmpty) {
          return 'İade ($desc) #$refId';
        }
        return 'İade #$refId';
      default:
        if (row.description.trim().isNotEmpty) {
          return '${row.description.trim()} (#$refId)';
        }
        return 'İşlem #$refId';
    }
  }

  return row.description;
}

double _signedAmountForDisplay(LedgerRow row) {
  final isRefund = (row.type).toLowerCase() == 'refund';

  final raw = row.credit != 0
      ? row.credit
      : row.debit != 0
          ? row.debit
          : 0.0;

  if (!isRefund) return raw;

  // Refund her zaman negatif gibi gösterilsin (çift eksi üretmeden).
  return raw > 0 ? -raw : raw;
}

String _balanceDirectionLabel(double balance) {
  return kBalanceLabel;
}

String _formatType(String type) {
  switch (type) {
    case 'invoice':
      return 'Fatura';
    case 'payment':
      return 'Tahsilat';
    case 'refund':
      return 'İade';
    case 'opening':
      return 'Açılış';
    case 'adjustment':
      return 'Düzeltme';
    default:
      return type;
  }
}

Color _netColor(ThemeData theme, double net) {
  if (net > 0) {
    return Colors.green;
  }
  if (net < 0) {
    return Colors.red;
  }
  return theme.textTheme.titleMedium?.color ?? Colors.black;
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

List<Object> _buildLedgerListItems(List<LedgerRow> rows) {
  final items = <Object>[];
  DateTime? lastDate;
  var zebra = false;

  for (final row in rows) {
    final dateOnly = DateTime(row.date.year, row.date.month, row.date.day);

    if (lastDate == null || !_isSameDay(dateOnly, lastDate)) {
      items.add(dateOnly);
      lastDate = dateOnly;
      zebra = false;
    }

    zebra = !zebra;
    items.add(_LedgerListRow(row: row, isZebra: zebra));
  }

  return items;
}

class _LedgerColumnSpec {
  const _LedgerColumnSpec({
    required this.dateWidth,
    required this.typeWidth,
    required this.debitWidth,
    required this.creditWidth,
    required this.balanceWidth,
    required this.actionWidth,
  });

  final double dateWidth;
  final double typeWidth;
  final double debitWidth;
  final double creditWidth;
  final double balanceWidth;
  final double actionWidth;
}

class _LedgerSummaryCard extends StatelessWidget {
  const _LedgerSummaryCard({
    required this.customerName,
    required this.customerCode,
    required this.netBalanceText,
    required this.totalDebitText,
    required this.totalCreditText,
    required this.netBalanceValue,
  });

  final String customerName;
  final String customerCode;
  final String netBalanceText;
  final String totalDebitText;
  final String totalCreditText;
  final double netBalanceValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customerName.isEmpty ? 'Cari yükleniyor...' : customerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (customerCode.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      customerCode,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Güncel Bakiye',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    netBalanceText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _netColor(theme, netBalanceValue),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    'Toplam Borç: $totalDebitText',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Toplam Alacak: $totalCreditText',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerFilters extends StatelessWidget {
  const _LedgerFilters({
    required this.range,
    required this.movementFilter,
    required this.onRangeChanged,
    required this.onMovementFilterChanged,
  });

  final _LedgerRange range;
  final _MovementFilter movementFilter;
  final ValueChanged<_LedgerRange> onRangeChanged;
  final ValueChanged<_MovementFilter> onMovementFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s8,
          children: [
            ChoiceChip(
              label: const Text(
                'Son 30 gün',
                style: TextStyle(color: Colors.black),
              ),
              selected: range == _LedgerRange.days30,
              onSelected: (_) => onRangeChanged(_LedgerRange.days30),
            ),
            ChoiceChip(
              label: const Text(
                'Son 90 gün',
                style: TextStyle(color: Colors.black),
              ),
              selected: range == _LedgerRange.days90,
              onSelected: (_) => onRangeChanged(_LedgerRange.days90),
            ),
            ChoiceChip(
              label: const Text(
                'Tümü',
                style: TextStyle(color: Colors.black),
              ),
              selected: range == _LedgerRange.all,
              onSelected: (_) => onRangeChanged(_LedgerRange.all),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        const Text('Hareket türü:'),
        const SizedBox(height: AppSpacing.s4),
        Wrap(
          spacing: AppSpacing.s8,
          children: [
            ChoiceChip(
              label: const Text(
                'Tümü',
                style: TextStyle(color: Colors.black),
              ),
              selected: movementFilter == _MovementFilter.all,
              onSelected: (_) => onMovementFilterChanged(_MovementFilter.all),
            ),
            ChoiceChip(
              label: const Text(
                'Fatura',
                style: TextStyle(color: Colors.black),
              ),
              selected: movementFilter == _MovementFilter.invoice,
              onSelected: (_) =>
                  onMovementFilterChanged(_MovementFilter.invoice),
            ),
            ChoiceChip(
              label: const Text(
                'Tahsilat',
                style: TextStyle(color: Colors.black),
              ),
              selected: movementFilter == _MovementFilter.payment,
              onSelected: (_) =>
                  onMovementFilterChanged(_MovementFilter.payment),
            ),
            ChoiceChip(
              label: const Text(
                'Diğer',
                style: TextStyle(color: Colors.black),
              ),
              selected: movementFilter == _MovementFilter.other,
              onSelected: (_) => onMovementFilterChanged(_MovementFilter.other),
            ),
          ],
        ),
      ],
    );
  }
}

class _LedgerHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _LedgerHeaderDelegate({required this.spec});

  final _LedgerColumnSpec spec;

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final background =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8);

    return Material(
      elevation: overlapsContent ? 1 : 0,
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
        child: _LedgerHeaderRow(spec: spec),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LedgerHeaderDelegate oldDelegate) {
    return oldDelegate.spec != spec;
  }
}

class _LedgerHeaderRow extends StatelessWidget {
  const _LedgerHeaderRow({required this.spec});

  final _LedgerColumnSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: spec.dateWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tarih', style: labelStyle),
            ),
          ),
          SizedBox(
            width: spec.typeWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tür', style: labelStyle),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Açıklama', style: labelStyle),
            ),
          ),
          SizedBox(
            width: spec.debitWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                kDebtLabel,
                style: labelStyle,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          SizedBox(
            width: spec.creditWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                kCreditLabel,
                style: labelStyle,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          SizedBox(
            width: spec.balanceWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                kBalanceLabel,
                style: labelStyle,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ),
          SizedBox(width: spec.actionWidth),
        ],
      ),
    );
  }
}

class _LedgerDayHeader extends StatelessWidget {
  const _LedgerDayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s16,
        vertical: AppSpacing.s4,
      ),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _formatDate(date),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LedgerListRow {
  const _LedgerListRow({
    required this.row,
    required this.isZebra,
  });

  final LedgerRow row;
  final bool isZebra;
}

class _LedgerGridRow extends StatefulWidget {
  const _LedgerGridRow({
    required this.row,
    required this.spec,
    required this.isZebra,
    required this.isSelected,
    required this.onTap,
    this.onEditPayment,
    this.onDeletePayment,
    this.onEditInvoice,
    this.onDeleteInvoice,
  });

  final LedgerRow row;
  final _LedgerColumnSpec spec;
  final bool isZebra;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEditPayment;
  final VoidCallback? onDeletePayment;
  final VoidCallback? onEditInvoice;
  final VoidCallback? onDeleteInvoice;

  @override
  State<_LedgerGridRow> createState() => _LedgerGridRowState();
}

class _LedgerGridRowState extends State<_LedgerGridRow> {
  bool _hovered = false;

  TextStyle _amountStyle(Color color, ThemeData theme) {
    return theme.textTheme.bodyMedium?.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        TextStyle(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surface;
    final zebraOverlay =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.04);
    final hoverOverlay = theme.colorScheme.primary.withValues(alpha: 0.04);
    final selectedOverlay = theme.colorScheme.primary.withValues(alpha: 0.08);

    Color background = baseColor;
    if (widget.isZebra) {
      background = Color.alphaBlend(zebraOverlay, background);
    }
    if (_hovered) {
      background = Color.alphaBlend(hoverOverlay, background);
    }
    if (widget.isSelected) {
      background = Color.alphaBlend(selectedOverlay, background);
    }

    final row = widget.row;
    final debitText = _formatAmount(row.debit);
    final creditRaw = row.credit;
    final isRefund = (row.type).toLowerCase() == 'refund';
    final String creditText;
    if (isRefund) {
      final signed = _signedAmountForDisplay(row);
      creditText = signed == 0 ? '—' : _formatAmount(signed);
    } else {
      creditText = _formatAmount(creditRaw);
    }
    final balanceValue = row.runningBalance ?? 0;
    final balanceText = _formatAmount(balanceValue.abs());
    final balanceDirection = _balanceDirectionLabel(balanceValue);

    final badgeColor = switch (row.type) {
      'invoice' => theme.colorScheme.primary.withValues(alpha: 0.1),
      'payment' => theme.colorScheme.secondary.withValues(alpha: 0.1),
      'refund' => theme.colorScheme.tertiary.withValues(alpha: 0.1),
      _ => theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
    };
    final badgeTextColor = switch (row.type) {
      'invoice' => theme.colorScheme.primary,
      'payment' => theme.colorScheme.secondary,
      'refund' => theme.colorScheme.tertiary,
      _ => theme.colorScheme.onSurface.withValues(alpha: 0.6),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
          decoration: BoxDecoration(
            color: background,
          ),
          child: Row(
            children: [
              // Sol seçili şerit
              Container(
                width: 2,
                height: 32,
                margin: const EdgeInsets.only(right: AppSpacing.s8),
                color: widget.isSelected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
              SizedBox(
                width: widget.spec.dateWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_formatDate(row.date)),
                ),
              ),
              SizedBox(
                width: widget.spec.typeWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _formatType(row.type),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _formatLedgerDescription(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: widget.spec.debitWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    debitText,
                    style: _amountStyle(Colors.red, theme),
                  ),
                ),
              ),
              SizedBox(
                width: widget.spec.creditWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    creditText,
                    style: _amountStyle(Colors.green, theme),
                  ),
                ),
              ),
              SizedBox(
                width: widget.spec.balanceWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        balanceText,
                        style: _amountStyle(
                          _netColor(theme, balanceValue),
                          theme,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        balanceDirection,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: widget.spec.actionWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _hovered ? 1 : 0,
                    child: _buildMenu(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final hasPaymentActions =
        widget.onEditPayment != null || widget.onDeletePayment != null;
    final hasInvoiceActions =
        widget.onEditInvoice != null || widget.onDeleteInvoice != null;

    if (!hasPaymentActions && !hasInvoiceActions) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit_payment':
            widget.onEditPayment?.call();
            break;
          case 'delete_payment':
            widget.onDeletePayment?.call();
            break;
          case 'edit_invoice':
            widget.onEditInvoice?.call();
            break;
          case 'delete_invoice':
            widget.onDeleteInvoice?.call();
            break;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];
        if (hasPaymentActions) {
          items.addAll(const [
            PopupMenuItem(
              value: 'edit_payment',
              child: Text('Tahsilatı Düzenle'),
            ),
            PopupMenuItem(
              value: 'delete_payment',
              child: Text('Tahsilatı Sil'),
            ),
          ]);
        }
        if (hasInvoiceActions) {
          if (items.isNotEmpty) {
            items.add(const PopupMenuDivider());
          }
          items.addAll(const [
            PopupMenuItem(
              value: 'edit_invoice',
              child: Text('Faturayı Düzenle'),
            ),
            PopupMenuItem(
              value: 'delete_invoice',
              child: Text('Faturayı Sil'),
            ),
          ]);
        }
        return items;
      },
    );
  }
}

class _EditPaymentFromLedgerSheet extends StatefulWidget {
  const _EditPaymentFromLedgerSheet({
    required this.row,
  });

  final PaymentRow row;

  @override
  State<_EditPaymentFromLedgerSheet> createState() =>
      _EditPaymentFromLedgerSheetState();
}

class _EditPaymentFromLedgerSheetState
    extends State<_EditPaymentFromLedgerSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late PaymentMethod _method;
  late DateTime _date;
  AsyncValue<void> _saveState = const AsyncData<void>(null);

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _formatAmount(widget.row.amount),
    );
    _descriptionController = TextEditingController(
      text: widget.row.description,
    );
    _method = widget.row.method;
    _date = widget.row.date;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  double? _parseAmount(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir tutar girin.')),
      );
      return;
    }

    setState(() => _saveState = const AsyncLoading<void>());

    final result = await AsyncValue.guard(() async {
      await adminCustomerLedgerRepository.updatePayment(
        id: widget.row.id,
        amount: amount,
        method: _method,
        date: _date,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );

    });

    if (!mounted) return;
    setState(() => _saveState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Güncelleme hatası: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.s16,
          right: AppSpacing.s16,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
          top: AppSpacing.s16,
        ),
        child: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tahsilatı Düzenle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Tutar',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Yöntem',
                    ),
                    items: PaymentMethod.values
                        .map(
                          (m) => DropdownMenuItem<PaymentMethod>(
                            value: m,
                            child: Text(m.labelTr),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _method = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tarih: ${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.s4,
                          ),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _date = picked);
                          }
                        },
                        child: const Text('Tarih Seç'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama (opsiyonel)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  PrimaryButton(
                    label:
                        _saveState.isLoading ? 'Kaydediliyor...' : 'Kaydet',
                    expand: true,
                    onPressed: _saveState.isLoading ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@Deprecated('Use /returns/new (ReturnCreatePage) instead.')
class _ManualRefundSheet extends ConsumerStatefulWidget {
  const _ManualRefundSheet({
    required this.customerId,
    required this.customerName,
    required this.request,
  });

  final String customerId;
  final String customerName;
  final CustomerStatementRequest request;

  @override
  ConsumerState<_ManualRefundSheet> createState() => _ManualRefundSheetState();
}

@Deprecated('Use /returns/new (ReturnCreatePage) instead.')
class _ManualRefundSheetState extends ConsumerState<_ManualRefundSheet> {
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _unitPriceController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  AsyncValue<void> _saveState = const AsyncData<void>(null);
  String _selectedUnit = 'Adet';

  String? _selectedGroupName;
  CustomerProduct? _selectedProduct;

  String _formatGroupLabel(String groupName) {
    if (groupName == CustomerProductRepository.ungroupedGroupName) {
      return 'Grupsuz';
    }
    return groupName;
  }

  void _applyProductToForm(CustomerProduct product) {
    final rawUnitName = product.baseUnitName.trim();
    final normalizedUnitName = rawUnitName.toLowerCase();

    String selectedUnit;

    if (normalizedUnitName.contains('adet')) {
      selectedUnit = 'Adet';
    } else if (normalizedUnitName.contains('koli')) {
      selectedUnit = 'Koli';
    } else if (normalizedUnitName.contains('paket')) {
      selectedUnit = 'Paket';
    } else {
      selectedUnit = 'Adet';
    }

    final price = (product.effectivePrice ?? product.baseUnitPrice);

    setState(() {
      _selectedProduct = product;
      _selectedUnit = selectedUnit;
      if (price > 0) {
        _unitPriceController.text = price.toStringAsFixed(2);
      }
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _unitPriceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double? _parseNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  double get _quantity => _parseNumber(_quantityController.text) ?? 0;
  double get _unitPrice => _parseNumber(_unitPriceController.text) ?? 0;
  double get _total => _quantity * _unitPrice;

  bool get _isValid {
    if (_selectedProduct == null) return false;
    if (_quantity <= 0) return false;
    if (_unitPrice < 0) return false;
    return true;
  }

  Future<void> _save() async {
    if (!_isValid) return;

    final repo = ref.read(manualRefundRepositoryProvider);
    final unit = _selectedUnit;

    setState(() => _saveState = const AsyncLoading<void>());

    final result = await AsyncValue.guard(() async {
      await repo.createManualRefund(
        customerId: widget.customerId,
        quantity: _quantity,
        unit: unit,
        unitPrice: _unitPrice,
        note: () {
          final value = _noteController.text.trim();
          return value.isEmpty ? null : value;
        }(),
      );

    });

    if (!mounted) return;
    setState(() => _saveState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'İade kaydedilemedi: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('İade kaydedildi.')),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.s16,
          right: AppSpacing.s16,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
          top: AppSpacing.s16,
        ),
        child: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'İade (Elle)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Text(
                    widget.customerName.isEmpty
                        ? 'Müşteri'
                        : widget.customerName,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    'Ürün seçimi:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Devam etmek için önce bir ürün seçin.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  ref
                      .watch(_manualRefundGroupNamesProvider(widget.customerId))
                      .when(
                        loading: () => const AppLoadingState(),
                        error: (e, _) => AppErrorState(
                          message: 'Ürün grupları yüklenemedi: $e',
                          onRetry: () => ref.refresh(
                            _manualRefundGroupNamesProvider(
                              widget.customerId,
                            ).future,
                          ),
                        ),
                        data: (groups) {
                          final items = <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Tümü'),
                            ),
                            ...groups.map(
                              (g) => DropdownMenuItem<String>(
                                value: g,
                                child: Text(_formatGroupLabel(g)),
                              ),
                            ),
                          ];

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey<String>(
                                  'manual-refund-group-${widget.customerId}-${_selectedGroupName ?? ''}',
                                ),
                                initialValue: _selectedGroupName ?? '',
                                decoration: const InputDecoration(
                                  labelText: 'Kategori / Grup',
                                ),
                                items: items,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _selectedGroupName =
                                        value.trim().isEmpty ? null : value;
                                    _selectedProduct = null;
                                  });
                                },
                              ),
                              const SizedBox(height: AppSpacing.s8),
                              if (_selectedProduct != null) ...[
                                Text(
                                  'Seçili ürün: ${_selectedProduct!.name}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: AppSpacing.s8),
                              ],
                              SizedBox(
                                height: 220,
                                child: ref
                                    .watch(
                                      _manualRefundProductsProvider(
                                        _ManualRefundProductsQuery(
                                          customerId: widget.customerId,
                                          groupName: _selectedGroupName,
                                        ),
                                      ),
                                    )
                                    .when(
                                      loading: () =>
                                          const AppLoadingState(),
                                      error: (e, _) => AppErrorState(
                                        message: 'Ürünler yüklenemedi: $e',
                                        onRetry: () => ref.refresh(
                                          _manualRefundProductsProvider(
                                            _ManualRefundProductsQuery(
                                              customerId: widget.customerId,
                                              groupName: _selectedGroupName,
                                            ),
                                          ).future,
                                        ),
                                      ),
                                      data: (products) {
                                        if (products.isEmpty) {
                                          return const AppEmptyState(
                                            title: 'Ürün bulunamadı',
                                            subtitle:
                                                'Bu grup altında ürün yok.',
                                          );
                                        }

                                        return ListView.separated(
                                          itemCount: products.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                            final product = products[index];
                                            final price =
                                                (product.effectivePrice ??
                                                    product.baseUnitPrice);
                                            return ListTile(
                                              dense: true,
                                              title: Text(product.name),
                                              subtitle: Text(product.code),
                                              trailing: Text(
                                                formatMoney(price),
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                              onTap: () =>
                                                  _applyProductToForm(product),
                                            );
                                          },
                                        );
                                      },
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
                  const SizedBox(height: AppSpacing.s16),
                  TextField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText: 'Miktar',
                      hintText:
                          _selectedProduct == null ? 'Önce ürün seçin' : null,
                    ),
                    enabled: _selectedProduct != null,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedUnit,
                    decoration: const InputDecoration(
                      labelText: 'Birim',
                    ),
                    items: const [
                      'Adet',
                      'Koli',
                      'Paket',
                    ]
                        .map(
                          (u) => DropdownMenuItem<String>(
                            value: u,
                            child: Text(u),
                          ),
                        )
                        .toList(),
                    onChanged: _selectedProduct == null
                        ? null
                        : (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedUnit = value;
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextField(
                    controller: _unitPriceController,
                    decoration: InputDecoration(
                      labelText: 'Birim Fiyat',
                      hintText:
                          _selectedProduct == null ? 'Önce ürün seçin' : null,
                    ),
                    enabled: _selectedProduct != null,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.,]'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Tutar (otomatik)',
                      hintText: formatMoney(_total),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextField(
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Not (opsiyonel)',
                    ),
                    controller: _noteController,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  PrimaryButton(
                    label:
                        _saveState.isLoading ? 'Kaydediliyor...' : 'Kaydet',
                    expand: true,
                    onPressed:
                        !_isValid || _saveState.isLoading ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LedgerTotalsFooter extends StatelessWidget {
  const _LedgerTotalsFooter({
    required this.totalDebit,
    required this.totalCredit,
  });

  final double totalDebit;
  final double totalCredit;

  double get net => totalDebit - totalCredit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Expanded(
              child: _TotalItem(
                label: 'Toplam Borç',
                value: totalDebit,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _TotalItem(
                label: 'Toplam Alacak',
                value: totalCredit,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _TotalItem(
                label: 'Net (Borç - Alacak)',
                value: net,
                color: _netColor(theme, net),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalItem extends StatelessWidget {
  const _TotalItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          _formatAmount(value.abs()),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ManualRefundProductsQuery {
  const _ManualRefundProductsQuery({
    required this.customerId,
    required this.groupName,
  });

  final String customerId;
  final String? groupName;

  @override
  bool operator ==(Object other) {
    return other is _ManualRefundProductsQuery &&
        other.customerId == customerId &&
        other.groupName == groupName;
  }

  @override
  int get hashCode => Object.hash(customerId, groupName);
}

final _manualRefundGroupNamesProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, customerId) {
  return customerProductRepository.fetchGroupNames(customerId: customerId);
});

final _manualRefundProductsProvider = FutureProvider.autoDispose
    .family<List<CustomerProduct>, _ManualRefundProductsQuery>((ref, query) {
  return customerProductRepository.fetchProducts(
    customerId: query.customerId,
    page: 0,
    pageSize: 50,
    groupName: query.groupName,
  );
});
