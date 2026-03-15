import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import 'orders_realtime_provider.dart';

class _CustomerOrderEntry {
  const _CustomerOrderEntry({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.totalAmount,
  });

  final String id;
  final DateTime createdAt;
  final String status;
  final double totalAmount;

  factory _CustomerOrderEntry.fromMap(Map<String, dynamic> map) {
    return _CustomerOrderEntry(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      status: (map['status'] as String?) ?? '',
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
    );
  }
}

final customerOrdersProvider =
    FutureProvider.autoDispose<List<_CustomerOrderEntry>>((ref) async {
  final client = supabaseClient;
  final customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    // Oturum / müşteri eşleşmesi yoksa sipariş listesi boş kabul edilir.
    return <_CustomerOrderEntry>[];
  }

  final data = await client
      .from('orders')
      .select('id, created_at, status, total_amount')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false);

  return (data as List<dynamic>)
      .map((e) => _CustomerOrderEntry.fromMap(
            Map<String, dynamic>.from(e as Map),
          ))
      .toList();
});

class CustomerOrdersPage extends ConsumerWidget {
  const CustomerOrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mevcut müşteri için realtime aboneliği aktif et.
    ref.watch(customerOrdersRealtimeProvider);

    // Her UPDATE event'inde sipariş listesini yeniden çek.
    ref.listen<String?>(
      customerOrdersRealtimeLastOrderIdProvider,
      (previous, next) {
        if (next == null || next.isEmpty) {
          return;
        }
        ref.invalidate(customerOrdersProvider);
      },
    );

    final ordersAsync = ref.watch(customerOrdersProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Siparişlerim',
      body: ordersAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Siparişler yüklenemedi: $e',
          onRetry: () => ref.invalidate(customerOrdersProvider),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return AppEmptyState(
              title: 'Henüz siparişiniz yok',
              subtitle: 'Yeni sipariş oluşturduğunuzda burada listelenecek.',
              icon: Icons.shopping_bag_outlined,
              action: FilledButton.icon(
                onPressed: () => context.go('/orders/new'),
                icon: const Icon(Icons.add_shopping_cart_outlined),
                label: const Text('Yeni sipariş oluştur'),
              ),
            );
          }

          final totalAmount = orders.fold<double>(
            0,
            (sum, e) => sum + e.totalAmount,
          );

          final now = DateTime.now();
          final Map<String, List<_CustomerOrderEntry>> grouped =
              <String, List<_CustomerOrderEntry>>{};

          for (final order in orders) {
            final key = _groupKeyForDate(now, order.createdAt);
            grouped.putIfAbsent(key, () => <_CustomerOrderEntry>[]).add(order);
          }

          const List<String> orderedGroups = <String>[
            'today',
            'yesterday',
            'thisWeek',
            'thisMonth',
            'older',
          ];

          final List<String> groupKeys = orderedGroups
              .where((g) => grouped.containsKey(g))
              .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Toplam',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            '${orders.length} sipariş',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Toplam Tutar',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            _formatAmount(totalAmount),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Expanded(
                child: ListView.separated(
                  itemCount: groupKeys.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.s12),
                  itemBuilder: (context, index) {
                    final key = groupKeys[index];
                    final groupOrders = grouped[key] ??
                        <_CustomerOrderEntry>[];
                    if (groupOrders.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    final groupTotal = groupOrders.fold<double>(
                      0,
                      (sum, e) => sum + e.totalAmount,
                    );

                    final String title = _groupTitle(key);
                    final String subtitle =
                        '${groupOrders.length} sipariş • ${_formatAmount(groupTotal)}';

                    final List<Widget> children = <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style:
                                  theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                    ];

                    for (final order in groupOrders) {
                      children.add(
                        _CustomerOrderCard(
                          order: order,
                        ),
                      );
                      children.add(
                        const SizedBox(height: AppSpacing.s4),
                      );
                    }

                    // Son elemandan sonra ekstra boşluk olmasın.
                    if (children.isNotEmpty &&
                        children.last is SizedBox) {
                      children.removeLast();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CustomerOrderCard extends StatelessWidget {
  const _CustomerOrderCard({
    required this.order,
  });

  final _CustomerOrderEntry order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _formatDate(order.createdAt);
    final idShort = _shortId(order.id);
    final totalText = _formatAmount(order.totalAmount);

    const borderRadius = BorderRadius.all(Radius.circular(12));

    return Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: borderRadius),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () {
            context.go('/orders/${order.id}');
          },
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              'Sipariş #$idShort',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          _buildStatusChip(order.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        dateText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      totalText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
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

String _shortId(String id) {
  if (id.length <= 8) return id;
  return id.substring(0, 8);
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _formatDate(DateTime date) {
  return formatDate(date);
}

Widget _buildStatusChip(String status) {
  final s = status.trim().toLowerCase();

  if (s.isEmpty) {
    return const AppStatusChip.inactive();
  }

  switch (s) {
    case 'cancelled':
      return const AppStatusChip.inactive();
    case 'completed':
    case 'approved':
    case 'preparing':
    case 'shipped':
    case 'new':
    default:
      return const AppStatusChip.active();
  }
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _groupKeyForDate(DateTime now, DateTime createdAt) {
  if (_isSameDay(createdAt, now)) {
    return 'today';
  }

  final yesterday = now.subtract(const Duration(days: 1));
  if (_isSameDay(createdAt, yesterday)) {
    return 'yesterday';
  }

  final weekAgo = now.subtract(const Duration(days: 7));
  final isThisWeek =
      (createdAt.isAfter(weekAgo) || _isSameDay(createdAt, weekAgo)) &&
          !(_isSameDay(createdAt, now) || _isSameDay(createdAt, yesterday));
  if (isThisWeek) {
    return 'thisWeek';
  }

  final isThisMonth =
      createdAt.year == now.year && createdAt.month == now.month;
  if (isThisMonth) {
    return 'thisMonth';
  }

  return 'older';
}

String _groupTitle(String key) {
  String label;
  switch (key) {
    case 'today':
      label = 'Bugün';
      break;
    case 'yesterday':
      label = 'Dün';
      break;
    case 'thisWeek':
      label = 'Bu Hafta';
      break;
    case 'thisMonth':
      label = 'Bu Ay';
      break;
    case 'older':
    default:
      label = 'Daha Eski';
      break;
  }
  return label;
}
