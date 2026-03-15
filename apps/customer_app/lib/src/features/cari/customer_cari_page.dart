import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../../constants/statement_labels_tr.dart';
import '../pdf/pdf_builders.dart';
import '../pdf/pdf_share.dart';

enum _StatementRange { days30, days90, days180, all }

class _CustomerStatementEntry {
  const _CustomerStatementEntry({
    required this.id,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.isOverdue,
    this.type,
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
  final String? type;
  final String? refId;
  final String? invoiceId;
  final String? invoiceStatus;

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

    final entry = _CustomerStatementEntry(
      id: rawId?.toString() ?? '',
      date: parsedDate,
      description: (map['description'] as String?) ?? '',
      debit: (map['debit'] as num?)?.toDouble() ?? 0,
      credit: (map['credit'] as num?)?.toDouble() ?? 0,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      isOverdue: map['is_overdue'] == true,
      type: (map['type'] as String?)?.trim(),
      refId: (map['ref_id'] as String?)?.trim(),
      invoiceId: _parseInvoiceId(map['invoice_id']),
      // Bazı view'larda invoice_status veya status alanı varsa buradan gelir.
      // Yoksa _enrichStatementTimes içinde invoices tablosundan zenginleştiriyoruz.
      invoiceStatus: (map['invoice_status'] ?? map['status'])?.toString().trim(),
    );
    assert(() {
      if (kDebugMode) {
        debugPrint(
          '[LEDGER] type=${entry.type} ref=${entry.refId} invoiceId=${entry.invoiceId}',
        );
      }
      return true;
    }());
    return entry;
  }

  double get net => debit - credit;
}

String? _parseInvoiceId(dynamic value) {
  if (value == null) return null;
  final asString = value.toString().trim();
  if (asString.isEmpty) return null;
  return asString;
}

final RegExp _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-'
  r'[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

bool _isUuid(String value) => _uuidRegex.hasMatch(value.trim());

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
  final ledgerIdsNeedingTime = <String>{};

  bool isMidnight(DateTime dt) =>
      dt.hour == 0 && dt.minute == 0 && dt.second == 0 && dt.millisecond == 0;

  for (final row in rows) {
    final t = (row.type ?? '').toLowerCase();
    final isInvoice = t == 'invoice' || (row.debit > 0 && row.credit == 0);
    final isPayment = t == 'payment' || (row.credit > 0 && row.debit == 0);
    final needsTime = isMidnight(row.date);

    // Legacy: geçmişte v_customer_statement_with_balance bazı hareketlerde
    // sadece YYYY-MM-DD döndürebiliyordu. Saat 00:00 ise (date-only),
    // created_at / ilgili tablo timestamp'i ile zenginleştir.
    if (isMidnight(row.date)) {
      final id = row.id.trim();
      if (id.isNotEmpty && _isUuid(id)) ledgerIdsNeedingTime.add(id);
    }

    if (isInvoice) {
      final id = (row.invoiceId ?? row.refId ?? '').trim();
      if (id.isNotEmpty && _isUuid(id)) invoiceIds.add(id);
    }
    if (needsTime && isPayment) {
      final id = (row.refId ?? '').trim();
      if (id.isNotEmpty && _isUuid(id)) paymentIds.add(id);
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
      debugPrint('[CUSTOMER][Statement] invoice time enrich failed: $e');
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
      debugPrint('[CUSTOMER][Statement] payment time enrich failed: $e');
    }
  }

