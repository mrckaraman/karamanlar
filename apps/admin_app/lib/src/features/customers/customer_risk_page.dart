import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import 'customer_finance_providers.dart';
import 'customer_general_tab.dart';

class CustomerRiskPage extends ConsumerStatefulWidget {
  const CustomerRiskPage({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  ConsumerState<CustomerRiskPage> createState() => _CustomerRiskPageState();
}

class _CustomerRiskPageState extends ConsumerState<CustomerRiskPage> {
  final TextEditingController _riskNoteController = TextEditingController();
  bool _initialized = false;
  AsyncValue<void> _saveState = const AsyncData(null);

  @override
  void dispose() {
    _riskNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(customerBalanceProvider(widget.customerId));
    final detailAsync = ref.watch(customerDetailProvider(widget.customerId));
    final agingAsync = ref.watch(customerAgingProvider(widget.customerId));

    if (balanceAsync.isLoading || detailAsync.isLoading || agingAsync.isLoading) {
      return const AppLoadingState();
    }

    if (balanceAsync.hasError) {
      return AppErrorState(
        message:
            'Bakiye bilgisi yüklenemedi: ${AppException.messageOf(balanceAsync.error!)}',
        onRetry: () => ref.invalidate(customerBalanceProvider(widget.customerId)),
      );
    }
    if (detailAsync.hasError) {
      return AppErrorState(
        message:
            'Cari kartı yüklenemedi: ${AppException.messageOf(detailAsync.error!)}',
        onRetry: () => ref.invalidate(customerDetailProvider(widget.customerId)),
      );
    }
    if (agingAsync.hasError) {
      return AppErrorState(
        message:
            'Vade bilgisi yüklenemedi: ${AppException.messageOf(agingAsync.error!)}',
        onRetry: () => ref.invalidate(customerAgingProvider(widget.customerId)),
      );
    }

    final balance = balanceAsync.value!;
    final customer = detailAsync.value!;
    final agingRows = agingAsync.value ?? const <AgingRow>[];

    if (!_initialized) {
      _riskNoteController.text = customer.riskNote ?? '';
      _initialized = true;
    }

    final limit = customer.limitAmount ?? 0;
    final dueDays = customer.dueDays ?? 0;
    final net = balance.net;

    final overdueAmount = agingRows
        .where((r) => r.bucket != '0-7')
        .fold<double>(0, (sum, r) => sum + r.amount);

    final hasLimitExceeded = limit > 0 && net > limit;
    final hasOverdue = overdueAmount > 0;

    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Risk & Limit',
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Uyarılar',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      spacing: AppSpacing.s8,
                      runSpacing: AppSpacing.s8,
                      children: [
                        if (hasLimitExceeded)
                          Chip(
                            label: const Text('Limit aşıldı'),
                            backgroundColor:
                                Colors.red.withValues(alpha: 0.08),
                            labelStyle: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (hasOverdue)
                          Chip(
                            label: const Text('Vadesi geçmiş borç var'),
                            backgroundColor:
                                Colors.orange.withValues(alpha: 0.08),
                            labelStyle: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (!hasLimitExceeded && !hasOverdue)
                          Chip(
                            label: const Text('Risk normal'),
                            backgroundColor:
                                Colors.green.withValues(alpha: 0.08),
                            labelStyle: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Limit & Bakiye',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    _SummaryRow(
                      label: 'Kredi limiti',
                      value: limit,
                    ),
                    _SummaryRow(
                      label: 'Azami vade (gün)',
                      value: dueDays.toDouble(),
                      isInteger: true,
                    ),
                    _SummaryRow(
                      label: 'Net bakiye (borç - alacak)',
                      value: net,
                    ),
                    _SummaryRow(
                      label: 'Toplam vadesi geçmiş borç',
                      value: overdueAmount,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Risk notu',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    TextField(
                      controller: _riskNoteController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Bu cari için risk değerlendirmesini yazın...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: PrimaryButton(
                        label: _saveState.isLoading ? 'Kaydediliyor...' : 'Kaydet',
                        icon: Icons.save,
                        expand: false,
                        onPressed: _saveState.isLoading
                            ? null
                            : () => _saveRiskNote(customer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRiskNote(Customer customer) async {
    setState(() => _saveState = const AsyncLoading());

    final result = await AsyncValue.guard(() async {
      final text = _riskNoteController.text.trim();
      final detailsPayload = <String, dynamic>{
        'customer_id': customer.id,
        'risk_note': text.isEmpty ? null : text,
      };

      await supabaseClient
          .from('customer_details')
          .upsert(detailsPayload, onConflict: 'customer_id')
          .select('customer_id')
          .single();

      unawaited(
        auditService.logChange(
          entity: 'limits',
          entityId: customer.id,
          action: 'update',
          oldValue: <String, dynamic>{
            'risk_note': customer.riskNote,
          },
          newValue: <String, dynamic>{
            'risk_note': text.isEmpty ? null : text,
          },
        ),
      );
    });

    if (!mounted) return;

    setState(() => _saveState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kaydetme hatası: ${AppException.messageOf(result.error!)}'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Risk notu kaydedildi.')),
    );
    ref.invalidate(customerDetailProvider(customer.id));
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.isInteger = false,
  });

  final String label;
  final double value;
  final bool isInteger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            isInteger ? value.toInt().toString() : _formatAmount(value),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

String _formatAmount(double value) {
  return formatMoney(value);
}
