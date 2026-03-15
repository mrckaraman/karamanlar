import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/formatters_tr.dart';
import 'customer_home_page.dart';
import 'dashboard_summary.dart';

class CustomerDashboardPage extends ConsumerWidget {
  const CustomerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerId = ref.watch(customerIdProvider);
    if (customerId == null || customerId.isEmpty) {
      return AppScaffold(
        title: 'Genel Bakış',
        body: const Center(
          child: Text('CustomerId yok. Lütfen tekrar giriş yapın.'),
        ),
      );
    }

    final currentCustomerAsync = ref.watch(currentCustomerProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final recentOrdersAsync = ref.watch(_dashboardRecentOrdersProvider);

    return AppScaffold(
      titleWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/Karamanlar_Ticaret_Uygulama.png',
            width: 24,
            height: 24,
          ),
          const SizedBox(width: 8),
          const Text('Genel Bakış'),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GreetingHeader(currentCustomerAsync: currentCustomerAsync),
            const SizedBox(height: 16),
            _SummaryRow(summaryAsync: summaryAsync),
            const SizedBox(height: 24),
            const _DashboardMenuGrid(),
            const SizedBox(height: 24),
            _RecentOrdersSection(recentOrdersAsync: recentOrdersAsync),
          ],
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader({required this.currentCustomerAsync});

  final AsyncValue<Customer?> currentCustomerAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return currentCustomerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (customer) {
        if (customer == null) return const SizedBox.shrink();

        final trade = customer.tradeTitle?.trim();
        final fullName = customer.fullName?.trim();
        final name = (trade != null && trade.isNotEmpty)
            ? trade
            : (fullName != null && fullName.isNotEmpty)
                ? fullName
                : null;

        if (name == null) return const SizedBox.shrink();

        return Text(
          'Hoş geldin $name',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summaryAsync});

  final AsyncValue<DashboardSummary> summaryAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (summaryAsync.isLoading && !summaryAsync.hasError) {
      return const Center(child: CircularProgressIndicator());
    }

    if (summaryAsync.hasError) {
      return Text(
        'Özet yüklenemedi: ${summaryAsync.error}',
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
      );
    }

    final DashboardSummary data = summaryAsync.value ?? DashboardSummary.empty;
    final balanceText = formatMoney(data.balance);
    final DateTime? lastOrderDate = data.lastOrderDate;
    final lastOrderText = lastOrderDate != null
        ? formatDate(lastOrderDate)
        : 'Henüz sipariş yok';

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryChip(
          label: 'Bakiye',
          value: balanceText,
          icon: Icons.account_balance_wallet_outlined,
        ),
        _SummaryChip(
          label: 'Son sipariş tarihi',
          value: lastOrderText,
          icon: Icons.receipt_long_outlined,
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardOrderEntry {
  const _DashboardOrderEntry({
    required this.id,
    required this.createdAt,
    required this.totalAmount,
  });

  final String id;
  final DateTime createdAt;
  final double totalAmount;

  factory _DashboardOrderEntry.fromMap(Map<String, dynamic> map) {
    final createdRaw = map['created_at'];
    DateTime createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.parse(createdRaw);
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    } else {
      createdAt = DateTime.now();
    }

    return _DashboardOrderEntry(
      id: map['id'] as String,
      createdAt: createdAt,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

final _dashboardRecentOrdersProvider =
    FutureProvider.autoDispose<List<_DashboardOrderEntry>>((ref) async {
  final client = supabaseClient;
  final customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    return <_DashboardOrderEntry>[];
  }

  final data = await client
      .from('orders')
      .select('id, created_at, total_amount')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false)
      .limit(5);

  return (data as List<dynamic>)
      .map((row) => _DashboardOrderEntry.fromMap(
            Map<String, dynamic>.from(row as Map),
          ))
      .toList(growable: false);
});

class _RecentOrdersSection extends ConsumerWidget {
  const _RecentOrdersSection({required this.recentOrdersAsync});

  final AsyncValue<List<_DashboardOrderEntry>> recentOrdersAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Son Siparişler',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        recentOrdersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text(
            'Son siparişler yüklenemedi: $error',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return const Text('Henüz siparişiniz yok.');
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(height: 8),
              itemBuilder: (context, index) {
                final order = orders[index];
                final dateText = formatDate(order.createdAt);
                final amountText = formatMoney(order.totalAmount);

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(dateText),
                  subtitle: Text('Tutar: $amountText'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/orders/${order.id}'),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _DashboardMenuGrid extends StatelessWidget {
  const _DashboardMenuGrid();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        _MenuTile(
          icon: Icons.add_shopping_cart_outlined,
          label: 'Yeni Sipariş',
          helper: 'Hızlıca yeni sipariş oluşturun',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/orders/new'),
        ),
        _MenuTile(
          icon: Icons.list_alt_outlined,
          label: 'Siparişlerim',
          helper: 'Geçmiş siparişlerinizi görüntüleyin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/orders'),
        ),
        _MenuTile(
          icon: Icons.inventory_2_outlined,
          label: 'Ürünler',
          helper: 'Stoktaki ürünleri inceleyin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/home/products'),
        ),
        _MenuTile(
          icon: Icons.receipt_long_outlined,
          label: 'Faturalarım',
          helper: 'Oluşturulan faturalarınızı görüntüleyin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/invoices'),
        ),
        _MenuTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Cari / Ekstre',
          helper: 'Cari hareketlerinizi ve bakiyenizi takip edin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/cari'),
        ),
        _MenuTile(
          icon: Icons.person_outline,
          label: 'Bilgilerim',
          helper: 'Hesap ve giriş bilgilerinizi yönetin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/account'),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.helper,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String helper;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell
      (
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  helper,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.color
                            ?.withValues(alpha: 0.8),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
