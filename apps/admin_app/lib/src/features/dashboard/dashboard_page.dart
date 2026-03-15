// ignore_for_file: prefer_const_constructors

import 'package:core/core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_layout.dart';
import '../../constants/ui_copy_tr.dart';
import '../../utils/formatters_tr.dart';
import '../customers/customer_finance_providers.dart' as customer_finance;
import 'widgets/metric_card.dart';
import 'widgets/orders_table.dart';
import 'widgets/quick_action_card.dart';
import 'dashboard_refresh_provider.dart';

class AdminMetrics {
  const AdminMetrics({
    required this.activeStockCount,
    required this.customerCount,
    required this.todaySalesCount,
    required this.openOrdersCount,
  });

  final int activeStockCount;
  final int customerCount;
  final int todaySalesCount;
  final int openOrdersCount;
}

final adminMetricsProvider = FutureProvider.autoDispose<AdminMetrics>((ref) async {
  final repo = core.adminMetricsRepository;

  final results = await Future.wait<int>([
    repo.getActiveStockCount(),
    repo.getCustomerCount(),
    repo.getTodaySalesCount(),
    repo.getOpenOrderCount(),
  ]);

  return AdminMetrics(
    activeStockCount: results[0],
    customerCount: results[1],
    todaySalesCount: results[2],
    openOrdersCount: results[3],
  );
});

