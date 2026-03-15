import 'package:core/core.dart' hide isValidUuid;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../../constants/statement_labels_tr.dart';
import '../../utils/uuid_utils.dart' as uuid;
import 'customer_finance_providers.dart' as finance;

enum _StatementRange { days30, days90, days180, all }

enum StatementActionsMode { admin, customer }

class _CustomerStatementEntry {
  const _CustomerStatementEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.isOverdue,
    required this.type,
    this.refId,
    this.invoiceId,
    this.invoiceStatus,
  });

  final String id;
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double balance;
  final bool isOverdue;
  final String type; // 'invoice', 'payment' veya diger
  final String? refId; // Ilgili invoice/payment ID
  final String? invoiceId; // Payment satırı için bağlı fatura ID'si (opsiyonel)
  final String? invoiceStatus; // Sadece invoice satırları için (örn: cancelled)

  _CustomerStatementEntry withDate(DateTime newDate) {
    return _CustomerStatementEntry(
      id: id,
      date: newDate,
      description: description,
      debit: debit,
      credit: credit,
      balance: balance,
      isOverdue: isOverdue,
      type: type,
      refId: refId,
      invoiceId: invoiceId,
      invoiceStatus: invoiceStatus,
    );
  }

  _CustomerStatementEntry withInvoiceStatus(String? status) {
    return _CustomerStatementEntry(
      id: id,
      date: date,
      description: description,
      debit: debit,
      credit: credit,
      balance: balance,
      isOverdue: isOverdue,
      type: type,
      refId: refId,
      invoiceId: invoiceId,
      invoiceStatus: status,
    );
  }
  factory _CustomerStatementEntry.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];

    final rawDate = map['created_at'] ?? map['date'];
    DateTime parsedDate;
    if (rawDate is DateTime) {
      parsedDate = rawDate;
    } else if (rawDate is String) {
      parsedDate =
          DateTime.tryParse(rawDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(0);
    }
    parsedDate = parsedDate.toLocal();

    return _CustomerStatementEntry(
      id: rawId?.toString() ?? '',
      date: parsedDate,
      description: (map['description'] as String?) ?? '',
      debit: (map['debit'] as num?)?.toDouble() ?? 0,
      credit: (map['credit'] as num?)?.toDouble() ?? 0,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      isOverdue: map['is_overdue'] == true,
      type: (map['type'] as String?) ?? '',
      refId: map['ref_id']?.toString(),
      invoiceId: map['invoice_id']?.toString(),
      // Bazı view'larda invoice_status alanı varsa buradan gelir.
      // Yoksa _enrichStatementTimes içinde invoices tablosundan çekip set ediyoruz.
      invoiceStatus: (map['invoice_status'] ?? map['status'])?.toString(),
    );
  }

  double get net => debit - credit;
}

class _StatementFilterState {
  const _StatementFilterState({
    required this.range,
    this.from,
    this.to,
  });

  final _StatementRange range;
  final DateTime? from;
  final DateTime? to;
}

class _StatementQueryKey {
  _StatementQueryKey({
    required this.customerId,
    required this.range,
    DateTime? from,
    DateTime? to,
  })  : from = _normalizeDate(from),
        to = _normalizeDate(to),
        fromDayKey = _dayKey(_normalizeDate(from)),
        toDayKey = _dayKey(_normalizeDate(to));

  final String customerId;
  final _StatementRange range;
  final DateTime? from;
  final DateTime? to;
  final int fromDayKey;
  final int toDayKey;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _StatementQueryKey) return false;
    return other.customerId == customerId &&
        other.range == range &&
        other.fromDayKey == fromDayKey &&
        other.toDayKey == toDayKey;
  }

  @override
  int get hashCode => Object.hash(
        customerId,
        range,
        fromDayKey,
        toDayKey,
      );

  @override
  String toString() {
    return '_StatementQueryKey(customerId: $customerId, range: $range, fromDayKey: $fromDayKey, toDayKey: $toDayKey)';
  }
}

_StatementFilterState _buildFilterForRange(_StatementRange range) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  switch (range) {
    case _StatementRange.days30:
      return _StatementFilterState(
        range: range,
        from: today.subtract(const Duration(days: 30)),
        to: today,
      );
    case _StatementRange.days90:
      return _StatementFilterState(
        range: range,
        from: today.subtract(const Duration(days: 90)),
        to: today,
      );
    case _StatementRange.days180:
      return _StatementFilterState(
        range: range,
        from: today.subtract(const Duration(days: 180)),
        to: today,
      );
    case _StatementRange.all:
      return const _StatementFilterState(
        range: _StatementRange.all,
        from: null,
        to: null,
      );
  }
}

final _statementFilterProvider =
    StateProvider.family<_StatementFilterState, String>(
  (ref, customerId) => _buildFilterForRange(_StatementRange.days30),
);

