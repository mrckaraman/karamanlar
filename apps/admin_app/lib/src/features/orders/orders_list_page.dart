import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crashlytics/crash_logger.dart';
import '../../utils/formatters_tr.dart';
import '../invoices/invoices_list_page.dart' show adminInvoicesReloadTokenProvider;
import '../stocks/stock_import_export_download_stub.dart'
  if (dart.library.html) '../stocks/stock_import_export_download_web.dart'
  as download_helper;
import 'widgets/order_status_chip.dart';
import 'services/order_export_service.dart';
import 'services/order_print_service.dart';

enum AdminOrderStageTab { newOrders, approved, preparing, shipped, cancelled }

extension AdminOrderStageTabX on AdminOrderStageTab {
  String get label {
    switch (this) {
      case AdminOrderStageTab.newOrders:
        return 'Yeni';
      case AdminOrderStageTab.approved:
        return 'Onaylı';
      case AdminOrderStageTab.preparing:
        return 'Hazırlanıyor';
      case AdminOrderStageTab.shipped:
        return 'Sevk edildi';
      case AdminOrderStageTab.cancelled:
        return 'İptal';
    }
  }

  List<String> get statuses {
    switch (this) {
      case AdminOrderStageTab.newOrders:
        return <String>['new'];
      case AdminOrderStageTab.approved:
        return <String>['approved'];
      case AdminOrderStageTab.preparing:
        return <String>['preparing'];
      case AdminOrderStageTab.shipped:
        return <String>['shipped'];
      case AdminOrderStageTab.cancelled:
        return <String>['cancelled'];
    }
  }
}

enum AdminOrdersDateFilter { today, thisWeek, thisMonth, custom }

extension AdminOrdersDateFilterX on AdminOrdersDateFilter {
  String get label {
    switch (this) {
      case AdminOrdersDateFilter.today:
        return 'Bugün';
      case AdminOrdersDateFilter.thisWeek:
        return 'Bu hafta';
      case AdminOrdersDateFilter.thisMonth:
        return 'Bu ay';
      case AdminOrdersDateFilter.custom:
        return 'Özel';
    }
  }
}

enum AdminOrdersSortOption { newest, amountDesc, customerAz }

extension AdminOrdersSortOptionX on AdminOrdersSortOption {
  String get label {
    switch (this) {
      case AdminOrdersSortOption.newest:
        return 'En yeni';
      case AdminOrdersSortOption.amountDesc:
        return 'Tutar yüksek';
      case AdminOrdersSortOption.customerAz:
        return 'Müşteri A-Z';
    }
  }
}

final _adminOrdersStageProvider =
    StateProvider<AdminOrderStageTab>((ref) => AdminOrderStageTab.newOrders);

final _adminOrdersSearchProvider = StateProvider<String>((ref) => '');
final _adminOrdersDateFilterProvider =
  StateProvider<AdminOrdersDateFilter>((ref) => AdminOrdersDateFilter.today);
final _adminOrdersCustomDateRangeProvider =
  StateProvider<DateTimeRange?>((ref) => null);
final _adminOrdersMinTotalProvider =
  StateProvider<double?>((ref) => null);
final _adminOrdersMaxTotalProvider =
  StateProvider<double?>((ref) => null);
final _adminOrdersCustomerIdFilterProvider =
  StateProvider<String?>((ref) => null);
final _adminOrdersSortOptionProvider = StateProvider<AdminOrdersSortOption>(
  (ref) => AdminOrdersSortOption.newest,
);

class OrdersFilter {
  const OrdersFilter({
    this.startDate,
    this.endDate,
    this.customerId,
    this.minAmount,
    this.maxAmount,
    this.search,
    this.stage,
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? customerId;
  final double? minAmount;
  final double? maxAmount;
  final String? search;
  final String? stage;

  OrdersFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? customerId,
    double? minAmount,
    double? maxAmount,
    String? search,
    String? stage,
  }) {
    return OrdersFilter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      customerId: customerId ?? this.customerId,
      minAmount: minAmount ?? this.minAmount,
      maxAmount: maxAmount ?? this.maxAmount,
      search: search ?? this.search,
      stage: stage ?? this.stage,
    );
  }
}

@immutable
class OrderCounts {
  const OrderCounts({
    required this.newCount,
    required this.approvedCount,
    required this.preparingCount,
    required this.shippedCount,
    required this.cancelledCount,
  });

  final int newCount;
  final int approvedCount;
  final int preparingCount;
  final int shippedCount;
  final int cancelledCount;
}

final ordersFiltersProvider = Provider<OrdersFilter>((ref) {
  final currentStage = ref.watch(_adminOrdersStageProvider);
  final search = ref.watch(_adminOrdersSearchProvider);
  final dateFilter = ref.watch(_adminOrdersDateFilterProvider);
  final customRange = ref.watch(_adminOrdersCustomDateRangeProvider);
  final minTotal = ref.watch(_adminOrdersMinTotalProvider);
  final maxTotal = ref.watch(_adminOrdersMaxTotalProvider);
  final selectedCustomerId = ref.watch(_adminOrdersCustomerIdFilterProvider);

  DateTime? startDate;
  DateTime? endDate;

  DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  final now = DateTime.now();
  switch (dateFilter) {
    case AdminOrdersDateFilter.today:
      startDate = startOfDay(now);
      endDate = endOfDay(now);
      break;
    case AdminOrdersDateFilter.thisWeek:
      final start = now.subtract(Duration(days: now.weekday - 1));
      startDate = startOfDay(start);
      endDate = endOfDay(now);
      break;
    case AdminOrdersDateFilter.thisMonth:
      startDate = DateTime(now.year, now.month, 1);
      endDate = endOfDay(now);
      break;
    case AdminOrdersDateFilter.custom:
      if (customRange != null) {
        startDate = startOfDay(customRange.start);
        endDate = endOfDay(customRange.end);
      } else {
        startDate = null;
        endDate = null;
      }
      break;
  }

  final stageKey = currentStage.statuses.first;

  return OrdersFilter(
    startDate: startDate,
    endDate: endDate,
    customerId: selectedCustomerId,
    minAmount: minTotal,
    maxAmount: maxTotal,
    search: search.trim().isEmpty ? null : search.trim(),
    stage: stageKey,
  );
});

List<String>? _statusesForStage(String? stage) {
  switch (stage) {
    case 'new':
      return const <String>['new'];
    case 'approved':
      return const <String>['approved'];
    case 'preparing':
      return const <String>['preparing'];
    case 'shipped':
      return const <String>['shipped'];
    case 'cancelled':
      return const <String>['cancelled'];
    case 'all':
    case null:
      return null;
    default:
      return <String>[stage];
  }
}

final adminOrdersProvider = FutureProvider.autoDispose
    .family<List<AdminOrderListEntry>, OrdersFilter>((ref, filter) async {
  final statuses = _statusesForStage(filter.stage);
  final orders = await adminOrderRepository.fetchOrders(
    status: statuses == null ? 'all' : '',
    statuses: statuses,
  );

  final sortOption = ref.read(_adminOrdersSortOptionProvider);
  return _applyOrdersFilters(
    base: orders,
    filter: filter,
    sortOption: sortOption,
  );
});

