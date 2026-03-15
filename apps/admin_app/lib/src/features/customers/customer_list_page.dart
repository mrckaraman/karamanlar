import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';

final _customerSearchProvider = StateProvider<String>((ref) => '');

enum _CustomerFilterChip { active, passive, debtor, creditor, risky }

final _customerFilterChipsProvider =
    StateProvider<Set<_CustomerFilterChip>>(
  (ref) => {_CustomerFilterChip.active},
);

final customersFutureProvider =
    FutureProvider.autoDispose<List<Customer>>((ref) async {
  final search = ref.watch(_customerSearchProvider);
  final chips = ref.watch(_customerFilterChipsProvider);

  final isActive = _mapChipsToIsActive(chips);

  return customerRepository.fetchCustomers(
    search: search.trim().isEmpty ? null : search.trim(),
    isActive: isActive,
    limit: 100,
  );
});

class CustomerListPage extends ConsumerWidget {
  const CustomerListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customersAsync = ref.watch(customersFutureProvider);
    final chips = ref.watch(_customerFilterChipsProvider);

    final summary = customersAsync.maybeWhen<_CustomerSummaryStats?>(
      data: (customers) {
        final filtered = _applyLocalFilters(customers, chips);
        return _buildSummary(filtered);
      },
      orElse: () => null,
    );