  final ledgerCreatedAtById = <String, DateTime>{};
  if (ledgerIdsNeedingTime.isNotEmpty) {
    try {
      final data = await supabaseClient
          .from('ledger_entries')
          .select('id, created_at')
          .inFilter('id', ledgerIdsNeedingTime.toList());

      for (final row in (data as List<dynamic>)) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = (map['id'] ?? '').toString();
        final dt = _parseDateTime(map['created_at']);
        if (id.isNotEmpty && dt != null) {
          ledgerCreatedAtById[id] = dt;
        }
      }
    } catch (e) {
      debugPrint('[CUSTOMER][Statement] ledger time enrich failed: $e');
    }
  }

  DateTime? resolveEffectiveDate(_CustomerStatementEntry entry) {
    bool needsTime(DateTime dt) =>
        dt.hour == 0 && dt.minute == 0 && dt.second == 0 && dt.millisecond == 0;
    if (!needsTime(entry.date)) return null;

    final t = (entry.type ?? '').toLowerCase();
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

    final dt = ledgerCreatedAtById[entry.id.trim()];
    if (dt != null) return dt.toLocal();

    return null;
  }

  String? resolveInvoiceStatus(_CustomerStatementEntry entry) {
    final t = (entry.type ?? '').toLowerCase();
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

void _openInvoice(BuildContext context, String? invoiceId) {
  final id = (invoiceId ?? '').trim();
  if (id.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu hareket için fatura bulunamadı.'),
      ),
    );
    return;
  }
  context.go('/invoices/$id');
}

final _statementRangeProvider =
    StateProvider<_StatementRange>((ref) => _StatementRange.days30);

final customerBalanceNetProvider = FutureProvider.autoDispose<double>((ref) async {
  final customerId = ref.watch(customerIdProvider);
  if (customerId == null || customerId.isEmpty) return 0;

  final dynamic row = await supabaseClient
    .from('v_customer_balance')
    .select('net')
    .eq('customer_id', customerId)
    .maybeSingle();

  final Map<String, dynamic>? map =
    row == null ? null : Map<String, dynamic>.from(row as Map);
  return (map?['net'] as num?)?.toDouble() ?? 0;
});

final customerStatementProvider =
    FutureProvider.autoDispose<List<_CustomerStatementEntry>>((ref) async {
  final client = supabaseClient;
  final customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    // Router zaten oturum / eşleşme durumuna göre yönlendireceği için
    // burada boş liste döndürmek yeterli.
    return <_CustomerStatementEntry>[];
  }

  final range = ref.watch(_statementRangeProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime? fromDate;
  switch (range) {
    case _StatementRange.days30:
      fromDate = today.subtract(const Duration(days: 30));
      break;
    case _StatementRange.days90:
      fromDate = today.subtract(const Duration(days: 90));
      break;
    case _StatementRange.days180:
      fromDate = today.subtract(const Duration(days: 180));
      break;
    case _StatementRange.all:
      fromDate = null;
      break;
  }

  final data = await client
      .from('v_customer_statement_with_balance')
      .select()
      .eq('customer_id', customerId)
      .order('created_at', ascending: false)
      .limit(100);

  final rows = (data as List<dynamic>)
      .map((e) => _CustomerStatementEntry.fromMap(
            Map<String, dynamic>.from(e as Map),
          ))
      .toList();

  final enrichedRows = await _enrichStatementTimes(rows);

  // 30/90/180 filtreleri fetch sonrası uygulanır.
  final List<_CustomerStatementEntry> rangeFilteredRows;
  if (fromDate == null) {
    rangeFilteredRows = enrichedRows;
  } else {
    DateTime toDateOnly(DateTime value) =>
        DateTime(value.year, value.month, value.day);
    rangeFilteredRows = enrichedRows
        .where((e) => !toDateOnly(e.date).isBefore(fromDate!))
        .toList();
  }

  rangeFilteredRows.sort((a, b) => b.date.compareTo(a.date));

  final totalDebit =
      rangeFilteredRows.fold<double>(0, (sum, e) => sum + e.debit);
  final totalCredit =
      rangeFilteredRows.fold<double>(0, (sum, e) => sum + e.credit);
  final net = totalDebit - totalCredit;

  var invoiceCount = 0;
  var paymentCount = 0;
  var otherCount = 0;

  for (final row in rangeFilteredRows) {
    final t = (row.type ?? '').toLowerCase();
    if (t == 'invoice') {
      invoiceCount++;
    } else if (t == 'payment') {
      paymentCount++;
    } else {
      // Heuristik: sadece debit veya sadece credit ise yine sınıflandır.
      if (row.debit > 0 && row.credit == 0) {
        invoiceCount++;
      } else if (row.credit > 0 && row.debit == 0) {
        paymentCount++;
      } else {
        otherCount++;
      }
    }
  }

  final authUserId = supabaseClient.auth.currentUser?.id;
  final fromStr = fromDate != null ? _toIsoDate(fromDate) : 'null';
  final toStr = _toIsoDate(now);

  assert(() {
    if (kDebugMode) {
      debugPrint(
        '[CUSTOMER][Statement] authUserId=$authUserId customerId=$customerId '
        'range=$range from=$fromStr to=$toStr fetched=${rows.length} '
        'rows=${rangeFilteredRows.length} '
        'invoice=$invoiceCount payment=$paymentCount other=$otherCount '
        'totalDebit=$totalDebit totalCredit=$totalCredit net=$net',
      );
    }
    return true;
  }());

  return rangeFilteredRows;
});