final adminOrderCountsProvider = FutureProvider.autoDispose
    .family<OrderCounts, OrdersFilter>((ref, filter) async {
  // Stage hariç tüm filtreler uygulanmalı, bu yüzden stage'i yok sayıyoruz.
  final baseFilter = filter.copyWith(stage: 'all');

  final orders = await adminOrderRepository.fetchOrders(
    status: 'all',
  );

  final filtered = _applyOrdersFilters(
    base: orders,
    filter: baseFilter,
    sortOption: AdminOrdersSortOption.newest,
  );

  int countFor(String status) => filtered
      .where((o) => o.status.trim().toLowerCase() == status)
      .length;

  return OrderCounts(
    newCount: countFor('new'),
    approvedCount: countFor('approved'),
    preparingCount: countFor('preparing'),
    shippedCount: countFor('shipped'),
    cancelledCount: countFor('cancelled'),
  );
});

class OrdersListPage extends ConsumerStatefulWidget {
  const OrdersListPage({
    super.key,
    this.initialStatus,
    this.info,
  });

  final String? initialStatus;
  final String? info;

  @override
  ConsumerState<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends ConsumerState<OrdersListPage> {
  bool _showAll = false;
  bool _selectionMode = false;
  final Set<String> _selectedOrderIds = <String>{};
  String? _approvingOrderId;
  String? _lastOpenedOrderId;

  AsyncValue<void> _exportState = const AsyncData<void>(null);

  @override
  void initState() {
    super.initState();
    CrashLogger.logScreen('admin_orders_list');
    final initial = widget.initialStatus?.trim().toLowerCase();
    if (initial == null || initial.isEmpty) {
      return;
    }
    if (initial == 'all') {
      _showAll = true;
      return;
    }
    final stage = _stageFromStatus(initial);
    if (stage != null) {
      Future<void>.delayed(Duration.zero, () {
        if (!mounted) return;
        ref.read(_adminOrdersStageProvider.notifier).state = stage;
      });
    }
  }

  AdminOrderStageTab? _stageFromStatus(String status) {
    switch (status) {
      case 'new':
        return AdminOrderStageTab.newOrders;
      case 'approved':
        return AdminOrderStageTab.approved;
      case 'preparing':
        return AdminOrderStageTab.preparing;
      case 'shipped':
        return AdminOrderStageTab.shipped;
      case 'cancelled':
        return AdminOrderStageTab.cancelled;
      default:
        return null;
    }
  }

  void _toggleSelection(String orderId) {
    setState(() {
      if (_selectedOrderIds.contains(orderId)) {
        _selectedOrderIds.remove(orderId);
      } else {
        _selectedOrderIds.add(orderId);
      }
    });
  }

  Future<void> _openOrdersExportSheet({
    required BuildContext context,
    required List<AdminOrderListEntry> currentOrders,
    List<AdminOrderListEntry>? selectedOverride,
  }) async {
    if (_exportState.isLoading) return;

    final selectedOrders = selectedOverride ??
        (_selectionMode
            ? currentOrders
                .where((o) => _selectedOrderIds.contains(o.id))
                .toList(growable: false)
            : const <AdminOrderListEntry>[]);

    final effectiveOrders = selectedOrders.isNotEmpty
        ? selectedOrders
        : currentOrders;

    if (effectiveOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışa aktarılacak sipariş bulunamadı.')),
      );
      return;
    }

    final action = await showModalBottomSheet<_OrdersExportAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scopeLabel = selectedOrders.isNotEmpty
            ? 'Seçili siparişler (${selectedOrders.length})'
            : 'Tüm liste (${currentOrders.length})';

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(scopeLabel),
                subtitle: const Text('Yazdır, CSV (Excel) veya PDF dışa aktar.'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Yazdır'),
                onTap: () => Navigator.of(ctx).pop(_OrdersExportAction.print),
              ),
              ListTile(
                leading: const Icon(Icons.table_view_outlined),
                title: const Text('CSV (Excel)'),
                onTap: () => Navigator.of(ctx).pop(_OrdersExportAction.csv),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('PDF'),
                onTap: () => Navigator.of(ctx).pop(_OrdersExportAction.pdf),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (action == null) return;

    await _runExportAction(
      action: action,
      orders: effectiveOrders,
    );
  }

  Future<void> _runExportAction({
    required _OrdersExportAction action,
    required List<AdminOrderListEntry> orders,
  }) async {
    if (_exportState.isLoading) return;

    setState(() => _exportState = const AsyncLoading<void>());

    final service = OrderExportService(
      adminOrderRepository: adminOrderRepository,
    );

    final result = await AsyncValue.guard(() async {
      switch (action) {
        case _OrdersExportAction.csv:
          return service.buildCsv(orders: orders);
        case _OrdersExportAction.pdf:
        case _OrdersExportAction.print:
          return service.buildPdf(orders: orders);
      }
    });

    if (!mounted) return;
    setState(() => _exportState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dışa aktarma başarısız: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    final file = result.value as OrderExportFile;

    switch (action) {
      case _OrdersExportAction.csv:
        final ok = await download_helper.saveBytesFile(
          file.fileName,
          file.bytes,
          mimeType: file.mimeType,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'CSV hazırlandı.' : 'CSV kaydedilemedi/açılamadı.',
            ),
          ),
        );
        return;
      case _OrdersExportAction.pdf:
        final ok = await download_helper.saveBytesFile(
          file.fileName,
          file.bytes,
          mimeType: file.mimeType,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? 'PDF hazırlandı.' : 'PDF kaydedilemedi/açılamadı.',
            ),
          ),
        );
        return;
      case _OrdersExportAction.print:
        if (kIsWeb) {
          await Printing.layoutPdf(
            onLayout: (_) async => file.bytes,
          );
          return;
        }