    return AppScaffold(
      title: 'Cari Bilgileri',
      floatingActionButton: FloatingActionButton(
        onPressed: () => GoRouter.of(context).go('/customers/new'),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary != null) ...[
              _CustomerSummaryHeader(stats: summary),
              const SizedBox(height: AppSpacing.s16),
            ],
            AppSearchField(
              hintText: 'Ünvan / kod / telefon / vergi no ara',
              padded: false,
              onChanged: (value) =>
                  ref.read(_customerSearchProvider.notifier).state = value,
            ),
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                _FilterChipToggle(
                  label: 'Aktif',
                  chip: _CustomerFilterChip.active,
                  chips: chips,
                  onChanged: (updated) => ref
                      .read(_customerFilterChipsProvider.notifier)
                      .state = updated,
                ),
                _FilterChipToggle(
                  label: 'Pasif',
                  chip: _CustomerFilterChip.passive,
                  chips: chips,
                  onChanged: (updated) => ref
                      .read(_customerFilterChipsProvider.notifier)
                      .state = updated,
                ),
                _FilterChipToggle(
                  label: 'Borçlu',
                  chip: _CustomerFilterChip.debtor,
                  chips: chips,
                  onChanged: (updated) => ref
                      .read(_customerFilterChipsProvider.notifier)
                      .state = updated,
                ),
                _FilterChipToggle(
                  label: 'Alacaklı',
                  chip: _CustomerFilterChip.creditor,
                  chips: chips,
                  onChanged: (updated) => ref
                      .read(_customerFilterChipsProvider.notifier)
                      .state = updated,
                ),
                _FilterChipToggle(
                  label: 'Riskli',
                  chip: _CustomerFilterChip.risky,
                  chips: chips,
                  onChanged: (updated) => ref
                      .read(_customerFilterChipsProvider.notifier)
                      .state = updated,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Expanded(
              child: customersAsync.when(
                loading: () => const AppLoadingState(),
                error: (e, _) => AppErrorState(
                  message: 'Cari listesi yüklenemedi: ${AppException.messageOf(e)}',
                  onRetry: () =>
                      ref.refresh(customersFutureProvider.future),
                ),
                data: (customers) {
                  final filteredCustomers =
                      _applyLocalFilters(customers, chips);

                  if (filteredCustomers.isEmpty) {
                    return _CustomerEmptyState(
                      onCreate: () =>
                          GoRouter.of(context).go('/customers/new'),
                    );
                  }

                  return ListView.separated(
                    itemCount: filteredCustomers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = filteredCustomers[index];
                      return _CustomerRow(
                        customer: customer,
                        onTap: () {
                          GoRouter.of(context)
                              .go('/customers/${customer.id}');
                        },
                        onEdit: () {
                          GoRouter.of(context).go(
                            '/customers/${customer.id}/edit',
                            extra: customer,
                          );
                        },
                        onToggleActive: () async {
                          final makePassive = customer.isActive;
                          final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) {
                                  return AlertDialog(
                                    title: Text(
                                        makePassive ? 'Cariyi pasife al' : 'Cariyi aktifleştir'),
                                    content: Text(
                                      makePassive
                                          ? 'Bu cari pasife alınacak. Devam etmek istiyor musunuz?'
                                          : 'Bu cari yeniden aktif hale getirilecek. Devam etmek istiyor musunuz?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(false),
                                        child: const Text('Vazgeç'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext).pop(true),
                                        child: const Text('Evet'),
                                      ),
                                    ],
                                  );
                                },
                              ) ??
                              false;

                          if (!confirmed) return;

                          final result = await AsyncValue.guard(() async {
                            await supabaseClient
                                .from('customers')
                                .update({
                                  'is_active': !customer.isActive,
                                })
                                .eq('id', customer.id);
                          });

                          // Listeyi yenile
                          final _ = ref.refresh(
                            customersFutureProvider.future,
                          );

                          if (context.mounted) {
                            if (result.hasError) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Durum güncellenemedi: ${AppException.messageOf(result.error!)}',
                                  ),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    makePassive
                                        ? 'Cari pasife alındı.'
                                        : 'Cari yeniden aktifleştirildi.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool? _mapChipsToIsActive(Set<_CustomerFilterChip> chips) {
  final activeSelected = chips.contains(_CustomerFilterChip.active);
  final passiveSelected = chips.contains(_CustomerFilterChip.passive);

  if (activeSelected && !passiveSelected) {
    return true;
  }
  if (!activeSelected && passiveSelected) {
    return false;
  }
  return null;
}

class _CustomerSummaryStats {
  const _CustomerSummaryStats({
    required this.total,
    required this.debtorCount,
    required this.riskyCount,
    required this.totalDebt,
  });

  final int total;
  final int debtorCount;
  final int riskyCount;
  final double totalDebt;
}

_CustomerSummaryStats _buildSummary(List<Customer> customers) {
  var debtorCount = 0;
  var riskyCount = 0;
  var totalDebt = 0.0;

  for (final customer in customers) {
    final balance = _computeNetBalance(customer);
    if (balance > 0) {
      debtorCount++;
      totalDebt += balance;
    }

    if (_isRiskyCustomer(customer, balance)) {
      riskyCount++;
    }
  }

  return _CustomerSummaryStats(
    total: customers.length,
    debtorCount: debtorCount,
    riskyCount: riskyCount,
    totalDebt: totalDebt,
  );
}

List<Customer> _applyLocalFilters(
  List<Customer> customers,
  Set<_CustomerFilterChip> chips,
) {
  Iterable<Customer> result = customers;

  final hasDebtor = chips.contains(_CustomerFilterChip.debtor);
  final hasCreditor = chips.contains(_CustomerFilterChip.creditor);
  final hasRisky = chips.contains(_CustomerFilterChip.risky);

  if (hasDebtor || hasCreditor) {
    result = result.where((customer) {
      final balance = _computeNetBalance(customer);
      final isDebtor = balance > 0;
      final isCreditor = balance < 0;

      if (hasDebtor && hasCreditor) {
        return isDebtor || isCreditor;
      } else if (hasDebtor) {
        return isDebtor;
      } else {
        return isCreditor;
      }
    });
  }

  if (hasRisky) {
    result = result.where((customer) {
      final balance = _computeNetBalance(customer);
      return _isRiskyCustomer(customer, balance);
    });
  }

  return result.toList();
}

double _computeNetBalance(Customer customer) {
  // Şimdilik açılış bakiyesi üzerinden yaklaşık net bakiye hesabı.
  return customer.openingBalance ?? 0;
}

bool _isRiskyCustomer(Customer customer, double balance) {
  final limit = customer.limitAmount ?? 0;
  if (limit <= 0) return false;

  final used = balance.abs();
  final ratio = used / limit;
  return ratio >= 0.8;
}

class _CustomerSummaryHeader extends StatelessWidget {
  const _CustomerSummaryHeader({required this.stats});

  final _CustomerSummaryStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.s8,
          horizontal: AppSpacing.s12,
        ),
        child: Wrap(
          spacing: AppSpacing.s12,
          runSpacing: AppSpacing.s4,
          children: [
            _SummaryItem(
              label: 'Toplam Cari',
              value: stats.total.toString(),
            ),
            _SummaryItem(
              label: 'Borçlu',
              value: stats.debtorCount.toString(),
            ),
            _SummaryItem(
              label: 'Riskli',
              value: stats.riskyCount.toString(),
            ),
            _SummaryItem(
              label: 'Toplam Borç',
              value: _formatAmount(stats.totalDebt),
              isEmphasized: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.isEmphasized = false,
  });

  final String label;
  final String value;
  final bool isEmphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          value,
          style: (isEmphasized
                  ? textTheme.titleSmall
                  : textTheme.bodyMedium)
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _FilterChipToggle extends StatelessWidget {
  const _FilterChipToggle({
    required this.label,
    required this.chip,
    required this.chips,
    required this.onChanged,
  });

  final String label;
  final _CustomerFilterChip chip;
  final Set<_CustomerFilterChip> chips;
  final ValueChanged<Set<_CustomerFilterChip>> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = chips.contains(chip);

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        final next = Set<_CustomerFilterChip>.from(chips);
        if (selected) {
          next.remove(chip);
        } else {
          next.add(chip);
        }
        onChanged(next);
      },
    );
  }
}

enum _CustomerRowAction { detail, toggleActive }

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.onTap,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Customer customer;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final name = customer.displayName;
    final phone = (customer.phone ?? '').trim();
    final subtitle = '${customer.code} · ${phone.isEmpty ? '-' : phone}';

    final balance = _computeNetBalance(customer);
    final balanceText = _formatAmount(balance.abs());

    final statusChip = customer.isActive
        ? const AppStatusChip.active()
        : const AppStatusChip.inactive();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.s4,
            horizontal: AppSpacing.s4,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              final menu = PopupMenuButton<_CustomerRowAction>(
                icon: const Icon(Icons.more_vert),
                onSelected: (action) {
                  switch (action) {
                    case _CustomerRowAction.detail:
                      onTap();
                      break;
                    case _CustomerRowAction.toggleActive:
                      onToggleActive();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem<_CustomerRowAction>(
                    value: _CustomerRowAction.detail,
                    child: Text('Detay'),
                  ),
                  PopupMenuItem<_CustomerRowAction>(
                    value: _CustomerRowAction.toggleActive,
                    child: Text(
                      customer.isActive ? 'Sil (pasife al)' : 'Aktif Yap',
                    ),
                  ),
                ],
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            statusChip,
                            const SizedBox(height: AppSpacing.s4),
                            menu,
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Row(
                      children: [
                        _BalanceText(balance: balance, text: balanceText),
                        const Spacer(),
                        Text(
                          _formatRelativeDateTime(customer.createdAt),
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.s8),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s16),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _BalanceText(balance: balance, text: balanceText),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _formatRelativeDateTime(customer.createdAt),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    flex: 1,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: statusChip,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  menu,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BalanceText extends StatelessWidget {
  const _BalanceText({required this.balance, required this.text});

  final double balance;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color color;
    if (balance > 0) {
      color = colorScheme.error;
    } else if (balance < 0) {
      color = Colors.green.shade700;
    } else {
      color = colorScheme.outline;
    }

    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _formatRelativeDateTime(DateTime? dateTime) {
  if (dateTime == null) return '—';

  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inDays <= 0) {
    return 'Bugün';
  }
  if (difference.inDays == 1) {
    return '1 gün önce';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays} gün önce';
  }
  if (difference.inDays < 30) {
    final weeks = (difference.inDays / 7).floor();
    return '$weeks hafta önce';
  }
  if (difference.inDays < 365) {
    final months = (difference.inDays / 30).floor();
    return '$months ay önce';
  }
  return '1+ yıl önce';
}

class _CustomerEmptyState extends StatelessWidget {
  const _CustomerEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.people_outline,
              size: 64,
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Henüz cari bulunmuyor.',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Yeni cari ekleyerek başlayabilirsin.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s16),
            PrimaryButton(
              label: 'Yeni Cari Ekle',
              icon: Icons.person_add,
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}