final _statementQueryKeyProvider =
    Provider.family<_StatementQueryKey, String>((ref, customerId) {
  final filter = ref.watch(_statementFilterProvider(customerId));
  return _StatementQueryKey(
    customerId: customerId,
    range: filter.range,
    from: filter.from,
    to: filter.to,
  );
});

final customerStatementProvider =
    FutureProvider.family<List<_CustomerStatementEntry>, _StatementQueryKey>(
        (ref, key) async {
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());

  final fromDate = key.from;
  final toDate = key.to;

  if (kDebugMode) {
    debugPrint('[Statement] fetch key=$key');
  }

  var query = supabaseClient
      .from('v_customer_statement_with_balance')
      .select(
        'id, customer_id, date, created_at, type, ref_id, description, debit, credit, balance, is_overdue, invoice_id',
      )
      .eq('customer_id', key.customerId);

  if (fromDate != null) {
    query = query.gte('created_at', _toIsoUtcStartOfDay(fromDate));
  }
  if (toDate != null) {
    query = query.lte('created_at', _toIsoUtcEndOfDay(toDate));
  }

  final data = await query.order('created_at', ascending: false);

  final rows = (data as List<dynamic>)
      .map((e) => _CustomerStatementEntry.fromMap(
            Map<String, dynamic>.from(e as Map),
          ))
      .toList();

  final enriched = await _enrichStatementTimes(rows);
  final filtered = enriched.where((e) {
    final t = e.type.trim().toLowerCase();
    final isInvoice = t == 'invoice' || (e.debit > 0 && e.credit == 0);
    if (!isInvoice) return true;

    final s = e.invoiceStatus?.trim().toLowerCase();
    return s != 'cancelled';
  }).toList();

  filtered.sort((a, b) => b.date.compareTo(a.date));
  return filtered;
});

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return DateTime.tryParse(value.toString());
}

