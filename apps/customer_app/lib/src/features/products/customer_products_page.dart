import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../utils/formatters_tr.dart';
import '../../widgets/stock_image_thumbnail.dart';

final _searchProvider = StateProvider<String>((ref) => '');

/// Mevcut sayfa index'i (0-based).
final _pageIndexProvider = StateProvider<int>((ref) => 0);

/// Basit grup filtresi için seçili grup adı (null/boş = Tümü).
final _groupFilterProvider = StateProvider<String?>((ref) => null);

/// Dropdown için distinct grup isimleri.
final _groupNamesProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final client = supabaseClient;

  final customerId = ref.watch(customerIdProvider);
  if (customerId == null || customerId.isEmpty) {
    return <String>[];
  }

  final data = await client
      .from('v_customer_stock_prices')
      .select('group_name')
      .eq('is_active', true)
      .eq('customer_id', customerId);

  final rows = (data as List).cast<Map<String, dynamic>>();
  final names = rows
      .map((row) => row['group_name'] as String?)
      .where((name) => name != null)
      .map((name) => name!.trim())
      .where((name) => name.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  return names;
});

class EmptyDebugInfo {
  const EmptyDebugInfo({
    required this.stepATotal,
    required this.stepBIsActive,
    required this.stepDFinal,
    required this.hasCustomerUserMapping,
    required this.search,
    required this.page,
    this.groupFilter,
  });

  /// Adım A: from('stocks').select('id') sonucu toplam kayıt sayısı.
  final int stepATotal;

  /// Adım B: + eq('is_active', true) sonrası kayıt sayısı.
  final int stepBIsActive;

  /// Adım D: müşteri ürün sorgusundaki tüm filtreler sonrası kayıt sayısı.
  final int stepDFinal;

  final bool hasCustomerUserMapping;

  /// Arama terimi (boş string de olabilir).
  final String search;

  /// Mevcut sayfa index'i (0-based).
  final int page;
  final String? groupFilter;
}

final _emptyDebugInfoProvider =
    FutureProvider.autoDispose<EmptyDebugInfo?>((ref) async {
  final client = supabaseClient;

  try {
    final user = client.auth.currentUser;
    final String? customerId = ref.watch(customerIdProvider);
    final search = ref.read(_searchProvider);
    final page = ref.read(_pageIndexProvider);
    final groupFilter = ref.read(_groupFilterProvider);

    // Adım A: view'daki tüm kayıtlar.
    if (customerId == null || customerId.isEmpty) {
      return null;
    }

    final stepAData = await client
      .from('v_customer_stock_prices')
      .select('id')
      .eq('customer_id', customerId);
    final stepATotal = (stepAData as List<dynamic>).length;

    // Adım B: sadece is_active = true filtresi.
    final stepBData = await client
      .from('v_customer_stock_prices')
      .select('id')
      .eq('is_active', true)
      .eq('customer_id', customerId);
    final stepBIsActive = (stepBData as List<dynamic>).length;

    // Adım C: Uygulamada açık bir firma/tenant filtresi YOK.
    // Eğer Supabase RLS politikaları tenant/customer bazlı kısıtlama yapıyorsa,
    // bu, burada değil doğrudan sunucu tarafında uygulanacaktır.

    var stepDQuery = client
      .from('v_customer_stock_prices')
      .select('id')
      .eq('is_active', true)
      .eq('customer_id', customerId);

    if (groupFilter != null && groupFilter.trim().isNotEmpty) {
      stepDQuery = stepDQuery.eq('group_name', groupFilter.trim());
    }

    if (search.trim().isNotEmpty) {
      final q = search.trim();
      stepDQuery = stepDQuery.or(
        'name.ilike.%$q%,code.ilike.%$q%,barcode.ilike.%$q%,'
        'pack_barcode.ilike.%$q%,box_barcode.ilike.%$q%',
      );
    }

    final stepDData = await stepDQuery;
    final stepDFinal = (stepDData as List<dynamic>).length;

    Future<dynamic>? mappingFuture;
    if (user != null) {
      mappingFuture = client
          .from('customers')
          .select('id')
          .eq('auth_user_id', user.id)
          .maybeSingle();
    }

    final mappingData = mappingFuture == null ? null : await mappingFuture;
    final hasMapping = mappingData != null;

    assert(() {
      debugPrint(
        '[CustomerProducts][empty-debug] A(tümü)=$stepATotal, '
        'B(is_active)=$stepBIsActive, D(son)=$stepDFinal, '
        'search="$search", page=$page, '
        'groupFilter=$groupFilter',
      );
      return true;
    }());

    return EmptyDebugInfo(
      stepATotal: stepATotal,
      stepBIsActive: stepBIsActive,
      stepDFinal: stepDFinal,
      hasCustomerUserMapping: hasMapping,
      search: search,
      page: page,
      groupFilter: groupFilter,
    );
  } catch (_) {
    return null;
  }
});

