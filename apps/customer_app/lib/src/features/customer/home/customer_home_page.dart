import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/formatters_tr.dart';
import '../../../crashlytics/crashlytics.dart';
import '../../../../core/crashlytics/crash_logger.dart';
import 'customer_dashboard_repository.dart';
import 'dashboard_summary.dart';

const bool crashTestEnabled =
  bool.fromEnvironment('CRASH_TEST_ENABLED');

final dashboardSummaryProvider =
    FutureProvider.autoDispose<DashboardSummary>((ref) async {
  final String? customerId = ref.watch(customerIdProvider);
  if (customerId == null || customerId.isEmpty) {
    return DashboardSummary.empty;
  }
  return customerDashboardRepository.fetchSummary(customerId: customerId);
});

/// AuthState -> customerIdProvider -> currentCustomerProvider zinciri
/// üzerinden, oturum açmış kullanıcının bağlı olduğu cari kaydı yükler.
final currentCustomerProvider =
    FutureProvider.autoDispose<Customer?>((ref) async {
  final String? customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    return null;
  }

  return customerRepository.fetchCustomerById(customerId);
});

final customerDebugBannerProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final String? customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    return 'DEBUG: customerId missing';
  }

  final client = supabaseClient;

  try {
    final dynamic customerRow = await client
        .from('customers')
        .select('trade_title')
        .eq('id', customerId)
        .maybeSingle();

    final dynamic detailsRow = await client
        .from('customer_details')
        .select('price_tier')
        .eq('customer_id', customerId)
        .maybeSingle();

    final Map<String, dynamic>? customerMap =
        customerRow as Map<String, dynamic>?;
    final Map<String, dynamic>? detailsMap =
        detailsRow as Map<String, dynamic>?;

    final String? tradeTitle = customerMap?['trade_title'] as String?;
    final int? priceTier = detailsMap?['price_tier'] as int?;

    if (tradeTitle == null || tradeTitle.isEmpty || priceTier == null) {
      return 'DEBUG: customerId missing';
    }

    return 'DEBUG: $tradeTitle | $customerId | tier=$priceTier';
  } catch (_) {
    return 'DEBUG: customerId missing';
  }
});

class CustomerHomePage extends ConsumerWidget {
  const CustomerHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    CrashLogger.logScreen('customer_home');

    // Müşteri kimliği henüz çözülmediyse, daha fazla sorgu yapmadan
    // kullanıcıya net bir durum göster.
    final customerId = ref.watch(customerIdProvider);
    if (customerId == null || customerId.isEmpty) {
      return AppScaffold(
        title: 'Genel Bakış',
        body: const Center(
          child: Text('CustomerId yok. Lütfen tekrar giriş yapın.'),
        ),
      );
    }

    final summaryAsync = ref.watch(dashboardSummaryProvider);
    final debugBannerAsync = ref.watch(customerDebugBannerProvider);

    return AppScaffold(
      title: 'Genel Bakış',
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/orders/new'),
        child: const Icon(Icons.add_shopping_cart_outlined),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeHeaderWidget(),
            const SizedBox(height: AppSpacing.s16),
            _DebugBanner(bannerAsync: debugBannerAsync),
            if ((kDebugMode || crashTestEnabled) && !kIsWeb) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s16,
                ),
                child: ElevatedButton(
                  onPressed: testCrash,
                  child: const Text('Crash Test'),
                ),
              ),
              const SizedBox(height: AppSpacing.s12),
            ],
            _SummaryCards(summaryAsync: summaryAsync),
            const SizedBox(height: AppSpacing.s20),
            _BalanceInsightCard(summaryAsync: summaryAsync),
            const SizedBox(height: AppSpacing.s20),
            _RecentActivityCard(summaryAsync: summaryAsync),
            const SizedBox(height: AppSpacing.s24),
            const _MenuGrid(),
          ],
        ),
      ),
    );
  }
}

class HomeHeaderWidget extends ConsumerWidget {
  const HomeHeaderWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCustomerAsync = ref.watch(currentCustomerProvider);

    return currentCustomerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (customer) {
        if (customer == null) {
          return const SizedBox.shrink();
        }

        final greeting = _buildGreeting(customer);
        if (greeting == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final primary = theme.colorScheme.primary;
        final textColor = primary.withValues(alpha: 0.8);
        final backgroundColor = primary.withValues(alpha: 0.04);
        final size = MediaQuery.of(context).size;
        final bool isWide = size.width >= 600;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 24 : 16,
            vertical: isWide ? 18 : 12,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: Text(
            greeting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        );
      },
    );
  }
}

String? _buildGreeting(Customer customer) {
  final trade = customer.tradeTitle?.trim();
  if (trade != null && trade.isNotEmpty) {
    return 'Sayın $trade';
  }

  final fullName = customer.fullName?.trim();
  if (fullName != null && fullName.isNotEmpty) {
    return 'Sayın $fullName';
  }

  // trade_name ve ad soyad yoksa karşılama metni göstermeyelim.
  return null;
}

class _DebugBanner extends StatelessWidget {
  const _DebugBanner({required this.bannerAsync});

  final AsyncValue<String?> bannerAsync;