Future<List<_CustomerStatementEntry>> _enrichStatementTimes(
  List<_CustomerStatementEntry> rows,
) async {
  if (rows.isEmpty) return rows;

  final invoiceIds = <String>{};
  final paymentIds = <String>{};

  bool isMidnight(DateTime dt) =>
      dt.hour == 0 && dt.minute == 0 && dt.second == 0 && dt.millisecond == 0;

  for (final row in rows) {
    final t = row.type.toLowerCase();
    final isInvoice = t == 'invoice' || (row.debit > 0 && row.credit == 0);
    final isPayment = t == 'payment' || (row.credit > 0 && row.debit == 0);
    final needsTime = isMidnight(row.date);

    if (isInvoice) {
      final id = (row.invoiceId ?? row.refId ?? '').trim();
      if (id.isNotEmpty && uuid.isValidUuid(id)) invoiceIds.add(id);
    }
    if (needsTime && isPayment) {
      final id = (row.refId ?? '').trim();
      if (id.isNotEmpty && uuid.isValidUuid(id)) paymentIds.add(id);
    }
  }

  final invoiceTimeById = <String, DateTime>{};
  final invoiceStatusById = <String, String>{};
  if (invoiceIds.isNotEmpty) {
    try {
      final data = await supabaseClient
          .from('invoices')
          .select('id, issued_at, created_at, invoice_date, status')
          .inFilter('id', invoiceIds.toList());

      for (final row in (data as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = (map['id'] ?? '').toString();
        final status = (map['status'] ?? '').toString();
        final dt = _parseDateTime(map['issued_at']) ??
            _parseDateTime(map['created_at']) ??
            _parseDateTime(map['invoice_date']);
        if (id.isNotEmpty && dt != null) {
          invoiceTimeById[id] = dt;
        }
        if (id.isNotEmpty && status.isNotEmpty) {
          invoiceStatusById[id] = status;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[ADMIN][Statement] invoice time enrich failed: ${AppException.messageOf(e)}',
        );
      }
    }
  }

  final paymentTimeById = <String, DateTime>{};
  if (paymentIds.isNotEmpty) {
    try {
      final data = await supabaseClient
          .from('customer_payments')
          .select('id, created_at, payment_date')
          .inFilter('id', paymentIds.toList());

      for (final row in (data as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = (map['id'] ?? '').toString();
        final dt =
            _parseDateTime(map['created_at']) ?? _parseDateTime(map['payment_date']);
        if (id.isNotEmpty && dt != null) {
          paymentTimeById[id] = dt;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[ADMIN][Statement] payment time enrich failed: ${AppException.messageOf(e)}',
        );
      }
    }
  }

  DateTime? resolveEffectiveDate(_CustomerStatementEntry entry) {
    if (!isMidnight(entry.date)) return null;

    final t = entry.type.toLowerCase();
    final isInvoice = t == 'invoice' || (entry.debit > 0 && entry.credit == 0);
    final isPayment = t == 'payment' || (entry.credit > 0 && entry.debit == 0);

    if (isInvoice) {
      final id = (entry.invoiceId ?? entry.refId ?? '').trim();
      final dt = invoiceTimeById[id];
      if (dt != null) return dt.toLocal();
    }

    if (isPayment) {
      final id = (entry.refId ?? '').trim();
      final dt = paymentTimeById[id];
      if (dt != null) return dt.toLocal();
    }

    return null;
  }

  String? resolveInvoiceStatus(_CustomerStatementEntry entry) {
    final t = entry.type.toLowerCase();
    final isInvoice = t == 'invoice' || (entry.debit > 0 && entry.credit == 0);
    if (!isInvoice) return null;

    final id = (entry.invoiceId ?? entry.refId ?? '').trim();
    if (id.isEmpty) return null;
    return invoiceStatusById[id];
  }

  return rows.map((e) {
    final resolvedDate = resolveEffectiveDate(e);
    final resolvedStatus = resolveInvoiceStatus(e) ?? e.invoiceStatus;
    final withDate = resolvedDate == null ? e : e.withDate(resolvedDate);
    return withDate.withInvoiceStatus(resolvedStatus);
  }).toList();
}

String _toIsoUtcStartOfDay(DateTime date) {
  final localStart = DateTime(date.year, date.month, date.day);
  return localStart.toUtc().toIso8601String();
}

String _toIsoUtcEndOfDay(DateTime date) {
  final localEnd = DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  return localEnd.toUtc().toIso8601String();
}

class CustomerStatementPage extends ConsumerWidget {
  const CustomerStatementPage({
    super.key,
    required this.customerId,
    this.actionsMode = StatementActionsMode.admin,
  });

  final String customerId;
  final StatementActionsMode actionsMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queryKey = ref.watch(_statementQueryKeyProvider(customerId));
    final range = queryKey.range;
    final typeFilter = ref.watch(_statementTypeFilterProvider);

    final entriesAsync = ref.watch(customerStatementProvider(queryKey));

    final hasSummaryData = entriesAsync.asData != null;
    final summary = hasSummaryData
        ? _buildSummary(entriesAsync.asData!.value)
        : const _StatementSummary(balance: 0, overdue: 0, notDue: 0);


        final headerWidgets = <Widget>[
          Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cari Bakiyesi',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Builder(
                    builder: (context) {
                      final theme = Theme.of(context);
                      final balanceText =
                          hasSummaryData ? _formatAmount(summary.balance) : '—';
                      return Text(
                        balanceText,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hasSummaryData
                              ? _balanceColor(theme, summary.balance)
                              : theme.textTheme.headlineSmall?.color,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'Güncel bakiye (vadesi gelmiş + gelmemiş tüm hareketler)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryItem(
                          label: 'Vadesi geçmiş',
                          amount: hasSummaryData ? summary.overdue : 0,
                          showDashWhenZero: !hasSummaryData,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: _SummaryItem(
                          label: 'Vadesi gelmemiş',
                          amount: hasSummaryData ? summary.notDue : 0,
                          showDashWhenZero: !hasSummaryData,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          const _AdminInvoicesShortcutCard(),
          const SizedBox(height: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('Son 30 gün'),
                selected: range == _StatementRange.days30,
                onSelected: (_) {
                  ref.read(_statementFilterProvider(customerId).notifier).state =
                      _buildFilterForRange(_StatementRange.days30);
                },
              ),
              ChoiceChip(
                label: const Text('Son 90 gün'),
                selected: range == _StatementRange.days90,
                onSelected: (_) {
                  ref.read(_statementFilterProvider(customerId).notifier).state =
                      _buildFilterForRange(_StatementRange.days90);
                },
              ),
              ChoiceChip(
                label: const Text('Son 180 gün'),
                selected: range == _StatementRange.days180,
                onSelected: (_) {
                  ref.read(_statementFilterProvider(customerId).notifier).state =
                      _buildFilterForRange(_StatementRange.days180);
                },
              ),
              ChoiceChip(
                label: const Text('Tümü'),
                selected: range == _StatementRange.all,
                onSelected: (_) {
                  ref.read(_statementFilterProvider(customerId).notifier).state =
                      _buildFilterForRange(_StatementRange.all);
                },
              ),
              const SizedBox(width: AppSpacing.s12),
              const Text('Tür:'),
              DropdownButton<_StatementTypeFilter>(
                value: typeFilter,
                onChanged: (value) {
                  if (value == null) return;
                  ref.read(_statementTypeFilterProvider.notifier).state = value;
                },
                items: const [
                  DropdownMenuItem(
                    value: _StatementTypeFilter.all,
                    child: Text('Tümü'),
                  ),
                  DropdownMenuItem(
                    value: _StatementTypeFilter.invoice,
                    child: Text('Fatura'),
                  ),
                  DropdownMenuItem(
                    value: _StatementTypeFilter.payment,
                    child: Text('Tahsilat'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            _rangeLabel(range),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s8),
        ];

        if (entriesAsync.isLoading) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...headerWidgets,
              const AppLoadingState(),
            ],
          );
        }

        if (entriesAsync.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...headerWidgets,
              AppErrorState(
                message: 'Ekstre hareketleri yüklenemedi: ${entriesAsync.error}',
              ),
            ],
          );
        }

        final entries = entriesAsync.value ?? const <_CustomerStatementEntry>[];
        List<_CustomerStatementEntry> filtered = entries;

        switch (typeFilter) {
          case _StatementTypeFilter.all:
            break;
          case _StatementTypeFilter.invoice:
            filtered = entries
                .where((e) => e.debit > 0 && e.credit == 0)
                .toList();
            break;
          case _StatementTypeFilter.payment:
            filtered = entries
                .where((e) => e.credit > 0 && e.debit == 0)
                .toList();
            break;
        }

        // Supabase backend'e dokunmadan: ekstrede en yeni kayıt üstte.
        final displayEntries = [...filtered]
          ..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            if (byDate != 0) return byDate;
            return b.id.compareTo(a.id);
          });

        if (displayEntries.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...headerWidgets,
              AppEmptyState(
                title: 'Hareket bulunamadı',
                subtitle: 'Seçilen tarih aralığında bu cari için hareket yok.',
                icon: Icons.receipt_long_outlined,
                action: FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(customerStatementProvider(queryKey));
                    ref.invalidate(finance.customerBalanceProvider(customerId));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Yenile'),
                ),
              ),
            ],
          );
        }

        final totalDebit = displayEntries.fold<double>(
          0,
          (sum, e) => sum + e.debit,
        );
        final totalCredit = displayEntries.fold<double>(
          0,
          (sum, e) => sum + e.credit,
        );

        final showHeaderRow = MediaQuery.of(context).size.width >= 760;
        final extraHeader = showHeaderRow ? 1 : 0;

        Widget buildEntryWidget(_CustomerStatementEntry entry) {
          final theme = Theme.of(context);
          final dateText = _formatDate(entry.date);
          final isCancelledInvoice = _isCancelledInvoiceEntry(entry);

          final kind = _detectEntryKind(entry);
          final isPayment = kind == _EntryKind.payment;
          final hasLinkedInvoice = isPayment &&
              entry.invoiceId != null &&
              entry.invoiceId!.isNotEmpty &&
              uuid.isValidUuid(entry.invoiceId!);

          final isDebit = entry.debit > 0 && entry.credit == 0;
          final isCredit = entry.credit > 0 && entry.debit == 0;
          final isRefund = (entry.type).toLowerCase() == 'refund';

          final String typeLabel;
          final Color typeColor;

          if (isCancelledInvoice) {
            typeLabel = 'İptal';
            typeColor = Colors.grey;
          } else if (isRefund) {
            typeLabel = 'İade';
            typeColor = theme.colorScheme.tertiary;
          } else if (isDebit) {
            typeLabel = 'Borç';
            typeColor = theme.colorScheme.error;
          } else if (isCredit) {
            typeLabel = 'Alacak';
            typeColor = Colors.green;
          } else {
            typeLabel = 'Diğer';
            typeColor = Colors.grey;
          }

          final amountTextStyle = theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isCancelledInvoice
                    ? Colors.grey
                    : theme.textTheme.bodyMedium?.color,
                decoration:
                    isCancelledInvoice ? TextDecoration.lineThrough : TextDecoration.none,
              ) ??
              TextStyle(
                fontWeight: FontWeight.bold,
                color: isCancelledInvoice ? Colors.grey : Colors.black,
                decoration:
                    isCancelledInvoice ? TextDecoration.lineThrough : TextDecoration.none,
              );

            final balanceTextStyle = amountTextStyle.copyWith(
            color: isCancelledInvoice
              ? Colors.grey
              : _balanceColor(theme, entry.balance),
            );

          List<PopupMenuEntry<String>> buildMenuItems() {
            final kind = _detectEntryKind(entry);
            final items = <PopupMenuEntry<String>>[
              const PopupMenuItem(
                value: 'detail',
                child: Text('Detay'),
              ),
            ];

            if (actionsMode == StatementActionsMode.admin) {
              if (kind == _EntryKind.payment) {
                items.addAll(const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Düzenle'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Sil'),
                  ),
                ]);
              } else if (kind == _EntryKind.invoice) {
                items.add(const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Faturayı iptal et'),
                ));
              }
            }
            return items;
          }

          Future<void> handleMenu(String value) async {
            final kind = _detectEntryKind(entry);
            switch (value) {
              case 'detail':
                await _onEntryDetail(
                  context,
                  ref,
                  queryKey,
                  customerId,
                  entry,
                );
                break;
              case 'edit':
                _onEntryEdit(
                  context,
                  ref,
                  queryKey,
                  customerId,
                  entry,
                );
                break;
              case 'delete':
                if (kind == _EntryKind.payment) {
                  _onEntryDelete(
                    context,
                    ref,
                    queryKey,
                    customerId,
                    entry,
                  );
                }
                break;
              case 'cancel':
                if (kind == _EntryKind.invoice) {
                  await _onEntryCancelInvoice(
                    context,
                    ref,
                    queryKey,
                    customerId,
                    entry,
                  );
                }
                break;
            }
          }

          Future<void> handleTap() async {
            if (isPayment) {
              if (hasLinkedInvoice) {
                final invoiceId = entry.invoiceId!;
                context.go('/invoices/$invoiceId');
                return;
              }
              await _onEntryDetail(
                context,
                ref,
                queryKey,
                customerId,
                entry,
              );
              return;
            }
            await _onEntryDetail(
              context,
              ref,
              queryKey,
              customerId,
              entry,
            );
          }

          Widget badge() {
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRefund) ...[
                    Icon(
                      Icons.assignment_return_outlined,
                      size: 14,
                      color: typeColor,
                    ),
                    const SizedBox(width: AppSpacing.s4),
                  ],
                  Text(
                    typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: typeColor,
                    ),
                  ),
                ],
              ),
            );
          }

          Widget menu() {
            return PopupMenuButton<String>(
              itemBuilder: (_) => buildMenuItems(),
              onSelected: (value) async => handleMenu(value),
            );
          }

          return InkWell(
            onTap: handleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s8,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 700;
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dateText,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            badge(),
                            const SizedBox(width: AppSpacing.s8),
                            menu(),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          entry.description,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Row(
                          children: [
                            Expanded(
                              child: _CompactAmount(
                                  label: kDebtLabel,
                                value: entry.debit > 0
                                    ? _formatAmount(entry.debit)
                                    : '—',
                                style: amountTextStyle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.s12),
                            Expanded(
                              child: _CompactAmount(
                                  label: kCreditLabel,
                                value: () {
                                  final credit = _creditAmountForDisplay(entry);
                                  if (credit == 0) return '—';
                                  return _formatAmount(credit);
                                }(),
                                style: amountTextStyle,
                              ),
                            ),
                              const SizedBox(width: AppSpacing.s12),
                              Expanded(
                                child: _CompactAmount(
                                  label: kBalanceLabel,
                                  value: entry.balance == 0
                                      ? '—'
                                      : _formatAmount(entry.balance.abs()),
                                  style: balanceTextStyle,
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          dateText,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: badge(),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            entry.debit > 0 ? _formatAmount(entry.debit) : '—',
                            style: amountTextStyle,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            () {
                              final credit = _creditAmountForDisplay(entry);
                              if (credit == 0) return '—';
                              return _formatAmount(credit);
                            }(),
                            style: amountTextStyle,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            entry.balance == 0
                                ? '—'
                                : _formatAmount(entry.balance.abs()),
                            style: balanceTextStyle,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: menu(),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount:
              headerWidgets.length + extraHeader + displayEntries.length + 1,
          itemBuilder: (context, index) {
            if (index < headerWidgets.length) {
              return headerWidgets[index];
            }

            var localIndex = index - headerWidgets.length;

            if (showHeaderRow && localIndex == 0) {
              return const Column(
                children: [
                  _AdminStatementHeaderRow(),
                  Divider(height: 1),
                ],
              );
            }

            if (showHeaderRow) {
              localIndex -= 1;
            }

            if (localIndex < displayEntries.length) {
              return Column(
                children: [
                  buildEntryWidget(displayEntries[localIndex]),
                  const Divider(height: 1),
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: _AdminStatementTotalsBar(
                totalDebit: totalDebit,
                totalCredit: totalCredit,
              ),
            );
          },
        );
  }

  double _creditAmountForDisplay(_CustomerStatementEntry entry) {
    // _CustomerStatementEntry.type şu an String (non-null) tanımlı olsa da,
    // map'ten gelirken boş string'e normalize ediliyor. İleride nullable
    // yapılırsa da güvenli olsun diye yerelde değişkene alıyoruz.
    final type = entry.type;
    final isRefund = type.toLowerCase() == 'refund';

    final raw = entry.credit;

    if (!isRefund) return raw;

    // Refund her zaman negatif gibi gösterilsin (çift eksi üretmeden).
    return raw > 0 ? -raw : raw;
  }

  _EntryKind _detectEntryKind(_CustomerStatementEntry entry) {
    final type = entry.type.toLowerCase();
    if (type == 'refund') return _EntryKind.other;
    if (type == 'invoice') return _EntryKind.invoice;
    if (type == 'payment') return _EntryKind.payment;

    if (entry.debit > 0 && entry.credit == 0) {
      return _EntryKind.invoice;
    }
    if (entry.credit > 0 && entry.debit == 0) {
      return _EntryKind.payment;
    }
    return _EntryKind.other;
  }

  bool _isCancelledInvoiceEntry(_CustomerStatementEntry entry) {
    final t = entry.type.toLowerCase();
    return t == 'invoice_cancelled' || t == 'invoice_cancel';
  }

  String? _validatedRefId(
    BuildContext context,
    _CustomerStatementEntry entry,
  ) {
    final raw = entry.refId;
    if (raw == null || raw.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[ADMIN][Statement] Missing refId for entry id=${entry.id} type=${entry.type}',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hareketin referansı bulunamadı.'),
        ),
      );
      return null;
    }

    if (!uuid.isValidUuid(raw)) {
      if (kDebugMode) {
        debugPrint(
          '[ADMIN][Statement] Invalid refId="$raw" for entry id=${entry.id} type=${entry.type}',
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hareketin referansı bulunamadı.'),
        ),
      );
      return null;
    }

    return raw;
  }

  Future<void> _onEntryDetail(
    BuildContext context,
    WidgetRef ref,
    _StatementQueryKey queryKey,
    String customerId,
    _CustomerStatementEntry entry,
  ) async {
    final kind = _detectEntryKind(entry);
    final refId = _validatedRefId(context, entry);

    switch (kind) {
      case _EntryKind.invoice:
        if (refId == null) return;
        context.go('/invoices/$refId');
        return;
      case _EntryKind.payment:
        if (refId == null) return;
        await _openPaymentDetailSheet(
          context,
          ref,
          queryKey,
          customerId,
          entry,
          refId,
        );
        return;
      case _EntryKind.other:
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Hareket Detayı'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${entry.id}'),
                const SizedBox(height: AppSpacing.s4),
                Text('Tarih: ${_formatDate(entry.date)}'),
                const SizedBox(height: AppSpacing.s4),
                Text('Açıklama: ${entry.description}'),
                const SizedBox(height: AppSpacing.s4),
                Text('$kDebtLabel: ${_formatAmount(entry.debit)}'),
                const SizedBox(height: AppSpacing.s4),
                Text('$kCreditLabel: ${_formatAmount(entry.credit)}'),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  '$kBalanceLabel: ${_formatAmount(entry.balance.abs())}',
                  style: TextStyle(
                    color: _balanceColor(Theme.of(ctx), entry.balance),
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                const Text(
                  'Bu hareket şu an sadece görüntülenebilir.',
                ),
              ],
            ),
            actions: [
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => Navigator.of(ctx).pop(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s4,
                  ),
                  child: Text('Kapat'),
                ),
              ),
            ],
          ),
        );
        return;
    }
  }

  Future<void> _openPaymentDetailSheet(
    BuildContext context,
    WidgetRef ref,
    _StatementQueryKey queryKey,
    String customerId,
    _CustomerStatementEntry entry,
    String paymentId,
  ) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      final payment =
          await adminCustomerLedgerRepository.fetchPaymentById(paymentId);

      if (!context.mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _PaymentDetailSheet(
          row: payment,
          customerId: customerId,
          queryKey: queryKey,
        ),
      );
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text(
            'Tahsilat detayı yüklenemedi: ${AppException.messageOf(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _onEntryEdit(
    BuildContext context,
    WidgetRef ref,
    _StatementQueryKey queryKey,
    String customerId,
    _CustomerStatementEntry entry,
  ) async {
    final kind = _detectEntryKind(entry);
    final refId = _validatedRefId(context, entry);

    switch (kind) {
      case _EntryKind.invoice:
        if (refId == null) return;
        // Bu sürümde fatura düzenleme invoice detay ekranından yönetiliyor.
        context.go('/invoices/$refId');
        return;
      case _EntryKind.payment:
        if (refId == null) return;

        final scaffold = ScaffoldMessenger.of(context);
        try {
          final payment =
              await adminCustomerLedgerRepository.fetchPaymentById(refId);

          if (!context.mounted) return;

          final updated = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => _EditPaymentFromStatementSheet(row: payment),
          );

          if (updated == true) {
            ref.invalidate(customerStatementProvider(queryKey));
            ref.invalidate(finance.customerBalanceProvider(customerId));
            ref.invalidate(
              finance.customerPaymentsProvider((
                customerId: customerId,
                from: null,
                to: null,
              )),
            );

            scaffold.showSnackBar(
              const SnackBar(content: Text('Güncellendi.')),
            );
          }
        } catch (e) {
          scaffold.showSnackBar(
            SnackBar(content: Text('Düzenleme hatası: ${AppException.messageOf(e)}')),
          );
        }
        return;
      case _EntryKind.other:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu hareket türü şu an düzenlenemiyor.'),
          ),
        );
        return;
    }
  }

  Future<void> _onEntryDelete(
    BuildContext context,
    WidgetRef ref,
    _StatementQueryKey queryKey,
    String customerId,
    _CustomerStatementEntry entry,
  ) async {
    final kind = _detectEntryKind(entry);

    String? paymentRefId;
    if (kind == _EntryKind.payment) {
      paymentRefId = _validatedRefId(context, entry);
      if (paymentRefId == null) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hareket silinsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => Navigator.of(ctx).pop(false),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              child: Text('İptal'),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => Navigator.of(ctx).pop(true),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              child: Text(
                'Sil',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    switch (kind) {
      case _EntryKind.invoice:
        // Faturalar silinmez, yalnızca iptal edilir.
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Faturalar silinemez, yalnızca iptal edilebilir.'),
          ),
        );
        return;
      case _EntryKind.other:
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu hareket türü şu an silinemiyor.'),
          ),
        );
        return;
      case _EntryKind.payment:
        break;
    }

    final result = await AsyncValue.guard(
      () => adminCustomerLedgerRepository.deletePayment(paymentRefId!),
    );

    if (!context.mounted) return;

    if (result.hasError) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: ${AppException.messageOf(result.error!)}')),
      );
      return;
    }

    ref.invalidate(customerStatementProvider(queryKey));
    ref.invalidate(finance.customerBalanceProvider(customerId));

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Silindi.')),
    );
  }

  Future<void> _onEntryCancelInvoice(
    BuildContext context,
    WidgetRef ref,
    _StatementQueryKey queryKey,
    String customerId,
    _CustomerStatementEntry entry,
  ) async {
    final refId = _validatedRefId(context, entry);
    if (refId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fatura iptal edilsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
        actions: [
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => Navigator.pop(ctx, false),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              child: Text('İptal'),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () => Navigator.pop(ctx, true),
            child: const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: AppSpacing.s4,
              ),
              child: Text('İptal Et'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await AsyncValue.guard(
      () => adminInvoiceRepository.updateInvoiceStatus(
        invoiceId: refId,
        status: 'cancelled',
      ),
    );

    if (!context.mounted) return;

    if (result.hasError) {
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('İptal edilemedi: ${AppException.messageOf(result.error!)}'),
        ),
      );
      return;
    }

    // Başarılı iptal sonrası verileri yeniden çek.
    ref.invalidate(customerStatementProvider(queryKey));
    ref.invalidate(finance.customerBalanceProvider(customerId));

    final refreshedEntries =
        await ref.refresh(customerStatementProvider(queryKey).future);
    final refreshedBalance =
        await ref.refresh(finance.customerBalanceProvider(customerId).future);

    if (kDebugMode) {
      debugPrint(
        '[ADMIN][Statement] after cancel refresh entries=${refreshedEntries.length} balance=$refreshedBalance',
      );
    }

    if (!context.mounted) return;

    // ignore: use_build_context_synchronously
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Fatura iptal edildi')),
    );
  }
}