        final x = XFile.fromData(
          file.bytes,
          name: file.fileName,
          mimeType: file.mimeType,
        );
        await Share.shareXFiles(
          <XFile>[x],
          text: 'Sipariş Listesi',
        );
        return;
    }
  }

  Future<void> _printFromList(BuildContext context) async {
    String? orderId;

    if (_selectionMode) {
      if (_selectedOrderIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen yazdırmak için bir sipariş seçin.'),
          ),
        );
        return;
      }

      if (_selectedOrderIds.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen yalnızca bir sipariş seçin.'),
          ),
        );
        return;
      }

      orderId = _selectedOrderIds.first;
    } else {
      orderId = _lastOpenedOrderId;
      if (orderId == null || orderId.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen yazdırmak için bir sipariş seçin.'),
          ),
        );
        return;
      }
    }

    try {
      final detail = await adminOrderRepository.fetchOrderDetail(orderId);
      await OrderPrintService.printOrder(detail);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Yazdırma başarısız: ${AppException.messageOf(e)}'),
        ),
      );
    }
  }

  Future<void> _approveOrder({
    required BuildContext context,
    required String orderId,
  }) async {
    try {
      await supabaseClient.rpc(
        'rpc_approve_order',
        params: <String, dynamic>{'p_order_id': orderId},
      );

              final filter = ref.read(ordersFiltersProvider);
              final effective =
                _showAll ? filter.copyWith(stage: 'all') : filter;
              await ref.read(adminOrdersProvider(effective).future);
              await ref.read(adminOrderCountsProvider(filter).future);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sipariş onaylandı'),
        ),
      );
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint(
          'approve failed: \\${e.code} \\${e.message} \\${e.details}',
        );
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Onay başarısız: \\${e.message}'),
        ),
      );
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('approve failed (unknown): ${AppException.messageOf(e)}');
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onay başarısız (beklenmeyen hata)'),
        ),
      );
      rethrow;
    }
  }

  Future<void> _updateOrderStatus({
    required BuildContext context,
    required AdminOrderListEntry order,
    required String newStatus,
  }) async {
    try {
      await adminOrderRepository.updateOrderStatus(
        orderId: order.id,
        status: newStatus,
      );

              final filter = ref.read(ordersFiltersProvider);
              final effective =
                _showAll ? filter.copyWith(stage: 'all') : filter;
              await ref.read(adminOrdersProvider(effective).future);
              await ref.read(adminOrderCountsProvider(filter).future);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sipariş durumu güncellenemedi: ${AppException.messageOf(e)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentStage = ref.watch(_adminOrdersStageProvider);
    final search = ref.watch(_adminOrdersSearchProvider);
    final dateFilter = ref.watch(_adminOrdersDateFilterProvider);
    final sortOption = ref.watch(_adminOrdersSortOptionProvider);
    final minTotal = ref.watch(_adminOrdersMinTotalProvider);
    final maxTotal = ref.watch(_adminOrdersMaxTotalProvider);
    final selectedCustomerId =
      ref.watch(_adminOrdersCustomerIdFilterProvider);
    final customRange = ref.watch(_adminOrdersCustomDateRangeProvider);

    final baseFilter = ref.watch(ordersFiltersProvider);
    final effectiveFilter =
      _showAll ? baseFilter.copyWith(stage: 'all') : baseFilter;

    final ordersAsync = ref.watch(adminOrdersProvider(effectiveFilter));

    return AppScaffold(
      title: null,
      actions: [
        IconButton(
          tooltip: 'Yazdır',
          icon: const Icon(Icons.print),
          onPressed: () async {
            await _printFromList(context);
          },
        ),
        if (_selectionMode)
          IconButton(
            tooltip: 'Toplu seçimden çık',
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _selectionMode = false;
                _selectedOrderIds.clear();
              });
            },
          ),
        IconButton(
          tooltip: 'Yenile',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            final filter = ref.read(ordersFiltersProvider);
            final effective =
                _showAll ? filter.copyWith(stage: 'all') : filter;
            ref.invalidate(adminOrdersProvider(effective));
            ref.invalidate(adminOrderCountsProvider(filter));
          },
        ),
        IconButton(
          tooltip: 'Dışa aktar',
          icon: const Icon(Icons.download_outlined),
          onPressed: ordersAsync.isLoading
              ? null
              : () => _openOrdersExportSheet(
                    context: context,
                    currentOrders: ordersAsync.valueOrNull ??
                        const <AdminOrderListEntry>[],
                  ),
        ),
        IconButton(
          tooltip: 'Filtreleri göster',
          icon: const Icon(Icons.filter_list),
          onPressed: () {
            // Masaüstü/web için filtre paneli sağda sabit.
            // Küçük ekranlarda gelecekte ayrı bir bottom sheet olarak açılabilir.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Filtre paneli sağ tarafta yer alıyor.'),
              ),
            );
          },
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
              final showSideFilter = constraints.maxWidth >= 900;
              final includeInlineFilterPanel = !showSideFilter;

              List<Widget> buildCommonHeaderItems() {
                return <Widget>[
                  OrdersAppBar(
                    selectionMode: _selectionMode,
                    selectedCount: _selectedOrderIds.length,
                    search: search,
                    onSearchChanged: (value) {
                      setState(() {
                        _selectionMode = false;
                        _selectedOrderIds.clear();
                      });
                      ref.read(_adminOrdersSearchProvider.notifier).state =
                          value;
                    },
                    onToggleSelectionMode: () {
                      setState(() {
                        _selectionMode = !_selectionMode;
                        _selectedOrderIds.clear();
                      });
                    },
                    infoKey: widget.info,
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  OrdersKpiStrip(
                    currentStage: currentStage,
                    showAll: _showAll,
                    onStageSelected: (stage) {
                      setState(() {
                        _showAll = false;
                        _selectionMode = false;
                        _selectedOrderIds.clear();
                      });
                      ref.read(_adminOrdersStageProvider.notifier).state =
                          stage;
                    },
                    onShowAllSelected: () {
                      setState(() {
                        _showAll = true;
                        _selectionMode = false;
                        _selectedOrderIds.clear();
                      });
                      final filter = ref.read(ordersFiltersProvider);
                      ref.invalidate(
                        adminOrdersProvider(filter.copyWith(stage: 'all')),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  if (includeInlineFilterPanel) ...[
                    OrdersFilterPanel(
                      dateFilter: dateFilter,
                      sortOption: sortOption,
                      minTotal: minTotal,
                      maxTotal: maxTotal,
                      selectedCustomerId: selectedCustomerId,
                      customRange: customRange,
                      onFiltersChanged: () {
                        setState(() {
                          _selectionMode = false;
                          _selectedOrderIds.clear();
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.s16),
                  ],
                ];
              }

              Widget buildOrdersList() {
                return ordersAsync.when(
                  loading: () {
                    final items = <Widget>[
                      ...buildCommonHeaderItems(),
                      const Center(child: AppLoadingState()),
                    ];
                    return ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.s16),
                      itemCount: items.length,
                      itemBuilder: (context, index) => items[index],
                    );
                  },
                  error: (e, _) {
                    final items = <Widget>[
                      ...buildCommonHeaderItems(),
                      AppErrorState(
                        message:
                            'Siparişler yüklenemedi: ${AppException.messageOf(e)}',
                        onRetry: () {
                          final filter = ref.read(ordersFiltersProvider);
                          final effective = _showAll
                              ? filter.copyWith(stage: 'all')
                              : filter;
                          ref.invalidate(adminOrdersProvider(effective));
                        },
                      ),
                    ];
                    return ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.s16),
                      itemCount: items.length,
                      itemBuilder: (context, index) => items[index],
                    );
                  },
                  data: (orders) {
                    final filtered = orders;

                    final items = <Widget>[...buildCommonHeaderItems()];

                    if (filtered.isEmpty) {
                      items.add(
                        OrdersEmptyState(
                          showAll: _showAll,
                          onShowAll: () {
                            setState(() {
                              _showAll = true;
                              _selectionMode = false;
                              _selectedOrderIds.clear();
                            });
                            final filter = ref.read(ordersFiltersProvider);
                            ref.invalidate(
                              adminOrdersProvider(
                                filter.copyWith(stage: 'all'),
                              ),
                            );
                          },
                          onResetFilters: () {
                            setState(() {
                              _selectionMode = false;
                              _selectedOrderIds.clear();
                            });
                            _resetOrderFilters(ref);
                          },
                          onRefresh: () {
                            final filter = ref.read(ordersFiltersProvider);
                            final effective = _showAll
                                ? filter.copyWith(stage: 'all')
                                : filter;
                            ref.invalidate(adminOrdersProvider(effective));
                          },
                        ),
                      );
                      return ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.s16),
                        itemCount: items.length,
                        itemBuilder: (context, index) => items[index],
                      );
                    }

                    final totalAmount = filtered.fold<double>(
                      0,
                      (previousValue, element) =>
                          previousValue + element.totalAmount,
                    );

                    items.add(
                      Card(
                        margin: EdgeInsets.zero,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s12,
                            vertical: AppSpacing.s8,
                          ),
                          child: Row(
                            children: [
                              Text(
                                'Toplam: ${filtered.length} sipariş',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'Toplam Tutar: ${_formatAmount(totalAmount)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    items.add(const SizedBox(height: AppSpacing.s8));

                    if (_showAll) {
                      final Map<String, List<AdminOrderListEntry>> grouped =
                          <String, List<AdminOrderListEntry>>{};
                      for (final order in filtered) {
                        final statusKey =
                            order.status.trim().toLowerCase();
                        grouped
                            .putIfAbsent(
                              statusKey,
                              () => <AdminOrderListEntry>[],
                            )
                            .add(order);
                      }

                      const List<String> orderedStatuses = <String>[
                        'new',
                        'approved',
                        'preparing',
                        'shipped',
                        'cancelled',
                      ];

                      final List<String> keys = <String>[
                        ...orderedStatuses
                            .where((s) => grouped.containsKey(s)),
                        ...grouped.keys.where(
                          (k) => !orderedStatuses.contains(k),
                        ),
                      ];

                      final now = DateTime.now();

                      for (final status in keys) {
                        final groupOrders = grouped[status];
                        if (groupOrders == null || groupOrders.isEmpty) {
                          continue;
                        }

                        final groupTotal = groupOrders.fold<double>(
                          0,
                          (previousValue, element) =>
                              previousValue + element.totalAmount,
                        );

                        final oldest = groupOrders
                            .map((e) => e.createdAt)
                            .reduce((a, b) => a.isBefore(b) ? a : b);
                        final age = now.difference(oldest);
                        final ageText = _formatAge(age);

                        final avg = groupTotal / groupOrders.length;

                        items.add(
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    OrderStatusChip(status: status),
                                    const SizedBox(width: AppSpacing.s8),
                                    Text(
                                      '${groupOrders.length} sipariş',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (_selectionMode)
                                      TextButton(
                                        onPressed: () {
                                          setState(() {
                                            for (final o in groupOrders) {
                                              _selectedOrderIds.add(o.id);
                                            }
                                          });
                                        },
                                        child:
                                            const Text('Bu gruptakileri seç'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.s4),
                                Row(
                                  children: [
                                    Text(
                                      'Toplam: ${_formatAmount(groupTotal)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.s8),
                                    Text(
                                      'Ort.: ${_formatAmount(avg)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.s8),
                                    Text(
                                      'En eski: $ageText',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: theme
                                            .colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                              ],
                            ),
                          ),
                        );

                        for (final order in groupOrders) {
                          items.add(
                            OrderCard(
                              order: order,
                              selectionMode: _selectionMode,
                              isSelected: _selectedOrderIds.contains(order.id),
                              onToggleSelection: () =>
                                  _toggleSelection(order.id),
                              onOpenDetail: () {
                                setState(() {
                                  _lastOpenedOrderId = order.id;
                                });
                                context.go('/orders/${order.id}');
                              },
                              primaryLoading: _approvingOrderId == order.id,
                              onPrimaryAction: () async {
                                final nextStatus = _nextStatus(order.status);
                                if (nextStatus == null) return;
                                if (order.status.trim().toLowerCase() ==
                                        'new' &&
                                    nextStatus == 'approved') {
                                  if (_approvingOrderId != null) return;
                                  setState(() {
                                    _approvingOrderId = order.id;
                                  });
                                  try {
                                    await _approveOrder(
                                      context: context,
                                      orderId: order.id,
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _approvingOrderId = null;
                                      });
                                    }
                                  }
                                } else {
                                  await _updateOrderStatus(
                                    context: context,
                                    order: order,
                                    newStatus: nextStatus,
                                  );
                                }
                              },
                            ),
                          );
                          items.add(const SizedBox(height: AppSpacing.s4));
                        }

                        items.add(const SizedBox(height: AppSpacing.s12));
                      }
                    } else {
                      for (final order in filtered) {
                        items.add(
                          OrderCard(
                            order: order,
                            selectionMode: _selectionMode,
                            isSelected: _selectedOrderIds.contains(order.id),
                            onToggleSelection: () =>
                                _toggleSelection(order.id),
                            onOpenDetail: () {
                              setState(() {
                                _lastOpenedOrderId = order.id;
                              });
                              context.go('/orders/${order.id}');
                            },
                            primaryLoading: _approvingOrderId == order.id,
                            onPrimaryAction: () async {
                              final nextStatus = _nextStatus(order.status);
                              if (nextStatus == null) return;
                              if (order.status.trim().toLowerCase() ==
                                      'new' &&
                                  nextStatus == 'approved') {
                                if (_approvingOrderId != null) return;
                                setState(() {
                                  _approvingOrderId = order.id;
                                });
                                try {
                                  await _approveOrder(
                                    context: context,
                                    orderId: order.id,
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _approvingOrderId = null;
                                    });
                                  }
                                }
                              } else {
                                await _updateOrderStatus(
                                  context: context,
                                  order: order,
                                  newStatus: nextStatus,
                                );
                              }
                            },
                          ),
                        );
                        items.add(const SizedBox(height: AppSpacing.s8));
                      }
                    }

                    if (_selectionMode && _selectedOrderIds.isNotEmpty) {
                      items.add(const SizedBox(height: AppSpacing.s8));
                      items.add(
                        OrdersBulkActionBar(
                          orders: filtered,
                          selectedOrderIds: _selectedOrderIds,
                          onExportRequested: (selectedOrders) =>
                              _openOrdersExportSheet(
                            context: context,
                            currentOrders: filtered,
                            selectedOverride: selectedOrders,
                          ),
                          onBulkCompleted: () {
                            setState(() {
                              _selectedOrderIds.clear();
                              _selectionMode = false;
                            });
                          },
                          onClearSelection: () {
                            setState(() {
                              _selectedOrderIds.clear();
                            });
                          },
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.s16),
                      itemCount: items.length,
                      itemBuilder: (context, index) => items[index],
                    );
                  },
                );
              }

              final list = buildOrdersList();

              if (!showSideFilter) {
                return list;
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: list),
                  const SizedBox(width: AppSpacing.s16),
                  SizedBox(
                    width: 360,
                    child: OrdersFilterPanel(
                      dateFilter: dateFilter,
                      sortOption: sortOption,
                      minTotal: minTotal,
                      maxTotal: maxTotal,
                      selectedCustomerId: selectedCustomerId,
                      customRange: customRange,
                      onFiltersChanged: () {
                        setState(() {
                          _selectionMode = false;
                          _selectedOrderIds.clear();
                        });
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

class OrdersBulkActionBar extends ConsumerWidget {
  const OrdersBulkActionBar({
    super.key,
    required this.orders,
    required this.selectedOrderIds,
    required this.onExportRequested,
    required this.onBulkCompleted,
    required this.onClearSelection,
  });

  final List<AdminOrderListEntry> orders;
  final Set<String> selectedOrderIds;
  final Future<void> Function(List<AdminOrderListEntry> selectedOrders)
      onExportRequested;
  final VoidCallback onBulkCompleted;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedOrders = orders
        .where((o) => selectedOrderIds.contains(o.id))
        .toList(growable: false);
    if (selectedOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    final statusSet = selectedOrders
        .map((o) => o.status.trim().toLowerCase())
        .toSet();

    final allowedTargets = _computeBulkAllowedTargets(statusSet);

    final hasShippedOrCancelled = statusSet.contains('shipped') ||
        statusSet.contains('cancelled');
    final hasNew = statusSet.contains('new');

    final canCreateShipment =
        selectedOrders.isNotEmpty && !hasShippedOrCancelled && !hasNew;

    final shipmentTooltip = hasShippedOrCancelled
        ? 'Sevk listesine tamamlanmış veya iptal edilmiş sipariş eklenemez.'
        : hasNew
            ? 'Onaylanmamış sipariş sevk listesine eklenemez.'
            : 'Seçili siparişleri sevk listesi olarak görüntüle.';

    Future<void> handleTarget(String target) async {
      await _performBulkStatusChange(
        ref: ref,
        context: context,
        selectedOrders: selectedOrders,
        targetStatus: target,
      );
      onBulkCompleted();
    }

    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Row(
          children: [
            Text(
              'Seçili: ${selectedOrders.length}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onClearSelection,
              child: const Text('Temizle'),
            ),
            const Spacer(),
            Tooltip(
              message: shipmentTooltip,
              child: FilledButton.icon(
                onPressed: canCreateShipment
                    ? () {
                        final ids = selectedOrders
                            .map((e) => e.id)
                            .join(',');
                        if (ids.isEmpty) {
                          return;
                        }
                        context.go('/orders/shipment?ids=$ids');
                      }
                    : null,
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Sevk Listesi'),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            if (allowedTargets.contains('approved'))
              FilledButton.tonal(
                onPressed: () => handleTarget('approved'),
                child: const Text('Onayla'),
              ),
            if (allowedTargets.contains('preparing')) ...[
              const SizedBox(width: AppSpacing.s8),
              FilledButton.tonal(
                onPressed: () => handleTarget('preparing'),
                child: const Text('Hazırlanıyor yap'),
              ),
            ],
            if (allowedTargets.contains('cancelled')) ...[
              const SizedBox(width: AppSpacing.s8),
              FilledButton.tonal(
                onPressed: () => handleTarget('cancelled'),
                child: const Text('İptal'),
              ),
            ],
            const SizedBox(width: AppSpacing.s8),
            OutlinedButton.icon(
              onPressed: () => onExportRequested(selectedOrders),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Yazdır / Dışa aktar'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _performBulkStatusChange({
  required WidgetRef ref,
  required BuildContext context,
  required List<AdminOrderListEntry> selectedOrders,
  required String targetStatus,
}) async {
  final repo = adminOrderRepository;
  final ids = selectedOrders.map((e) => e.id).toList(growable: false);
  if (ids.isEmpty) return;

  try {
    if (targetStatus == 'cancelled') {
      final reasonController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Toplu iptal'),
            content: TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'İptal sebebi',
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(false);
                },
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop(true);
                },
                child: const Text('İptal et'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      final reason = reasonController.text.trim();
      if (reason.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('İptal sebebi boş olamaz.'),
            ),
          );
        }
        return;
      }

      await repo.cancelOrdersBulk(
        orderIds: ids,
        reason: reason,
      );
    } else {
      await repo.updateOrdersStatusBulk(
        orderIds: ids,
        status: targetStatus,
      );
    }

    if (context.mounted) {
      final filter = ref.read(ordersFiltersProvider);
      ref.invalidate(adminOrdersProvider(filter));
      ref.invalidate(adminOrderCountsProvider(filter));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Toplu işlem tamamlandı.'),
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'İşlem sırasında hata oluştu: ${AppException.messageOf(e)}',
        ),
      ),
    );
  }
}

enum _OrdersExportAction { print, csv, pdf }

Set<String> _computeBulkAllowedTargets(Set<String> statusSet) {
  Set<String> allowedForStatus(String status) {
    switch (status) {
      case 'new':
        return <String>{'approved', 'cancelled'};
      case 'approved':
        return <String>{'preparing', 'cancelled'};
      case 'preparing':
        return <String>{'shipped', 'cancelled'};
      default:
        return <String>{};
    }
  }

  Set<String>? intersection;
  for (final s in statusSet) {
    final currentAllowed = allowedForStatus(s);
    if (intersection == null) {
      intersection = currentAllowed;
    } else {
      intersection = intersection.intersection(currentAllowed);
    }
  }

  return intersection ?? <String>{};
}

String _formatDate(DateTime date) {
  return formatDate(date);
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String? _primaryActionLabel(String status) {
  final s = status.trim().toLowerCase();
  switch (s) {
    case 'new':
      return 'Onayla';
    case 'approved':
      return 'Hazırlanıyor işaretle';
    case 'preparing':
      return 'Sevk edildi işaretle';
    default:
      return null;
  }
}

String? _nextStatus(String status) {
  final s = status.trim().toLowerCase();
  switch (s) {
    case 'new':
      return 'approved';
    case 'approved':
      return 'preparing';
    case 'preparing':
      return 'shipped';
    default:
      return null;
  }
}

List<PopupMenuEntry<String>> _popupMenuItemsForStatus(String status) {
  final s = status.trim().toLowerCase();
  final List<PopupMenuEntry<String>> items = <PopupMenuEntry<String>>[];

  void addItem(String value, String label) {
    if (value == s) return;
    items.add(
      PopupMenuItem<String>(
        value: value,
        child: Text(label),
      ),
    );
  }

  switch (s) {
    case 'new':
      addItem('approved', 'Onayla');
      addItem('cancelled', 'İptal et');
      break;
    case 'approved':
      addItem('preparing', 'Hazırlanıyor');
      addItem('cancelled', 'İptal et');
      break;
    case 'preparing':
      addItem('shipped', 'Sevk edildi');
      addItem('cancelled', 'İptal et');
      break;
    case 'shipped':
      // Sevk edilmiş sipariş için "Siparişi tamamla" aksiyonu.
      items.add(
        const PopupMenuItem<String>(
          value: 'complete_order',
          child: Text('Siparişi tamamla'),
        ),
      );
      addItem('cancelled', 'İptal et');
      break;
    case 'completed':
      // Tamamlanan sipariş için "Faturaya dönüştür" aksiyonu.
      items.add(
        const PopupMenuItem<String>(
          value: 'convert_to_invoice',
          child: Text('Faturaya dönüştür'),
        ),
      );
      break;
    case 'cancelled':
      break;
    default:
      break;
  }

  return items;
}

String _formatAge(Duration diff) {
  if (diff.inDays >= 1) {
    return '${diff.inDays}g';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours}s';
  }
  return '${diff.inMinutes}dk';
}

List<AdminOrderListEntry> _applyOrdersFilters({
  required List<AdminOrderListEntry> base,
  required OrdersFilter filter,
  required AdminOrdersSortOption sortOption,
}) {
  final search = (filter.search ?? '').trim().toLowerCase();

  Iterable<AdminOrderListEntry> filtered = base;

  if (search.isNotEmpty) {
    filtered = filtered.where((order) {
      final buffer = <String?>[
        order.orderNo?.toString(),
        order.customerName,
        order.customerPhone,
        order.customerCode,
        order.note,
      ];
      final haystack = buffer.whereType<String>().join(' ').toLowerCase();
      return haystack.contains(search);
    });
  }

  bool matchesDate(AdminOrderListEntry order) {
    final created = order.createdAt;
    final start = filter.startDate;
    final end = filter.endDate;
    if (start == null && end == null) return true;
    if (start != null && created.isBefore(start)) return false;
    if (end != null && !created.isBefore(end)) return false;
    return true;
  }

  filtered = filtered.where(matchesDate);

  final minTotal = filter.minAmount;
  final maxTotal = filter.maxAmount;

  if (minTotal != null) {
    filtered = filtered.where((o) => o.totalAmount >= minTotal);
  }
  if (maxTotal != null) {
    filtered = filtered.where((o) => o.totalAmount <= maxTotal);
  }

  final selectedCustomerId = filter.customerId;
  if (selectedCustomerId != null && selectedCustomerId.isNotEmpty) {
    filtered = filtered.where((o) => o.customerId == selectedCustomerId);
  }

  final list = filtered.toList();

  int compareString(String? a, String? b) =>
      (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());

  list.sort((a, b) {
    switch (sortOption) {
      case AdminOrdersSortOption.newest:
        return b.createdAt.compareTo(a.createdAt);
      case AdminOrdersSortOption.amountDesc:
        return b.totalAmount.compareTo(a.totalAmount);
      case AdminOrdersSortOption.customerAz:
        return compareString(a.customerName, b.customerName);
    }
  });

  return list;
}

void _resetOrderFilters(WidgetRef ref) {
  ref.read(_adminOrdersSearchProvider.notifier).state = '';
  ref.read(_adminOrdersDateFilterProvider.notifier).state =
      AdminOrdersDateFilter.today;
  ref.read(_adminOrdersCustomDateRangeProvider.notifier).state = null;
  ref.read(_adminOrdersMinTotalProvider.notifier).state = null;
  ref.read(_adminOrdersMaxTotalProvider.notifier).state = null;
  ref.read(_adminOrdersCustomerIdFilterProvider.notifier).state = null;
  ref.read(_adminOrdersSortOptionProvider.notifier).state =
      AdminOrdersSortOption.newest;
}

class OrdersAppBar extends StatelessWidget {
  const OrdersAppBar({
    super.key,
    required this.selectionMode,
    required this.selectedCount,
    required this.search,
    required this.onSearchChanged,
    required this.onToggleSelectionMode,
    this.infoKey,
  });

  final bool selectionMode;
  final int selectedCount;
  final String search;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onToggleSelectionMode;
  final String? infoKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (infoKey == 'invoice-auto')
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s8),
            child: Card(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        'Fatura sipariş tamamlanınca otomatik oluşur. '
                        'Manuel fatura oluşturma devre dışıdır.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;

            final header = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sipariş Yönetimi',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  selectionMode && selectedCount > 0
                      ? '$selectedCount sipariş seçildi'
                      : 'Yeni, onaylı ve sevk edilen tüm siparişlerinizi yönetin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );

            final actionButton = TextButton.icon(
              onPressed: onToggleSelectionMode,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                selectionMode
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
              label: Text(
                selectionMode ? 'Toplu seçim açık' : 'Toplu seçim',
                overflow: TextOverflow.ellipsis,
              ),
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: AppSpacing.s8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: actionButton,
                  ),
                ],
              );
            }

            return Row(
              children: [
                header,
                const Spacer(),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: actionButton,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppSearchField(
                    hintText:
                        'Sipariş no, müşteri adı, telefon veya not ile ara',
                    padded: false,
                    initialValue: search,
                    onChanged: onSearchChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class OrdersKpiStrip extends ConsumerWidget {
  const OrdersKpiStrip({
    super.key,
    required this.currentStage,
    required this.showAll,
    required this.onStageSelected,
    required this.onShowAllSelected,
  });

  final AdminOrderStageTab currentStage;
  final bool showAll;
  final ValueChanged<AdminOrderStageTab> onStageSelected;
  final VoidCallback onShowAllSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final stage in AdminOrderStageTab.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s8),
              child: _KpiCard(
                label: stage.label,
                stage: stage,
                isSelected: !showAll && currentStage == stage,
                onTap: () => onStageSelected(stage),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s8),
            child: _KpiAllCard(
              isSelected: showAll,
              onTap: onShowAllSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends ConsumerWidget {
  const _KpiCard({
    required this.label,
    required this.stage,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final AdminOrderStageTab stage;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(ordersFiltersProvider);
    final countsAsync = ref.watch(adminOrderCountsProvider(filter));
    final counts = countsAsync.maybeWhen(data: (v) => v, orElse: () => null);

    int? count;
    if (counts != null) {
      switch (stage) {
        case AdminOrderStageTab.newOrders:
          count = counts.newCount;
          break;
        case AdminOrderStageTab.approved:
          count = counts.approvedCount;
          break;
        case AdminOrderStageTab.preparing:
          count = counts.preparingCount;
          break;
        case AdminOrderStageTab.shipped:
          count = counts.shippedCount;
          break;
        case AdminOrderStageTab.cancelled:
          count = counts.cancelledCount;
          break;
      }
    }

    final Color bgColor;
    if (isSelected) {
      bgColor = theme.colorScheme.primary.withValues(alpha: 0.1);
    } else {
      bgColor = theme.colorScheme.surfaceContainerHigh;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  count == null ? '…' : count.toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiAllCard extends StatelessWidget {
  const _KpiAllCard({
    required this.isSelected,
    required this.onTap,
  });

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : theme.colorScheme.surfaceContainerHigh;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s12,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.all_inbox_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              'Tümü',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.selectionMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onOpenDetail,
    required this.onPrimaryAction,
    this.primaryLoading = false,
  });

  final AdminOrderListEntry order;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onOpenDetail;
  final VoidCallback onPrimaryAction;
  final bool primaryLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _formatDate(order.createdAt);
    final totalText = _formatAmount(order.totalAmount);
    final orderNo = order.orderNo;
    final orderLabel = orderNo != null ? 'Sipariş #$orderNo' : 'Sipariş';
    final subtitleLine = '$orderLabel • $dateText';
    final notePreview = order.note?.trim();
    final actionLabel = _primaryActionLabel(order.status);

    Color stripeColor;
    switch (order.status.trim().toLowerCase()) {
      case 'new':
        stripeColor = theme.colorScheme.primary;
        break;
      case 'approved':
        stripeColor = theme.colorScheme.tertiary;
        break;
      case 'preparing':
        stripeColor = theme.colorScheme.secondary;
        break;
      case 'shipped':
        stripeColor = theme.colorScheme.outlineVariant;
        break;
      case 'cancelled':
        stripeColor = theme.colorScheme.error;
        break;
      default:
        stripeColor = theme.colorScheme.outline;
        break;
    }

    Widget headerRow({required bool includeCheckbox}) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (includeCheckbox)
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.s8,
                top: AppSpacing.s4,
              ),
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelection(),
              ),
            ),
          Expanded(
            child: Text(
              order.customerName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          OrderStatusChip(status: order.status),
        ],
      );
    }

    Widget subtitleAndNote() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.s4),
          Text(
            subtitleLine,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (notePreview != null && notePreview.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(
              notePreview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    Widget totalRow() {
      return Row(
        children: [
          Text(
            totalText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      );
    }

    Widget actionRow() {
      if (selectionMode) {
        return const SizedBox.shrink();
      }
      return Wrap(
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (actionLabel != null)
            FilledButton.tonal(
              onPressed: primaryLoading ? null : onPrimaryAction,
              child: primaryLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : Text(actionLabel),
            ),
          _OrderMoreMenu(order: order),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Material(
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (selectionMode) {
              onToggleSelection();
            } else {
              onOpenDetail();
            }
          },
          onLongPress: selectionMode ? null : onToggleSelection,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 4,
                    offset: Offset(0, 1),
                    color: Colors.black12,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 4,
                      color: stripeColor,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.s12),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 600;

                          if (isMobile) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                headerRow(includeCheckbox: selectionMode),
                                subtitleAndNote(),
                                const SizedBox(height: AppSpacing.s8),
                                totalRow(),
                                const SizedBox(height: AppSpacing.s8),
                                actionRow(),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    headerRow(
                                      includeCheckbox: selectionMode,
                                    ),
                                    subtitleAndNote(),
                                    const SizedBox(height: AppSpacing.s8),
                                    actionRow(),
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
                          );
                        },
                      ),
                    ),
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

class _OrderMoreMenu extends ConsumerStatefulWidget {
  const _OrderMoreMenu({required this.order});

  final AdminOrderListEntry order;

  @override
  ConsumerState<_OrderMoreMenu> createState() => _OrderMoreMenuState();
}

class _OrderMoreMenuState extends ConsumerState<_OrderMoreMenu> {
  bool _isConverting = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final items = _popupMenuItemsForStatus(order.status);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        final currentStatus = order.status.trim().toLowerCase();
        final action = value.trim().toLowerCase();

        if (action == 'complete_order') {
          try {
            await adminOrderRepository.updateOrderStatus(
              orderId: order.id,
              status: 'completed',
            );

            String? invoiceId;
            try {
              invoiceId = await adminInvoiceRepository
                  .convertOrderToInvoice(orderId: order.id);

              if (kDebugMode) {
                debugPrint(
                  '[ADMIN][Orders] auto convert_to_invoice on complete '
                  'orderId=${order.id} invoiceId=$invoiceId',
                );
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint(
                  '[ADMIN][Orders] auto convert_to_invoice failed '
                  'orderId=${order.id} error=$e',
                );
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Sipariş tamamlandı ancak fatura oluşturulurken hata oluştu: ${AppException.messageOf(e)}',
                    ),
                  ),
                );
              }
            }

            final filter = ref.read(ordersFiltersProvider);
            ref.invalidate(
              adminOrdersProvider(filter),
            );
            ref.invalidate(
              adminOrderCountsProvider(filter),
            );

            // Faturalar sekmesindeki listelerin yeniden yüklenebilmesi için
            // tetikleyici token'i arttır.
            if (invoiceId != null && invoiceId.isNotEmpty) {
              ref.read(adminInvoicesReloadTokenProvider.notifier).state++;
            }

            if (!context.mounted) {
              return;
            }

            final snackText = (invoiceId != null && invoiceId.isNotEmpty)
                ? 'Sipariş tamamlandı ve faturaya dönüştürüldü.'
                : 'Sipariş tamamlandı.';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(snackText),
              ),
            );
          } catch (e) {
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Sipariş tamamlanırken hata: ${AppException.messageOf(e)}',
                ),
              ),
            );
          }
          return;
        }

        if (action == 'convert_to_invoice') {
          if (_isConverting) {
            // Aynı siparişi art arda dönüştürme denemelerini engelle.
            return;
          }

          _isConverting = true;
          var dialogShown = false;

          try {
            if (context.mounted) {
              dialogShown = true;
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
              );
            }

            final invoiceId = await adminInvoiceRepository
                .convertOrderToInvoice(orderId: order.id);

            if (kDebugMode) {
              debugPrint(
                '[ADMIN][Orders] convert_to_invoice succeeded '
                'orderId=${order.id} invoiceId=$invoiceId',
              );
            }

            final filter = ref.read(ordersFiltersProvider);
            ref.invalidate(adminOrdersProvider(filter));
            ref.invalidate(adminOrderCountsProvider(filter));

            // Faturalar sekmesindeki listelerin yeniden yüklenebilmesi için
            // tetikleyici token'i arttır.
            ref.read(adminInvoicesReloadTokenProvider.notifier).state++;

            if (context.mounted) {
              if (dialogShown) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sipariş faturaya dönüştürüldü.'),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              if (dialogShown) {
                Navigator.of(context, rootNavigator: true).pop();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Sipariş faturaya dönüştürülürken hata: ${AppException.messageOf(e)}',
                  ),
                ),
              );
            }
          } finally {
            _isConverting = false;
          }
          return;
        }

        if (currentStatus == action) {
          return;
        }

        if (action == 'cancelled') {
          await _performBulkStatusChange(
            ref: ref,
            context: context,
            selectedOrders: <AdminOrderListEntry>[order],
            targetStatus: 'cancelled',
          );
        } else {
          await adminOrderRepository.updateOrderStatus(
            orderId: order.id,
            status: action,
          );
        }
      },
      itemBuilder: (context) => items,
    );
  }
}

