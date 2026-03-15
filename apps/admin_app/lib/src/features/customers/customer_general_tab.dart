import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import 'customer_finance_providers.dart';

final customerDetailProvider = FutureProvider.autoDispose
    .family<Customer, String>((ref, customerId) async {
  // Temel müşteri kaydını çek
  final coreData = await supabaseClient
      .from('customers')
      .select('*')
      .eq('id', customerId)
      .single();

  final baseMap = Map<String, dynamic>.from(coreData as Map);

  // Ek ticari / risk / adres detaylarını customer_details tablosundan birleştir
  final details = await supabaseClient
      .from('customer_details')
      .select(
        'customer_id, tax_office, tax_no, city, district, notes, tags, '
        'limit_amount, price_tier, due_days, risk_note, '
        'group_name, sub_group, alt_group, opening_balance, '
        'opening_balance_type, warn_on_limit_exceeded, marketer_name',
      )
      .eq('customer_id', customerId)
      .maybeSingle();

  if (details != null) {
    final detailsMap = Map<String, dynamic>.from(details as Map);
    detailsMap.remove('customer_id');
    baseMap.addAll(detailsMap);
  }

  return Customer.fromMap(baseMap);
});

class CustomerGeneralTab extends ConsumerWidget {
  const CustomerGeneralTab({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));
    final balanceAsync = ref.watch(customerBalanceProvider(customerId));

    if (customerAsync.isLoading || balanceAsync.isLoading) {
      return const AppLoadingState();
    }

    if (customerAsync.hasError) {
      return AppErrorState(
        message: 'Cari bilgileri yüklenemedi: ${customerAsync.error}',
        onRetry: () => ref.invalidate(customerDetailProvider(customerId)),
      );
    }

    final customer = customerAsync.value!;
    final balance = balanceAsync.asData?.value;

    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 960;

    final phoneText = _formatCustomerPhone(customer.phone);
    final emailText =
        (customer.email ?? '').trim().isEmpty ? 'E-posta belirtilmemiş.' : customer.email!.trim();

    final addressSummary = _buildAddressSummary(customer);
    final addressDetail =
        (customer.address ?? '').trim().isEmpty ? 'Adres bilgisi girilmemiş.' : customer.address!.trim();

    final openingBalance = customer.openingBalance;
    final openingType = customer.openingBalanceType;

    final limit = customer.limitAmount ?? 0;
    final net = balance?.net ?? 0;
    final hasLimit = limit > 0;
    final usedLimit = hasLimit && net > 0 ? (net > limit ? limit : net) : 0;
    final hasLimitExceeded = hasLimit && net > limit;