enum _EntryKind { invoice, payment, other }

class _AdminStatementHeaderRow extends StatelessWidget {
  const _AdminStatementHeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Text header(String text) {
      return Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: header('Tarih'),
          ),
          SizedBox(
            width: 110,
            child: header('Tür'),
          ),
          const Expanded(
            child: Text(
              'Açıklama',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: header(kDebtLabel),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: header(kCreditLabel),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: header(kBalanceLabel),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}

class _PaymentDetailSheet extends ConsumerWidget {
  const _PaymentDetailSheet({
    required this.row,
    required this.customerId,
    required this.queryKey,
  });

  final PaymentRow row;
  final String customerId;
  final _StatementQueryKey queryKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tahsilat Detayı',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                Text('Tarih: ${_formatDate(row.date)}'),
                const SizedBox(height: AppSpacing.s4),
                Text('Tutar: ${_formatAmount(row.amount)}'),
                const SizedBox(height: AppSpacing.s4),
                Text('Yöntem: ${row.method.labelTr}'),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Durum: ${row.isCancelled ? 'İptal edildi' : 'Aktif'}',
                ),
                const SizedBox(height: AppSpacing.s4),
                if (row.description.isNotEmpty)
                  Text('Açıklama: ${row.description}'),
                if (row.isCancelled && row.cancelReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: Text('İptal sebebi: ${row.cancelReason}'),
                  ),
                const SizedBox(height: AppSpacing.s16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.s8,
                          vertical: AppSpacing.s4,
                        ),
                        child: Text('Kapat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditPaymentFromStatementSheet extends ConsumerStatefulWidget {
  const _EditPaymentFromStatementSheet({required this.row});

  final PaymentRow row;

  @override
  ConsumerState<_EditPaymentFromStatementSheet> createState() =>
      _EditPaymentFromStatementSheetState();
}

class _EditPaymentFromStatementSheetState
    extends ConsumerState<_EditPaymentFromStatementSheet> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _date = DateTime.now();
  AsyncValue<void> _saveState = const AsyncData(null);

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.row.amount.toStringAsFixed(2);
    _descriptionController.text = widget.row.description;
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

    setState(() => _saveState = const AsyncLoading());
    final result = await AsyncValue.guard(
      () => adminCustomerLedgerRepository.updatePayment(
        id: widget.row.id,
        amount: amount,
        method: _method,
        date: _date,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      ),
    );

    if (!mounted) return;

    if (result.hasError) {
      setState(() => _saveState = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Güncelleme hatası: ${AppException.messageOf(result.error!)}'),
        ),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = _saveState.isLoading;

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
                  const SizedBox(height: AppSpacing.s12),
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
                      setState(() {
                        _method = value;
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Tarih: ${_formatDate(_date)}'),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _date = picked;
                            });
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.s4,
                          ),
                          child: Text('Tarih Seç'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  TextField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: isSaving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.s4,
                          ),
                          child: Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      FilledButton(
                        onPressed: isSaving ? null : _save,
                        child: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ],
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

class _StatementSummary {
  const _StatementSummary({
    required this.balance,
    required this.overdue,
    required this.notDue,
  });

  final double balance;
  final double overdue;
  final double notDue;
}

_StatementSummary _buildSummary(List<_CustomerStatementEntry> entries) {
  if (entries.isEmpty) {
    return const _StatementSummary(balance: 0, overdue: 0, notDue: 0);
  }

  final totalDebit = entries.fold<double>(
    0,
    (sum, e) => sum + e.debit,
  );
  final totalCredit = entries.fold<double>(
    0,
    (sum, e) => sum + e.credit,
  );
  final balance = totalDebit - totalCredit;

  double overdue = 0;
  double notDue = 0;

  for (final e in entries) {
    final net = e.net;
    if (net <= 0) continue;
    if (e.isOverdue) {
      overdue += net;
    } else {
      // Vadesi gelmemiş (is_overdue = false) tüm pozitif net hareketler
      notDue += net;
    }
  }

  return _StatementSummary(balance: balance, overdue: overdue, notDue: notDue);
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.amount,
    this.showDashWhenZero = false,
  });