class OrdersEmptyState extends StatelessWidget {
  const OrdersEmptyState({
    super.key,
    required this.showAll,
    required this.onShowAll,
    required this.onResetFilters,
    required this.onRefresh,
  });

  final bool showAll;
  final VoidCallback onShowAll;
  final VoidCallback onResetFilters;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Yeni sipariş yok',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Filtreleri değiştirerek veya tüm siparişleri göstererek tekrar deneyebilirsiniz.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              alignment: WrapAlignment.center,
              children: [
                if (!showAll)
                  OutlinedButton(
                    onPressed: onShowAll,
                    child: const Text('Tüm siparişleri göster'),
                  ),
                OutlinedButton(
                  onPressed: onResetFilters,
                  child: const Text('Filtreyi sıfırla'),
                ),
                FilledButton(
                  onPressed: onRefresh,
                  child: const Text('Yenile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class OrdersFilterPanel extends ConsumerStatefulWidget {
  const OrdersFilterPanel({
    super.key,
    required this.dateFilter,
    required this.sortOption,
    required this.minTotal,
    required this.maxTotal,
    required this.selectedCustomerId,
    required this.customRange,
    required this.onFiltersChanged,
  });

  final AdminOrdersDateFilter dateFilter;
  final AdminOrdersSortOption sortOption;
  final double? minTotal;
  final double? maxTotal;
  final String? selectedCustomerId;
  final DateTimeRange? customRange;
  final VoidCallback onFiltersChanged;

  @override
  ConsumerState<OrdersFilterPanel> createState() => _OrdersFilterPanelState();
}

class _OrdersFilterPanelState extends ConsumerState<OrdersFilterPanel> {
  late AdminOrdersDateFilter _dateFilter;
  late AdminOrdersSortOption _sortOption;
  late TextEditingController _minController;
  late TextEditingController _maxController;
  DateTimeRange? _customRange;
  String? _customerName;

  @override
  void initState() {
    super.initState();
    _dateFilter = widget.dateFilter;
    _sortOption = widget.sortOption;
    _customRange = widget.customRange;
    _minController = TextEditingController(
      text: widget.minTotal?.toStringAsFixed(0) ?? '',
    );
    _maxController = TextEditingController(
      text: widget.maxTotal?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _dateFilter = AdminOrdersDateFilter.custom;
      });
    }
  }

  void _apply() {
    double? parseAmount(String input) {
      final trimmed = input.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed.replaceAll(',', '.'));
    }

    final min = parseAmount(_minController.text);
    final max = parseAmount(_maxController.text);

    ref.read(_adminOrdersDateFilterProvider.notifier).state = _dateFilter;
    ref.read(_adminOrdersCustomDateRangeProvider.notifier).state =
        _customRange;
    ref.read(_adminOrdersMinTotalProvider.notifier).state = min;
    ref.read(_adminOrdersMaxTotalProvider.notifier).state = max;
    ref.read(_adminOrdersSortOptionProvider.notifier).state = _sortOption;

    widget.onFiltersChanged();
  }