class CustomerProductsState {
  const CustomerProductsState({
    required this.items,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    this.error,
    this.stackTrace,
  });

  final List<CustomerProduct> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final Object? error;
  final StackTrace? stackTrace;

  factory CustomerProductsState.initial() {
    return const CustomerProductsState(
      items: <CustomerProduct>[],
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      error: null,
      stackTrace: null,
    );
  }

  CustomerProductsState copyWith({
    List<CustomerProduct>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    Object? error = _sentinel,
    StackTrace? stackTrace = _sentinelStack,
  }) {
    return CustomerProductsState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: identical(error, _sentinel) ? this.error : error,
      stackTrace:
          identical(stackTrace, _sentinelStack) ? this.stackTrace : stackTrace,
    );
  }
}

const _sentinel = Object();
const _sentinelStack = StackTrace.empty;

class CustomerProductsController extends StateNotifier<CustomerProductsState> {
  CustomerProductsController(this._ref, this._repo)
      : super(CustomerProductsState.initial()) {
    loadFirstPage();
  }

  final Ref _ref;
  final CustomerProductRepository _repo;

  static const int _pageSize = 20;
  int _page = 0;

  Future<void> loadFirstPage() async {
    _page = 0;
    _ref.read(_pageIndexProvider.notifier).state = 0;
    state = state.copyWith(
      items: <CustomerProduct>[],
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      error: null,
      stackTrace: null,
    );
    await _fetchPage(reset: true);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }
    _page += 1;
    _ref.read(_pageIndexProvider.notifier).state = _page;
    state = state.copyWith(isLoadingMore: true, error: null, stackTrace: null);
    await _fetchPage(reset: false);
  }

  Future<void> refresh() async {
    await loadFirstPage();
  }

  Future<void> _fetchPage({required bool reset}) async {
    try {
      final search = _ref.read(_searchProvider);
      final groupFilter = _ref.read(_groupFilterProvider);

      final customerId = _ref.read(customerIdProvider);
      if (customerId == null || customerId.isEmpty) {
        state = state.copyWith(
          items: <CustomerProduct>[],
          isLoading: false,
          isLoadingMore: false,
          hasMore: false,
          error: null,
          stackTrace: null,
        );
        return;
      }

      final items = await _repo.fetchProducts(
        customerId: customerId,
        page: _page,
        pageSize: _pageSize,
        search: search.isEmpty ? null : search,
        groupName:
            groupFilter == null || groupFilter.isEmpty ? null : groupFilter,
      );

      final hasMore = items.length >= _pageSize;
      final newList = reset ? items : <CustomerProduct>[...state.items, ...items];

      state = state.copyWith(
        items: newList,
        isLoading: false,
        isLoadingMore: false,
        hasMore: hasMore,
        error: null,
        stackTrace: null,
      );
    } catch (e, st) {
      if (_page > 0) {
        _page -= 1;
      }
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: e,
        stackTrace: st,
      );
    }
  }
}

final customerProductsControllerProvider =
    StateNotifierProvider<CustomerProductsController, CustomerProductsState>(
  (ref) => CustomerProductsController(ref, customerProductRepository),
);

class CustomerProductsPage extends ConsumerStatefulWidget {
  const CustomerProductsPage({super.key});

  @override
  ConsumerState<CustomerProductsPage> createState() => _CustomerProductsPageState();
}

class _CustomerProductsPageState extends ConsumerState<CustomerProductsPage> {
  void _onSearchChanged(String value) {
    ref.read(_searchProvider.notifier).state = value.trim();
    ref
        .read(customerProductsControllerProvider.notifier)
        .loadFirstPage();
  }