  final String label;
  final double amount;
  final bool showDashWhenZero;

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
          showDashWhenZero && amount == 0 ? '—' : _formatAmount(amount),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
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
  return formatDateTime(date);
}

DateTime? _normalizeDate(DateTime? d) {
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

int _dayKey(DateTime? d) {
  if (d == null) return 0;
  return d.year * 10000 + d.month * 100 + d.day;
}

class _AdminInvoicesShortcutCard extends StatelessWidget {
  const _AdminInvoicesShortcutCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          context.go('/invoices');
        },
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Faturalar',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'Bu müşteriyle ilişkili faturaları listeleyin.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAmount extends StatelessWidget {
  const _CompactAmount({
    required this.label,
    required this.value,
    required this.style,
  });

  final String label;
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.s4),
        Text(value, style: style),
      ],
    );
  }
}

class _AdminStatementTotalsBar extends StatelessWidget {
  const _AdminStatementTotalsBar({
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
              child: _AdminTotalItem(
                label: 'Toplam Borç',
                value: totalDebit,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _AdminTotalItem(
                label: 'Toplam Alacak',
                value: totalCredit,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _AdminTotalItem(
                label: 'Net (Borç - Alacak)',
                value: net,
                color: _balanceColor(theme, net),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTotalItem extends StatelessWidget {
  const _AdminTotalItem({
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

String _rangeLabel(_StatementRange range) {
  switch (range) {
    case _StatementRange.days30:
      return 'Seçilen aralık: Son 30 gün';
    case _StatementRange.days90:
      return 'Seçilen aralık: Son 90 gün';
    case _StatementRange.days180:
      return 'Seçilen aralık: Son 180 gün';
    case _StatementRange.all:
      return 'Seçilen aralık: Tüm hareketler';
  }
}

Color _balanceColor(ThemeData theme, double balance) {
  if (balance > 0) return Colors.green;
  if (balance < 0) return Colors.red;
  return theme.textTheme.titleMedium?.color ?? Colors.black;
}

enum _StatementTypeFilter { all, invoice, payment }

final _statementTypeFilterProvider =
    StateProvider<_StatementTypeFilter>((ref) => _StatementTypeFilter.all);