  void _reset() {
    _resetOrderFilters(ref);
    setState(() {
      _dateFilter = AdminOrdersDateFilter.today;
      _sortOption = AdminOrdersSortOption.newest;
      _customRange = null;
      _minController.text = '';
      _maxController.text = '';
      _customerName = null;
    });
    widget.onFiltersChanged();
  }

  Future<void> _pickCustomer() async {
    final result = await showModalBottomSheet<_CustomerSelectionResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _CustomerSelectSheet(),
    );

    if (result == null) return;

    ref.read(_adminOrdersCustomerIdFilterProvider.notifier).state =
        result.id;
    setState(() {
      _customerName = result.name;
    });
    widget.onFiltersChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customerLabel = _customerName ??
        (widget.selectedCustomerId != null
            ? 'Seçili müşteri'
            : 'Müşteri seç');

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtreler',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Tarih aralığı',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s8,
              children: [
                for (final value in AdminOrdersDateFilter.values)
                  ChoiceChip(
                    label: Text(value.label),
                    selected: _dateFilter == value,
                    onSelected: (_) {
                      setState(() {
                        _dateFilter = value;
                      });
                      if (value != AdminOrdersDateFilter.custom) {
                        setState(() {
                          _customRange = null;
                        });
                      }
                    },
                  ),
              ],
            ),
            if (_dateFilter == AdminOrdersDateFilter.custom) ...[
              const SizedBox(height: AppSpacing.s8),
              OutlinedButton.icon(
                onPressed: _pickCustomRange,
                icon: const Icon(Icons.date_range),
                label: Text(
                  _customRange == null
                      ? 'Tarih seç'
                      : '${_customRange?.start.day}.${_customRange?.start.month}.${_customRange?.start.year} - '
                          '${_customRange?.end.day}.${_customRange?.end.month}.${_customRange?.end.year}',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Müşteri',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s4),
            OutlinedButton.icon(
              onPressed: _pickCustomer,
              icon: const Icon(Icons.person_search_outlined),
              label: Text(customerLabel),
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Tutar aralığı',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minController,
                    decoration: const InputDecoration(
                      labelText: 'Min',
                      prefixText: '₺ ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    decoration: const InputDecoration(
                      labelText: 'Max',
                      prefixText: '₺ ',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Sıralama',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s4),
            DropdownButton<AdminOrdersSortOption>(
              isExpanded: true,
              value: _sortOption,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _sortOption = value;
                });
              },
              items: AdminOrdersSortOption.values
                  .map(
                    (o) => DropdownMenuItem<AdminOrdersSortOption>(
                      value: o,
                      child: Text(o.label),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: AppSpacing.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _reset,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Sıfırla'),
                ),
                const SizedBox(width: AppSpacing.s8),
                FilledButton(
                  onPressed: _apply,
                  child: const Text('Uygula'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSelectionResult {
  _CustomerSelectionResult({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;
}

class _CustomerSelectSheet extends StatefulWidget {
  const _CustomerSelectSheet();

  @override
  State<_CustomerSelectSheet> createState() => _CustomerSelectSheetState();
}

class _CustomerSelectSheetState extends State<_CustomerSelectSheet> {
  String _search = '';
  bool _loading = false;
  List<Customer> _results = <Customer>[];

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final customers = await customerRepository.fetchCustomers(
        search: _search,
        isActive: true,
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _results = customers;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.6;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Müşteri seç',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppSearchField(
              hintText: 'Cari adı / kodu ara',
              padded: false,
              onChanged: (value) {
                _search = value;
                _load();
              },
            ),
            const SizedBox(height: AppSpacing.s12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.s8),
                child: CircularProgressIndicator(),
              )
            else if (_results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.s8),
                child: Text('Sonuç bulunamadı.'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListHeight),
                child: ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final c = _results[index];
                    return ListTile(
                      title: Text(c.name),
                      subtitle: c.code.isNotEmpty ? Text(c.code) : null,
                      onTap: () {
                        Navigator.of(context).pop(
                          _CustomerSelectionResult(
                            id: c.id,
                            name: c.name,
                          ),
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