  Future<void> _openBarcodeScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _BarcodeScannerPage()),
    );

    if (!mounted || code == null || code.isEmpty) {
      return;
    }

    ref.read(_searchProvider.notifier).state = code;
    await ref
        .read(customerProductsControllerProvider.notifier)
        .loadFirstPage();

    final state = ref.read(customerProductsControllerProvider);
    if (!mounted) return;

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu barkoda ait ürün bulunamadı'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerProductsControllerProvider);
    final groupNamesAsync = ref.watch(_groupNamesProvider);
    final debugInfoAsync = ref.watch(_emptyDebugInfoProvider);

    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Ürünler',
      titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            color: Colors.black,
          ) ??
          theme.textTheme.titleLarge?.copyWith(color: Colors.black),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(customerProductsControllerProvider.notifier)
            .refresh(),
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 200 &&
                notification is ScrollUpdateNotification) {
              final current =
                  ref.read(customerProductsControllerProvider);
              if (!current.isLoading &&
                  !current.isLoadingMore &&
                  current.hasMore) {
                ref
                    .read(customerProductsControllerProvider.notifier)
                    .loadMore();
              }
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: AppSpacing.horizontal16,
                      child: Row(
                        children: [
                          Expanded(
                            child: AppSearchField(
                              hintText: 'Ara (ad / kod / barkod)',
                              initialValue: ref.read(_searchProvider),
                              padded: false,
                              onChanged: _onSearchChanged,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s8),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            tooltip: 'Barkod ile ara',
                            onPressed: _openBarcodeScanner,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Padding(
                      padding: AppSpacing.horizontal16,
                      child: groupNamesAsync.when(
                        loading: () => const SizedBox(
                          height: 40,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (groups) {
                          if (groups.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final selected = ref.watch(_groupFilterProvider);

                          return Wrap(
                            spacing: AppSpacing.s8,
                            runSpacing: AppSpacing.s8,
                            children: [
                              ChoiceChip(
                                label: const Text(
                                  'Tümü',
                                  style: TextStyle(color: Colors.black),
                                ),
                                selected: selected == null,
                                onSelected: (_) {
                                  ref
                                      .read(_groupFilterProvider.notifier)
                                      .state = null;
                                  ref
                                      .read(
                                          customerProductsControllerProvider
                                              .notifier)
                                      .loadFirstPage();
                                },
                              ),
                              ...groups.map(
                                (g) => ChoiceChip(
                                  label: Text(
                                    g,
                                    style:
                                        const TextStyle(color: Colors.black),
                                  ),
                                  selected: selected == g,
                                  onSelected: (_) {
                                    ref
                                        .read(_groupFilterProvider.notifier)
                                        .state = g;
                                    ref
                                        .read(
                                            customerProductsControllerProvider
                                                .notifier)
                                        .loadFirstPage();
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                  ],
                ),
              ),
              if (state.isLoading && state.items.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppLoadingState(),
                )
              else if (state.error != null && state.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorState(
                    message: state.error.toString(),
                    onRetry: () => ref
                        .read(customerProductsControllerProvider.notifier)
                        .loadFirstPage(),
                  ),
                )
              else if (state.items.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    title: 'Ürün bulunamadı',
                    subtitle:
                        'Arama kriterlerini değiştirerek tekrar deneyebilirsiniz.',
                    action: debugInfoAsync.when(
                      data: (info) => info == null
                          ? const SizedBox.shrink()
                          : const SizedBox.shrink(),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
                )
              else ...[
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final p = state.items[index];
                      return _ProductListItem(product: p);
                    },
                    childCount: state.items.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 12),
                    child: Center(
                      child: state.isLoadingMore
                          ? const CircularProgressIndicator(strokeWidth: 2)
                          : state.hasMore
                              ? const SizedBox.shrink()
                              : const Text('Daha fazla ürün yok'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductListItem extends StatelessWidget {
  const _ProductListItem({required this.product});

  final CustomerProduct product;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>['Kod: ${product.code}'];
    if (product.brand != null && product.brand!.isNotEmpty) {
      subtitleParts.add(product.brand!);
    }

    final priceText = product.effectivePrice != null
    ? formatMoney(product.effectivePrice)
    : formatMoney(null);

    return AppListTile(
      leading: StockImageThumbnail(imagePath: product.imagePath),
      title: product.name,
      subtitle: subtitleParts.join(' • '),
      trailing: Text(
        priceText,
        style: const TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _BarcodeScannerPage extends StatelessWidget {
  const _BarcodeScannerPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barkod Tara')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcode = capture.barcodes.firstOrNull;
          final value = barcode?.rawValue;
          if (value != null && value.isNotEmpty) {
            Navigator.of(context).pop<String>(value);
          }
        },
      ),
    );
  }
}

// Eski _ErrorView ve _EmptyView bileşenleri yerine
// AppErrorState ve AppEmptyState kullanılmaktadır.