  @override
  Widget build(BuildContext context) {
    return bannerAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (text) {
        if (text == null || text.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.amber.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summaryAsync});

  final AsyncValue<DashboardSummary> summaryAsync;

  @override
  Widget build(BuildContext context) {
    return summaryAsync.when(
      loading: () => _buildSkeleton(context),
      error: (error, _) => _buildError(context, error),
      data: (data) => _buildData(context, data),
    );
  }

  Widget _buildSkeleton(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(3, (index) {
        return _SummaryCardContainer(
          child: Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return _SummaryCardContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Özet bilgileri yüklenemedi',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '$error',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              return OutlinedButton.icon(
                onPressed: () {
                  final container = ProviderScope.containerOf(context);
                  container
                      .refresh(dashboardSummaryProvider.future);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Yenile'),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildData(BuildContext context, DashboardSummary data) {
    final router = GoRouter.of(context);

    final cards = <Widget>[
      _SummaryCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Cari bakiyeniz',
        value: _formatCurrency(data.balance),
        hint: 'Detay için cari / ekstreye gidin',
        onTap: () => router.go('/cari'),
      ),
      _SummaryCard(
        icon: Icons.inventory_2_outlined,
        title: 'Açık siparişler',
        value: '${data.openOrdersCount}',
        hint: 'Açık siparişlerinizi görüntüleyin',
        onTap: () => router.go('/orders'),
      ),
      _SummaryCard(
        icon: Icons.receipt_long_outlined,
        title: 'Son sipariş',
        value: data.lastOrderDate == null
            ? 'Henüz sipariş yok'
            : '${_formatDate(data.lastOrderDate!)} / '
              '${_formatCurrency(data.lastOrderTotal ?? 0)}',
        hint: data.lastOrderDate == null
            ? 'İlk siparişinizi oluşturun'
            : 'Tüm siparişlerinizi görün',
        onTap: () => router.go('/orders'),
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards
          .map((card) => _SummaryCardContainer(child: card))
          .toList(),
    );
  }

  String _formatCurrency(double value) {
  return formatMoney(value);
  }

  String _formatDate(DateTime d) {
  return formatDate(d);
  }
}

class _SummaryCardContainer extends StatelessWidget {
  const _SummaryCardContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
      child: child,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    this.hint,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isClickable = onTap != null;

    return MouseRegion(
      cursor: isClickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: Card(
        elevation: isClickable ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isClickable
                ? theme.colorScheme.primary.withValues(alpha: 0.25)
                : const Color(0xFFE5E7EB),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isClickable)
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (hint != null && hint!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    hint!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color
                          ?.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BalanceInsightCard extends StatelessWidget {
  const _BalanceInsightCard({required this.summaryAsync});

  final AsyncValue<DashboardSummary> summaryAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return summaryAsync.when(
      loading: () => const AppLoadingState(),
      error: (error, _) => AppErrorState(
        message: 'Özet grafiği yüklenemedi: $error',
      ),
      data: (data) {
        final balance = data.balance.abs();
        final lastTotal = (data.lastOrderTotal ?? 0).abs();
        final openOrders = data.openOrdersCount.toDouble();
        final maxValue = [balance, lastTotal, openOrders, 1].reduce(
          (a, b) => a > b ? a : b,
        );

        double ratio(double v) =>
            maxValue == 0 ? 0.1 : (v / maxValue).clamp(0.1, 1.0);

        final bars = [
          (ratio(balance), 'Bakiye'),
          (ratio(lastTotal), 'Son sipariş'),
          (ratio(openOrders), 'Açık sipariş'),
        ];

        return Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bütçe görünümü',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.s8),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (ratio, label) in bars)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: 100 * ratio,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                label,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.summaryAsync});

  final AsyncValue<DashboardSummary> summaryAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return summaryAsync.when(
      loading: () => const AppLoadingState(),
      error: (error, _) => AppErrorState(
        message: 'Son hareketler yüklenemedi: $error',
      ),
      data: (data) {
        return Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Son hareketler',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.s8),
                _ActivityRow(
                  label: 'Cari bakiye',
                  value: _formatCurrency(data.balance),
                ),
                const SizedBox(height: AppSpacing.s4),
                _ActivityRow(
                  label: 'Açık sipariş',
                  value: '${data.openOrdersCount} adet',
                ),
                const SizedBox(height: AppSpacing.s4),
                _ActivityRow(
                  label: 'Son sipariş',
                  value: data.lastOrderDate == null
                      ? 'Henüz sipariş yok'
                      : '${_formatDate(data.lastOrderDate!)} • '
                        '${_formatCurrency(data.lastOrderTotal ?? 0)}',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatCurrency(double value) {
	return formatMoney(value);
  }

  String _formatDate(DateTime d) {
	return formatDate(d);
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = AppResponsive.gridColumns(context, mobile: 1, tablet: 2, desktop: 3);
    final childAspectRatio = columns == 1 ? 3.1 : 1.05;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: childAspectRatio,
      children: [
        _MenuCard(
          icon: Icons.inventory_2_outlined,
          label: 'Ürünler',
          helper: 'Stoktaki ürünleri inceleyin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/home/products'),
        ),
        _MenuCard(
          icon: Icons.shopping_cart_outlined,
          label: 'Yeni Sipariş',
          helper: 'Hızlıca yeni sipariş oluşturun',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/orders/new'),
        ),
        _MenuCard(
          icon: Icons.receipt_long_outlined,
          label: 'Faturalarım',
          helper: 'Oluşturulan faturalarınızı görüntüleyin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/invoices'),
        ),
        _MenuCard(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Cari / Ekstre',
          helper: 'Cari hareketlerinizi ve bakiyenizi takip edin',
          color: theme.colorScheme.primary,
          onTap: () => context.go('/cari'),
        ),
            _MenuCard(
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

class _MenuCard extends StatelessWidget {
  const _MenuCard({
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.s4),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