class CustomerCariPage extends ConsumerWidget {
  const CustomerCariPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(customerStatementProvider);
    final range = ref.watch(_statementRangeProvider);
    final balanceNetAsync = ref.watch(customerBalanceNetProvider);

    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Cari / Ekstre',
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            color: Colors.black,
          ) ??
          theme.textTheme.titleLarge?.copyWith(color: Colors.black),
      actions: [
        IconButton(
          tooltip: 'Ekstreyi paylaş (PDF)',
          icon: const Icon(Icons.ios_share_outlined),
          onPressed: () async {
            try {
              final entries = await ref.read(customerStatementProvider.future);
              final balanceNet =
                  await ref.read(customerBalanceNetProvider.future);
              if (!context.mounted) return;

              if (entries.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Seçilen aralıkta paylaşılacak hareket yok.'),
                  ),
                );
                return;
              }

              final totalDebit = entries.fold<double>(
                0,
                (sum, e) => sum + e.debit,
              );
              final totalCredit = entries.fold<double>(
                0,
                (sum, e) => sum + e.credit,
              );
              final header = StatementHeaderInfo(
                customerName: 'Cari',
                rangeLabel: _rangeLabel(range),
                currentBalance: balanceNet,
                totalDebit: totalDebit,
                totalCredit: totalCredit,
                net: totalDebit - totalCredit,
              );

              String typeLabel(_CustomerStatementEntry entry) {
                if (entry.debit > 0 && entry.credit == 0) return 'Borç';
                if (entry.credit > 0 && entry.debit == 0) return 'Alacak';
                return 'Diğer';
              }

              final rows = entries
                  .map(
                    (e) => StatementPdfRow(
                      date: e.date,
                      type: typeLabel(e),
                      description: e.description,
                      debit: e.debit,
                      credit: e.credit,
                      balance: e.balance,
                    ),
                  )
                  .toList();

              final bytes = await buildStatementPdf(rows, header);

              await saveAndSharePdf(
                bytes,
                'cari_ekstre.pdf',
                text: 'Cari ekstresinin PDF kopyası.',
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('PDF oluşturulamadı: ${e.toString()}'),
                ),
              );
            }
          },
        ),
      ],
      body: entriesAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            const _FaturalarimMenuCard(),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                ChoiceChip(
                  label: const Text(
                    'Son 30 gün',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.days30,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.days30;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
                ChoiceChip(
                  label: const Text(
                    'Son 90 gün',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.days90,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.days90;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
                ChoiceChip(
                  label: const Text(
                    'Son 180 gün',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.days180,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.days180;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
                ChoiceChip(
                  label: const Text(
                    'Tümü',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.all,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.all;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              _rangeLabel(range),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s16),
            const AppLoadingState(),
          ],
        ),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cari özeti yüklenemedi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text('$e'),
                    const SizedBox(height: AppSpacing.s8),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(customerStatementProvider),
                      child: const Text('Tekrar dene'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            const _FaturalarimMenuCard(),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                ChoiceChip(
                  label: const Text(
                    'Son 30 gün',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.days30,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.days30;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
                ChoiceChip(
                  label: const Text(
                    'Son 90 gün',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.days90,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.days90;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
                ChoiceChip(
                  label: const Text(
                    'Son 180 gün',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.days180,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.days180;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
                ChoiceChip(
                  label: const Text(
                    'Tümü',
                    style: TextStyle(color: Colors.black),
                  ),
                  selected: range == _StatementRange.all,
                  onSelected: (_) {
                    ref.read(_statementRangeProvider.notifier).state =
                        _StatementRange.all;
                    ref.invalidate(customerStatementProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              _rangeLabel(range),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s16),
            AppErrorState(
              message: 'Ekstre hareketleri yüklenemedi: $e',
              onRetry: () => ref.invalidate(customerStatementProvider),
            ),
          ],
        ),
        data: (entries) {
          final summary = _buildSummary(entries);
          final balanceNet = balanceNetAsync.value ?? 0;

          final totalDebit = entries.fold<double>(
            0,
            (sum, e) => sum + e.debit,
          );
          final totalCredit = entries.fold<double>(
            0,
            (sum, e) => sum + e.credit,
          );

          var invoiceCount = 0;
          var paymentCount = 0;
          for (final e in entries) {
            final t = (e.type ?? '').toLowerCase();
            if (t == 'invoice' || (e.debit > 0 && e.credit == 0)) {
              invoiceCount++;
            } else if (t == 'payment' || (e.credit > 0 && e.debit == 0)) {
              paymentCount++;
            }
          }
          final netTotal = totalDebit - totalCredit;
          // Supabase backend'e dokunmadan: ekstrede en yeni kayıt üstte.
          final displayEntries = [...entries]
            ..sort((a, b) {
              final byDate = b.date.toLocal().compareTo(a.date.toLocal());
              if (byDate != 0) return byDate;
              return b.id.compareTo(a.id);
            });

          final firstType = displayEntries.isNotEmpty
              ? (displayEntries.first.type ?? '-')
              : '-';
          final lastType = displayEntries.isNotEmpty
              ? (displayEntries.last.type ?? '-')
              : '-';

          assert(() {
            if (kDebugMode) {
              debugPrint(
                '[CUSTOMER][StatementView] rows=${displayEntries.length} '
                'invoice=$invoiceCount payment=$paymentCount '
                'netTotal=$netTotal firstType=$firstType lastType=$lastType '
                'balanceNet=$balanceNet',
              );

              // İlk birkaç satırı logla: date, type, debit, credit, description, ref_id.
              final sampleCount =
                  displayEntries.length > 5 ? 5 : displayEntries.length;
              for (var i = 0; i < sampleCount; i++) {
                final e = displayEntries[i];
                debugPrint(
                  '[CUSTOMER][Row $i] date=${_formatDate(e.date)} '
                  'type=${e.type ?? '-'} debit=${e.debit} credit=${e.credit} '
                  'desc=${e.description} refId=${e.refId ?? '-'}',
                );
              }
            }
            return true;
          }());

          if (displayEntries.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                            return Text(
                              _formatAmount(balanceNet),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _balanceColor(theme, balanceNet),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                const _FaturalarimMenuCard(),
                const SizedBox(height: AppSpacing.s12),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    ChoiceChip(
                      label: const Text(
                        'Son 30 gün',
                        style: TextStyle(color: Colors.black),
                      ),
                      selected: range == _StatementRange.days30,
                      onSelected: (_) {
                        ref.read(_statementRangeProvider.notifier).state =
                            _StatementRange.days30;
                        ref.invalidate(customerStatementProvider);
                      },
                    ),
                    ChoiceChip(
                      label: const Text(
                        'Son 90 gün',
                        style: TextStyle(color: Colors.black),
                      ),
                      selected: range == _StatementRange.days90,
                      onSelected: (_) {
                        ref.read(_statementRangeProvider.notifier).state =
                            _StatementRange.days90;
                        ref.invalidate(customerStatementProvider);
                      },
                    ),
                    ChoiceChip(
                      label: const Text(
                        'Son 180 gün',
                        style: TextStyle(color: Colors.black),
                      ),
                      selected: range == _StatementRange.days180,
                      onSelected: (_) {
                        ref.read(_statementRangeProvider.notifier).state =
                            _StatementRange.days180;
                        ref.invalidate(customerStatementProvider);
                      },
                    ),
                    ChoiceChip(
                      label: const Text(
                        'Tümü',
                        style: TextStyle(color: Colors.black),
                      ),
                      selected: range == _StatementRange.all,
                      onSelected: (_) {
                        ref.read(_statementRangeProvider.notifier).state =
                            _StatementRange.all;
                        ref.invalidate(customerStatementProvider);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  _rangeLabel(range),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.s16),
                AppEmptyState(
                  title: 'Hareket bulunamadı.',
                  subtitle: 'Seçilen tarih aralığında bu cari için hareket yok.',
                  icon: Icons.receipt_long_outlined,
                  action: OutlinedButton.icon(
                    onPressed: () {
                      ref.read(_statementRangeProvider.notifier).state =
                          _StatementRange.all;
                      ref.invalidate(customerStatementProvider);
                    },
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Filtreleri temizle'),
                  ),
                ),
              ],
            );
          }

          final ledgerItems = _buildCustomerLedgerItems(displayEntries);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(customerStatementProvider);
              ref.invalidate(customerBalanceNetProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 5 + ledgerItems.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Card(
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
                              return Text(
                                _formatAmount(balanceNet),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: _balanceColor(theme, balanceNet),
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
                                  amount: summary.overdue,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: _SummaryItem(
                                  label: 'Vadesi gelmemiş',
                                  amount: summary.notDue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (index == 1) {
                  return const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.s12),
                    child: _FaturalarimMenuCard(),
                  );
                }
                if (index == 2) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s12),
                    child: Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      children: [
                        ChoiceChip(
                          label: const Text(
                            'Son 30 gün',
                            style: TextStyle(color: Colors.black),
                          ),
                          selected: range == _StatementRange.days30,
                          onSelected: (_) {
                            ref.read(_statementRangeProvider.notifier).state =
                                _StatementRange.days30;
                            ref.invalidate(customerStatementProvider);
                          },
                        ),
                        ChoiceChip(
                          label: const Text(
                            'Son 90 gün',
                            style: TextStyle(color: Colors.black),
                          ),
                          selected: range == _StatementRange.days90,
                          onSelected: (_) {
                            ref.read(_statementRangeProvider.notifier).state =
                                _StatementRange.days90;
                            ref.invalidate(customerStatementProvider);
                          },
                        ),
                        ChoiceChip(
                          label: const Text(
                            'Son 180 gün',
                            style: TextStyle(color: Colors.black),
                          ),
                          selected: range == _StatementRange.days180,
                          onSelected: (_) {
                            ref.read(_statementRangeProvider.notifier).state =
                                _StatementRange.days180;
                            ref.invalidate(customerStatementProvider);
                          },
                        ),
                        ChoiceChip(
                          label: const Text(
                            'Tümü',
                            style: TextStyle(color: Colors.black),
                          ),
                          selected: range == _StatementRange.all,
                          onSelected: (_) {
                            ref.read(_statementRangeProvider.notifier).state =
                                _StatementRange.all;
                            ref.invalidate(customerStatementProvider);
                          },
                        ),
                      ],
                    ),
                  );
                }
                if (index == 3) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s4),
                    child: Text(
                      _rangeLabel(range),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                if (index == 4) {
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s8),
                    child: Text(
                      '${displayEntries.length} hareket listeleniyor',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  );
                }

                final listIndex = index - 5;
                if (listIndex < ledgerItems.length) {
                  final item = ledgerItems[listIndex];
                  if (item is DateTime) {
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s8),
                      child: _CustomerLedgerDayHeader(date: item),
                    );
                  }

                  final listRow = item as _CustomerLedgerListRow;
                  return _CustomerLedgerEntryTile(
                    entry: listRow.entry,
                    isZebra: listRow.isZebra,
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.s12),
                  child: _CustomerLedgerTotalsFooter(
                    totalDebit: totalDebit,
                    totalCredit: totalCredit,
                  ),
                );
              },
            ),
          );
        },
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

  final netTotal = entries.fold<double>(0, (sum, e) => sum + e.net);

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

  final summary =
      _StatementSummary(balance: netTotal, overdue: overdue, notDue: notDue);

  debugPrint(
    '[CUSTOMER][StatementSummary] rows=${entries.length} '
    'balance=${summary.balance} overdue=${summary.overdue} notDue=${summary.notDue} '
    'netTotal=$netTotal',
  );

  return summary;
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.amount,
  });

  final String label;
  final double amount;

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
          _formatAmount(amount),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

String _formatAmount(double value) => formatMoney(value);

String _formatDate(DateTime date) => formatDateTime(date);

String _formatDateOnly(DateTime date) => formatDate(date);

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

List<Object> _buildCustomerLedgerItems(List<_CustomerStatementEntry> rows) {
  final items = <Object>[];
  DateTime? lastDate;
  var zebra = false;

  for (final row in rows) {
    final local = row.date.toLocal();
    final dateOnly = DateTime(local.year, local.month, local.day);

    if (lastDate == null || !_isSameDay(dateOnly, lastDate)) {
      items.add(dateOnly);
      lastDate = dateOnly;
      zebra = false;
    }

    zebra = !zebra;
    items.add(_CustomerLedgerListRow(entry: row, isZebra: zebra));
  }

  return items;
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

String _toIsoDate(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.toIso8601String().split('T').first;
}

Color _balanceColor(ThemeData theme, double balance) {
  if (balance > 0) return Colors.green;
  if (balance < 0) return Colors.red;
  return theme.textTheme.titleMedium?.color ?? Colors.black;
}

class _CustomerLedgerDayHeader extends StatelessWidget {
  const _CustomerLedgerDayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _formatDateOnly(date),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CustomerLedgerListRow {
  const _CustomerLedgerListRow({
    required this.entry,
    required this.isZebra,
  });

  final _CustomerStatementEntry entry;
  final bool isZebra;
}

class _CustomerLedgerEntryTile extends StatelessWidget {
  const _CustomerLedgerEntryTile({
    required this.entry,
    required this.isZebra,
  });

  final _CustomerStatementEntry entry;
  final bool isZebra;

  String _typeLabel(_CustomerStatementEntry entry) {
    final t = (entry.type ?? '').toLowerCase();
    if (t == 'refund') return 'İade';
    if (t == 'invoice') return 'Fatura / Borç';
    if (t == 'payment') return 'Tahsilat / Alacak';

    if (entry.debit > 0 && entry.credit == 0) return 'Fatura / Borç';
    if (entry.credit > 0 && entry.debit == 0) return 'Tahsilat / Alacak';
    return 'Diğer';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final entryType = (entry.type ?? '').trim().toLowerCase();
    final entryInvoiceStatus = (entry.invoiceStatus ?? '').trim().toLowerCase();
    final isCancelledInvoice =
      entryType == 'invoice' && entryInvoiceStatus == 'cancelled';

    final baseColor = theme.colorScheme.surface;
    final zebraOverlay =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.04);
    final cancelledOverlay =
      theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18);
    final background = isCancelledInvoice
      ? Color.alphaBlend(cancelledOverlay, baseColor)
      : (isZebra ? Color.alphaBlend(zebraOverlay, baseColor) : baseColor);

    final isRefund = entryType == 'refund';
    final hasInvoice = entry.invoiceId != null && entry.invoiceId!.isNotEmpty;

    final debitText = entry.debit == 0 ? '—' : _formatAmount(entry.debit);

    final String creditText;
    if (isRefund) {
      final signed = _signedAmountForDisplay(entry);
      creditText = signed == 0 ? '—' : _formatAmount(signed);
    } else {
      creditText = entry.credit == 0 ? '—' : _formatAmount(entry.credit);
    }

    final balanceValue = entry.balance;
    final balanceText = _formatAmount(balanceValue.abs());

    final mutedTextColor =
      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);

    final effectiveDescription = isCancelledInvoice
      ? 'İptal edilen fatura'
      : entry.description;

    final badgeLabel = isCancelledInvoice ? 'İptal' : _typeLabel(entry);

    final badgeColor = isCancelledInvoice
      ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
      : isRefund
        ? theme.colorScheme.tertiary.withValues(alpha: 0.08)
        : entry.debit > 0 && entry.credit == 0
          ? theme.colorScheme.error.withValues(alpha: 0.08)
          : entry.credit > 0 && entry.debit == 0
            ? theme.colorScheme.secondary.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4);
    final badgeTextColor = isCancelledInvoice
      ? mutedTextColor
      : isRefund
        ? theme.colorScheme.tertiary
        : entry.debit > 0 && entry.credit == 0
          ? theme.colorScheme.error
          : entry.credit > 0 && entry.debit == 0
            ? theme.colorScheme.secondary
            : theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s4),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openInvoice(context, entry.invoiceId),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _formatDate(entry.date),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isCancelledInvoice ? mutedTextColor : null,
                        ),
                      ),
                    ),
                    if (hasInvoice)
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 16,
                        color: (isCancelledInvoice
                                ? mutedTextColor
                                : theme.colorScheme.primary)
                            .withValues(alpha: 0.7),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badgeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeTextColor,
                        ),
                      ),
                    ),
                    Text(
                      effectiveDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isCancelledInvoice ? mutedTextColor : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Row(
                  children: [
                    Expanded(
                      child: _AmountPair(
                        label: kDebtLabel,
                        value: debitText,
                        valueColor: isCancelledInvoice
                            ? mutedTextColor
                            : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: _AmountPair(
                        label: kCreditLabel,
                        value: creditText,
                        valueColor:
                            isCancelledInvoice ? mutedTextColor : Colors.green,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Expanded(
                      child: _AmountPair(
                        label: _balanceDirectionLabel(balanceValue),
                        value: balanceText,
                        valueColor: isCancelledInvoice
                            ? mutedTextColor
                            : _balanceColor(theme, balanceValue),
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

class _AmountPair extends StatelessWidget {
  const _AmountPair({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.s4),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

double _signedAmountForDisplay(_CustomerStatementEntry entry) {
  final isRefund = (entry.type ?? '').toLowerCase() == 'refund';

  final raw = entry.credit != 0
      ? entry.credit
      : entry.debit != 0
          ? entry.debit
          : 0.0;

  if (!isRefund) return raw;

  // Refund her zaman negatif gibi gösterilsin (çift eksi üretmeden).
  return raw > 0 ? -raw : raw;
}

String _balanceDirectionLabel(double balance) {
  return kBalanceLabel;
}

class _CustomerLedgerTotalsFooter extends StatelessWidget {
  const _CustomerLedgerTotalsFooter({
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
              child: _CustomerTotalItem(
                label: 'Toplam Borç',
                value: totalDebit,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _CustomerTotalItem(
                label: 'Toplam Alacak',
                value: totalCredit,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: _CustomerTotalItem(
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

class _CustomerTotalItem extends StatelessWidget {
  const _CustomerTotalItem({
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

class _FaturalarimMenuCard extends StatelessWidget {
  const _FaturalarimMenuCard();

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
                      'Faturalarım',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'Siparişlerinizin faturalarını görüntüleyin.',
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