final adminDashboardLastOrdersProvider =
    FutureProvider.autoDispose<List<core.AdminOrderListEntry>>((ref) async {
  final repo = core.adminOrderRepository;
  return repo.fetchOrders(
    status: 'all',
    limit: 5,
  );
});

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  String? _selectedOrderId;
  int? _lastRefreshTick;

  Future<void> _refreshAll() async {
    await Future.wait<void>([
      ref.refresh(adminMetricsProvider.future),
      ref.refresh(adminDashboardLastOrdersProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final refreshTick = ref.watch(dashboardRefreshTickProvider);
    if (_lastRefreshTick == null) {
      _lastRefreshTick = refreshTick;
    } else if (_lastRefreshTick != refreshTick) {
      _lastRefreshTick = refreshTick;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshAll();
      });
    }

    final metricsAsync = ref.watch(adminMetricsProvider);

    final scrollView = SingleChildScrollView(
      padding: AppLayout.screenPadding,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 24),
          metricsAsync.when(
            loading: () => const core.AppLoadingState(),
            error: (e, _) => core.AppErrorState(
              message: 'KPI yüklenemedi: $e',
              onRetry: () => ref.refresh(adminMetricsProvider.future),
            ),
            data: (metrics) => _OverviewMetrics(metrics: metrics),
          ),
          const SizedBox(height: 32),
          _buildQuickActionsSection(context),
          const SizedBox(height: 32),
          _buildLastOrdersSection(context),
        ],
      ),
    );

    final disablePullToRefresh = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (disablePullToRefresh) {
      return scrollView;
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: scrollView,
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final headerText = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Genel Bakış', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              UiCopyTr.dashboardOverviewSubtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        );

        final filters = Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: isNarrow ? WrapAlignment.start : WrapAlignment.end,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                  ),
                  hintText: 'Tarih aralığı',
                ),
                readOnly: true,
                onTap: () {
                  // İleride tarih seçici entegre edilebilir.
                },
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.filter_list, size: 18),
              label: const Text('Filtreler'),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headerText,
              const SizedBox(height: 12),
              filters,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: headerText),
            const SizedBox(width: 16),
            Flexible(
              child: Align(
                alignment: Alignment.topRight,
                child: filters,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hızlı İşlemler',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 700 ? 4 : 2;
            final totalSpacing = 16.0 * (crossAxisCount - 1);
            final cardWidth =
                (constraints.maxWidth - totalSpacing) / crossAxisCount;

            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: QuickActionCard(
                    icon: Icons.people_outline,
                    title: 'Cari / Müşteri Yönetimi',
                    description: 'Müşteriler ve cari işlemler',
                    onTap: () => context.goNamed('customerManagement'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: QuickActionCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'Stok Yönetimi',
                    description: 'Stok giriş/çıkış ve sayım işlemleri',
                    onTap: () => context.goNamed('stocks'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: QuickActionCard(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Sipariş Yönetimi',
                    description: UiCopyTr.dashboardOrdersSubtitle,
                    onTap: () => context.goNamed(
                      'orders',
                      queryParameters: {'status': 'new'},
                    ),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: QuickActionCard(
                    icon: Icons.add_shopping_cart_outlined,
                    title: 'Yeni Sipariş',
                    description: 'Müşteri seç ve sipariş oluştur',
                    onTap: () => context.push('/orders/new'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: QuickActionCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'Fatura',
                    description: UiCopyTr.dashboardInvoicesSubtitle,
                    onTap: () => context.goNamed('invoices'),
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: QuickActionCard(
                    icon: Icons.assignment_return_outlined,
                    title: 'İade',
                    description: 'Elle iade kaydı oluştur',
                    onTap: () => context.push('/returns/new'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildLastOrdersSection(BuildContext context) {
    final theme = Theme.of(context);
    final lastOrdersAsync = ref.watch(adminDashboardLastOrdersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Son Siparişler',
              style: theme.textTheme.titleMedium,
            ),
            TextButton(
              onPressed: () => context.goNamed('orders'),
              child: const Text('Tümünü Gör'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        lastOrdersAsync.when(
          loading: () => const core.AppLoadingState(),
          error: (e, _) => core.AppErrorState(
            message: 'Son siparişler yüklenemedi: $e',
            onRetry: () => ref.invalidate(adminDashboardLastOrdersProvider),
          ),
          data: (orders) {
            if (orders.isEmpty) {
              return const core.AppEmptyState(
                title: 'Henüz sipariş yok',
                subtitle:
                    'Yeni siparişler oluşturulduğunda burada listelenecek.',
              );
            }

            return OrdersTable(
              orders: orders,
              selectedOrderId: _selectedOrderId,
              onRowSelected: (id) {
                setState(() {
                  _selectedOrderId = _selectedOrderId == id ? null : id;
                });
              },
            );
          },
        ),
      ],
    );
  }
}

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({required this.metrics});

  final AdminMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount;
        if (constraints.maxWidth >= 900) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 700) {
          crossAxisCount = 3;
        } else {
          crossAxisCount = 2;
        }

        final totalSpacing = 16.0 * (crossAxisCount - 1);
        final cardWidth =
            (constraints.maxWidth - totalSpacing) / crossAxisCount;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                label: 'Aktif Stok',
                value: metrics.activeStockCount.toString(),
                description: 'Sistemde tanımlı aktif stok',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                label: 'Toplam Müşteri',
                value: metrics.customerCount.toString(),
                description: 'Toplam cari/müşteri sayısı',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                label: 'Bugünkü Satış',
                value: metrics.todaySalesCount.toString(),
                description: 'Bugün oluşturulan satış adedi',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: MetricCard(
                label: 'Açık Sipariş',
                value: metrics.openOrdersCount.toString(),
                description: 'Durumu açık olan siparişler',
              ),
            ),
          ],
        );
      },
    );
  }
}

@Deprecated('Use /returns/new (ReturnCreatePage) instead.')
class _QuickRefundSheet extends ConsumerStatefulWidget {
  const _QuickRefundSheet();

  @override
  ConsumerState<_QuickRefundSheet> createState() => _QuickRefundSheetState();
}

@Deprecated('Use /returns/new (ReturnCreatePage) instead.')
class _QuickRefundSheetState extends ConsumerState<_QuickRefundSheet> {
  core.Customer? _selectedCustomer;
  String? _selectedGroupName;
  core.CustomerProduct? _selectedProduct;

  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _unitPriceController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _saving = false;
  String _selectedUnit = 'Adet';

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

  bool get _isValidForm {
    if (_selectedProduct == null) return false;
    if (_quantity <= 0) return false;
    if (_unitPrice < 0) return false;
    return true;
  }

  bool get _canSubmit =>
      !_saving && _isValidForm && _selectedCustomer != null;

  String _formatGroupLabel(String groupName) {
    if (groupName == core.CustomerProductRepository.ungroupedGroupName) {
      return 'Grupsuz';
    }
    return groupName;
  }

  void _applyProductToForm(core.CustomerProduct product) {
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

  Future<void> _save() async {
    if (!_canSubmit) return;

    final customer = _selectedCustomer;
    if (customer == null) return;

    final repo = ref.read(customer_finance.manualRefundRepositoryProvider);
    final unit = _selectedUnit;
    final note = () {
      final value = _noteController.text.trim();
      return value.isEmpty ? null : value;
    }();

    setState(() => _saving = true);
    try {
      await repo.createManualRefund(
        customerId: customer.id,
        quantity: _quantity,
        unit: unit,
        unitPrice: _unitPrice,
        note: note,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İade kaydedildi.')),
      );
      Navigator.of(context).pop(customer.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İade kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customersAsync = ref.watch(_quickRefundCustomersProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppLayout.screenPadding.left,
          right: AppLayout.screenPadding.right,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                  const SizedBox(height: 8),
                  Text(
                    'Önce müşteri seçin, ardından elle iade tutarını girin.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  core.AppSearchField(
                    hintText: 'Ünvan / kod / telefon / vergi no ara',
                    padded: false,
                    onChanged: (value) => ref
                        .read(_quickRefundCustomerSearchProvider.notifier)
                        .state =
                    value,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: customersAsync.when(
                      loading: () => const core.AppLoadingState(),
                      error: (e, _) => core.AppErrorState(
                        message: 'Müşteri listesi yüklenemedi: $e',
                        onRetry: () => ref
                            .refresh(_quickRefundCustomersProvider.future),
                      ),
                      data: (customers) {
                        if (customers.isEmpty) {
                          return const core.AppEmptyState(
                            title: 'Müşteri bulunamadı',
                            subtitle:
                                'Arama kriterlerine uygun müşteri kaydı yok.',
                          );
                        }

                        return ListView.separated(
                          itemCount: customers.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            final isSelected =
                                _selectedCustomer?.id == customer.id;

                            return ListTile(
                              title: Text(customer.displayName),
                              subtitle: Text(
                                              customer.code,
                              ),
                              dense: true,
                              selected: isSelected,
                              onTap: () {
                                setState(() {
                                  _selectedCustomer = customer;
                                    _selectedGroupName = null;
                                    _selectedProduct = null;
                                  _quantityController.clear();
                                  _unitPriceController.clear();
                                  _selectedUnit = 'Adet';
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedCustomer != null) ...[
                    Text(
                      'Seçilen müşteri:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedCustomer!.displayName,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ürün seçimi:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Devam etmek için önce bir ürün seçin.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ref
                        .watch(
                          _refundGroupNamesProvider(_selectedCustomer!.id),
                        )
                        .when(
                          loading: () => const core.AppLoadingState(),
                          error: (e, _) => core.AppErrorState(
                            message: 'Ürün grupları yüklenemedi: $e',
                            onRetry: () => ref.refresh(
                              _refundGroupNamesProvider(
                                _selectedCustomer!.id,
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
                                    'refund-group-${_selectedCustomer!.id}-${_selectedGroupName ?? ''}',
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
                                const SizedBox(height: 8),
                                if (_selectedProduct != null) ...[
                                  Text(
                                    'Seçili ürün: ${_selectedProduct!.name}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                SizedBox(
                                  height: 220,
                                  child: ref
                                      .watch(
                                        _refundProductsProvider(
                                          _RefundProductsQuery(
                                            customerId:
                                                _selectedCustomer!.id,
                                            groupName: _selectedGroupName,
                                          ),
                                        ),
                                      )
                                      .when(
                                        loading: () =>
                                            const core.AppLoadingState(),
                                        error: (e, _) => core.AppErrorState(
                                          message:
                                              'Ürünler yüklenemedi: $e',
                                          onRetry: () => ref.refresh(
                                            _refundProductsProvider(
                                              _RefundProductsQuery(
                                                customerId:
                                                    _selectedCustomer!.id,
                                                groupName: _selectedGroupName,
                                              ),
                                            ).future,
                                          ),
                                        ),
                                        data: (products) {
                                          if (products.isEmpty) {
                                            return const core.AppEmptyState(
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
                                                  style: theme
                                                      .textTheme.bodySmall,
                                                ),
                                                onTap: () =>
                                                    _applyProductToForm(
                                                  product,
                                                ),
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
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText: 'Miktar',
                      hintText: _selectedProduct == null
                          ? 'Önce ürün seçin'
                          : null,
                    ),
                    enabled: _selectedProduct != null,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: _unitPriceController,
                    decoration: InputDecoration(
                      labelText: 'Birim Fiyat',
                      hintText: _selectedProduct == null
                          ? 'Önce ürün seçin'
                          : null,
                    ),
                    enabled: _selectedProduct != null,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Tutar (otomatik)',
                      hintText: formatMoney(_total),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Not (opsiyonel)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  core.PrimaryButton(
                    label: _saving ? 'Kaydediliyor...' : 'Kaydet',
                    expand: true,
                    onPressed: _canSubmit ? _save : null,
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

final _quickRefundCustomerSearchProvider =
    StateProvider.autoDispose<String>((ref) => '');

final _quickRefundCustomersProvider =
    FutureProvider.autoDispose<List<core.Customer>>((ref) async {
  final search = ref.watch(_quickRefundCustomerSearchProvider);
  return core.customerRepository.fetchCustomers(
    search: search.trim().isEmpty ? null : search.trim(),
    isActive: true,
    limit: 50,
  );
});

class _RefundProductsQuery {
  const _RefundProductsQuery({
    required this.customerId,
    required this.groupName,
  });

  final String customerId;
  final String? groupName;

  @override
  bool operator ==(Object other) {
    return other is _RefundProductsQuery &&
        other.customerId == customerId &&
        other.groupName == groupName;
  }

  @override
  int get hashCode => Object.hash(customerId, groupName);
}

final _refundGroupNamesProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, customerId) {
  return core.customerProductRepository.fetchGroupNames(customerId: customerId);
});

final _refundProductsProvider = FutureProvider.autoDispose
    .family<List<core.CustomerProduct>, _RefundProductsQuery>((ref, query) {
  return core.customerProductRepository.fetchProducts(
    customerId: query.customerId,
    page: 0,
    pageSize: 50,
    groupName: query.groupName,
  );
});