    Color netColor;
    if (net > 0) {
      netColor = Colors.red.shade600;
    } else if (net < 0) {
      netColor = Colors.green.shade600;
    } else {
      netColor = theme.colorScheme.onSurface;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
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
                          customer.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s4),
                        Wrap(
                          spacing: AppSpacing.s8,
                          runSpacing: AppSpacing.s4,
                          children: [
                            _BadgeChip(
                              label: customer.code.isEmpty
                                  ? 'Otomatik kod atanacak'
                                  : customer.code,
                              color: theme.colorScheme.primaryContainer,
                              textColor: theme.colorScheme.onPrimaryContainer,
                            ),
                            _BadgeChip(
                              label: _customerTypeLabel(customer.customerType),
                              color: theme.colorScheme.secondaryContainer,
                              textColor: theme.colorScheme.onSecondaryContainer,
                            ),
                            _StatusChip(isActive: customer.isActive),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                        vertical: AppSpacing.s4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      GoRouter.of(context).go('/customers/${customer.id}/edit');
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Düzenle'),
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hızlı İşlemler',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Wrap(
                    spacing: AppSpacing.s8,
                    runSpacing: AppSpacing.s8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          GoRouter.of(context)
                              .go('/customers/${customer.id}/statement');
                        },
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Cari Ekstre'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = isWide || constraints.maxWidth >= 960;

              final leftColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: _SectionColumn(
                        title: 'Kimlik',
                        children: [
                          _KeyValueRow(
                            label: 'Cari unvan',
                            value: customer.displayName,
                          ),
                          _KeyValueRow(
                            label: 'Cari kodu',
                            value: customer.code.isEmpty
                                ? 'Kod atanmadı (otomatik üretilecek)'
                                : customer.code,
                          ),
                          _KeyValueRow(
                            label: 'Cari türü',
                            value: _customerTypeLabel(customer.customerType),
                          ),
                          _KeyValueRow(
                            label: 'Durum',
                            value: customer.isActive ? 'Aktif' : 'Pasif',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: _SectionColumn(
                        title: 'İletişim',
                        children: [
                          _KeyValueRow(
                            label: 'Telefon',
                            value: phoneText,
                          ),
                          _KeyValueRow(
                            label: 'E-posta',
                            value: emailText,
                          ),
                          _KeyValueRow(
                            label: 'Adres (özet)',
                            value: addressSummary,
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              addressDetail,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );

              final rightColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: _SectionColumn(
                        title: 'Finansal Özet',
                        children: [
                          Text(
                            formatMoney(net.abs()),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: netColor,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            net > 0
                                ? 'Güncel bakiye: Borç'
                                : net < 0
                                    ? 'Güncel bakiye: Alacak'
                                    : 'Güncel bakiye yok',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          _KeyValueRow(
                            label: 'Açılış bakiyesi',
                            value: openingBalance == null
                              ? 'Tanımlı açılış bakiyesi yok.'
                              : formatMoney(openingBalance),
                            trailing: openingBalance == null
                              ? null
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.s8,
                                      vertical: AppSpacing.s4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (openingType == 'credit'
                                              ? Colors.green.shade50
                                              : Colors.red.shade50),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      openingType == 'credit'
                                          ? 'Alacak'
                                          : 'Borç',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: openingType == 'credit'
                                            ? Colors.green.shade700
                                            : Colors.red.shade700,
                                      ),
                                    ),
                                  ),
                          ),
                          _KeyValueRow(
                            label: 'Vade (gün)',
                            value: '${customer.dueDays ?? 30} gün',
                          ),
                          _KeyValueRow(
                            label: 'Fiyat listesi',
                            value: 'Fiyat Listesi ${customer.priceListNo ?? 4}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: _SectionColumn(
                        title: 'Risk & Limit',
                        children: [
                          _KeyValueRow(
                            label: 'Kredi limiti',
                            value: hasLimit
                                ? formatMoney(limit)
                                : 'Tanımlı kredi limiti yok.',
                          ),
                          _KeyValueRow(
                            label: 'Kullanılan limit',
                            value: hasLimit
                                ? formatMoney(usedLimit)
                                : '-',
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Row(
                            children: [
                              Icon(
                                hasLimitExceeded
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline,
                                size: 18,
                                color: hasLimitExceeded
                                    ? Colors.red.shade600
                                    : Colors.green.shade600,
                              ),
                              const SizedBox(width: AppSpacing.s4),
                              Expanded(
                                child: Text(
                                  hasLimitExceeded
                                      ? 'Limit aşıldı: net borç tanımlı limitin üzerinde.'
                                      : 'Limit dahilinde: net borç limit içerisinde.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: hasLimitExceeded
                                        ? Colors.red.shade700
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              (customer.riskNote ?? '').isEmpty
                                  ? 'Risk notu girilmemiş.'
                                  : customer.riskNote!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );

              if (twoColumns) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: leftColumn),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(child: rightColumn),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  leftColumn,
                  const SizedBox(height: AppSpacing.s8),
                  rightColumn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _customerTypeLabel(String? raw) {
  switch (raw) {
    case 'individual':
      return 'Bireysel';
    case 'commercial':
      return 'Ticari';
    default:
      return 'Belirtilmemiş';
  }
}

String _formatCustomerPhone(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Telefon belirtilmemiş.';

  var digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('90') && digits.length > 10) {
    digits = digits.substring(2);
  }
  if (digits.length == 10 && digits.startsWith('5')) {
    digits = '0$digits';
  }
  if (digits.length != 11 || !digits.startsWith('05')) {
    return value;
  }

  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i == 4 || i == 7 || i == 9) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String _buildAddressSummary(Customer customer) {
  final parts = <String>[
    if ((customer.district ?? '').trim().isNotEmpty)
      customer.district!.trim(),
    if ((customer.city ?? '').trim().isNotEmpty)
      customer.city!.trim(),
  ];
  if (parts.isEmpty) {
    return 'Adres özeti yok.';
  }
  return parts.join(' / ');
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
            ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.isActive,
  });

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isActive ? Colors.green.shade50 : Colors.grey.shade200;
    final textColor =
        isActive ? Colors.green.shade700 : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        isActive ? 'Aktif' : 'Pasif',
        style: theme.textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}

class _SectionColumn extends StatelessWidget {
  const _SectionColumn({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.s8),
        ...children,
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.s4),
            trailing!,
          ],
        ],
      ),
    );
  }
}
