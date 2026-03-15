import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import 'barcode_scanner_page.dart';

final _stockSearchProvider = StateProvider<String>((ref) => '');
final _stockFilterProvider = StateProvider<_StockFilter>((ref) => _StockFilter.active);
final _stockPageProvider = StateProvider<int>((ref) => 0);

final _selectionModeProvider = StateProvider<bool>((ref) => false);
final _selectedStockIdsProvider =
  StateProvider<Set<String>>((ref) => <String>{});

enum _StockExtraFilter { barcodeOnly, lowStock, withMultipliers }

final _stockExtraFiltersProvider =
    StateProvider<Set<_StockExtraFilter>>((ref) => <_StockExtraFilter>{});
enum _StockSortOption { nameAsc, codeAsc, stockAscending }

final _stockSortOptionProvider =
    StateProvider<_StockSortOption>((ref) => _StockSortOption.nameAsc);

  enum _StockViewMode { grouped, flat }

  final _stockViewModeProvider =
    StateProvider<_StockViewMode>((ref) => _StockViewMode.grouped);

final stocksFutureProvider =
    FutureProvider.autoDispose<List<Stock>>((ref) async {
  final page = ref.watch(_stockPageProvider);
  final search = ref.watch(_stockSearchProvider);
  final filter = ref.watch(_stockFilterProvider);
  final extraFilters = ref.watch(_stockExtraFiltersProvider);
  final sortOption = ref.watch(_stockSortOptionProvider);

  bool? isActive;
  switch (filter) {
    case _StockFilter.active:
      isActive = true;
      break;
    case _StockFilter.passive:
      isActive = false;
      break;
    case _StockFilter.all:
      isActive = null;
      break;
  }

  final stocks = await stockRepository.fetchStocks(
    page: page,
    pageSize: 20,
    search: search.trim().isEmpty ? null : search.trim(),
    isActive: isActive,
  );

  Iterable<Stock> filtered = stocks;

  if (extraFilters.contains(_StockExtraFilter.barcodeOnly)) {
    filtered = filtered.where(
      (s) =>
          (s.barcode != null && s.barcode!.isNotEmpty) ||
          (s.packBarcode != null && s.packBarcode!.isNotEmpty) ||
          (s.boxBarcode != null && s.boxBarcode!.isNotEmpty),
    );
  }

  if (extraFilters.contains(_StockExtraFilter.lowStock)) {
    filtered = filtered.where(
      (s) => (s.quantity ?? 0) <= 5,
    );
  }

  if (extraFilters.contains(_StockExtraFilter.withMultipliers)) {
    final List<Stock> withMultiplier = [];
    for (final stock in filtered) {
      if (stock.id == null) continue;
      final units = await stockRepository.fetchStockUnits(stock.id!);
      final hasMultiplier = units.any(
        (u) =>
            (u.packContainsPiece ?? 0) > 1 ||
            (u.caseContainsPiece ?? 0) > 1,
      );
      if (hasMultiplier) {
        withMultiplier.add(stock);
      }
    }
    filtered = withMultiplier;
  }

  final list = filtered.toList();

  int compareString(String? a, String? b) =>
      (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());

  list.sort((a, b) {
    switch (sortOption) {
      case _StockSortOption.nameAsc:
        return compareString(a.name, b.name);
      case _StockSortOption.codeAsc:
        return compareString(a.code, b.code);
      case _StockSortOption.stockAscending:
        final av = a.quantity ?? 0;
        final bv = b.quantity ?? 0;
        return av.compareTo(bv);
    }
  });

  return list;
});

class StockListPage extends ConsumerStatefulWidget {
  const StockListPage({super.key});

  @override
  ConsumerState<StockListPage> createState() => _StockListPageState();
}

class _StockListPageState extends ConsumerState<StockListPage> {
  bool _bulkLoading = false;
  String? _lastSingleResultSearch;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _openBarcodeManualSheet() async {
    final controller = TextEditingController();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.s16,
            right: AppSpacing.s16,
            top: AppSpacing.s16,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Barkod gir',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.s8),
              Text(
                'Web ortamında kameraya erişim olmadığı için barkodu manuel girebilirsiniz.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.s12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Barkod',
                  prefixIcon: Icon(Icons.qr_code_scanner),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: false),
                onSubmitted: (value) {
                  Navigator.of(context).pop(value.trim());
                },
              ),
              const SizedBox(height: AppSpacing.s16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Vazgeç'),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(controller.text.trim());
                    },
                    icon: const Icon(Icons.search),
                    label: const Text('Ara'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    final value = result?.trim();
    if (value == null || value.isEmpty) return;

    ref.read(_stockSearchProvider.notifier).state = value;
    ref.read(_stockPageProvider.notifier).state = 0;
  }

  Future<void> _openBarcodeScanner() async {
    if (kIsWeb) {
      await _openBarcodeManualSheet();
      return;
    }

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const BarcodeScannerPage()),
    );

    if (!mounted) return;
    final value = result?.trim();
    if (value == null || value.isEmpty) return;

    ref.read(_stockSearchProvider.notifier).state = value;
    ref.read(_stockPageProvider.notifier).state = 0;
  }

  bool _looksLikeBarcode(String input) {
    final trimmed = input.trim();
    if (trimmed.length < 8) return false;
    return RegExp(r'^[0-9]+$').hasMatch(trimmed);
  }

  Future<void> _applyBulkSetActive({
    required List<Stock> stocks,
    required Set<String> selectedIds,
    required bool isActive,
  }) async {
    if (selectedIds.isEmpty) return;
    setState(() => _bulkLoading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      for (final stock in stocks) {
        final id = stock.id;
        if (id == null || !selectedIds.contains(id)) continue;
        await stockRepository.updateStock(
          stock: stock.copyWith(isActive: isActive),
        );
      }

      final count = selectedIds.length;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$count stok ${isActive ? 'aktif' : 'pasif'} yapıldı',
          ),
        ),
      );

      // Seçimi temizle ama seçim modunu açık bırak.
      ref.read(_selectedStockIdsProvider.notifier).state = <String>{};
      ref.invalidate(stocksFutureProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Toplu işlem başarısız: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkLoading = false);
      }
    }
  }

  Future<void> _applyBulkDelete({
    required List<Stock> stocks,
    required Set<String> selectedIds,
  }) async {
    if (selectedIds.isEmpty) return;
    final count = selectedIds.length;

    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stoklar pasif yapılsın mı?'),
            content: Text(
              '$count stok pasif yapılacak. Devam etmek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Pasif yap'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _bulkLoading = true);

    try {
      for (final stock in stocks) {
        final id = stock.id;
        if (id == null || !selectedIds.contains(id)) continue;
        await stockRepository.deleteStock(id);
      }

      messenger.showSnackBar(
        SnackBar(content: Text('$count stok pasif yapıldı')),
      );

      ref.read(_selectedStockIdsProvider.notifier).state = <String>{};
      ref.invalidate(stocksFutureProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Toplu pasif yapma başarısız: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkLoading = false);
      }
    }
  }

  Future<void> _applyBulkDeletePermanently({
    required List<Stock> stocks,
    required Set<String> selectedIds,
  }) async {
    if (selectedIds.isEmpty) return;
    final count = selectedIds.length;

    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Stoklar kalıcı silinsin mi?'),
            content: Text(
              '$count stok kalıcı olarak silinecek. Bu işlem geri alınamaz. Devam etmek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Kalıcı sil'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _bulkLoading = true);

    try {
      for (final stock in stocks) {
        final id = stock.id;
        if (id == null || !selectedIds.contains(id)) continue;
        await stockRepository.deleteStockPermanently(id);
      }

      messenger.showSnackBar(
        SnackBar(content: Text('$count stok kalıcı olarak silindi')),
      );

      ref.read(_selectedStockIdsProvider.notifier).state = <String>{};
      ref.invalidate(stocksFutureProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Toplu kalıcı silme başarısız: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stocksAsync = ref.watch(stocksFutureProvider);
    final page = ref.watch(_stockPageProvider);
    final filter = ref.watch(_stockFilterProvider);
    final search = ref.watch(_stockSearchProvider);
    final extraFilters = ref.watch(_stockExtraFiltersProvider);
    final sortOption = ref.watch(_stockSortOptionProvider);
    final viewMode = ref.watch(_stockViewModeProvider);
    final selectionMode = ref.watch(_selectionModeProvider);
    final selectedIds = ref.watch(_selectedStockIdsProvider);
    final selectedCount = selectedIds.length;
    final stocksData = stocksAsync.asData?.value ?? const <Stock>[];
    const pageSize = 20;
    final hasNext = stocksData.length >= pageSize;

    final visibleCount = stocksData.length;
    final hasActiveFilters =
        filter != _StockFilter.all ||
        extraFilters.isNotEmpty ||
        search.trim().isNotEmpty;

    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    Future<void> refresh() async {
      ref.invalidate(stocksFutureProvider);
      try {
        await ref.read(stocksFutureProvider.future);
      } catch (_) {
        // Hata durumunda da pull-to-refresh akışı bozulmasın.
      }
    }

    final headerItem = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stok Bilgileri',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'Stok kartlarını listele ve düzenle',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s16),
        Row(
          children: [
            Expanded(
              child: AppSearchField(
                hintText: 'Ara (ad / kod / barkod)',
                padded: false,
                initialValue: search,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 350),
                    () {
                      ref.read(_stockSearchProvider.notifier).state = value;
                      ref.read(_stockPageProvider.notifier).state = 0;
                    },
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            IconButton(
              tooltip: 'Barkod tara',
              icon: const Icon(Icons.camera_alt),
              onPressed: _openBarcodeScanner,
            ),
          ],
        ),
        if (hasActiveFilters) ...[
          const SizedBox(height: AppSpacing.s8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Wrap(
                  spacing: AppSpacing.s8,
                  children: [
                    if (filter == _StockFilter.active)
                      InputChip(
                        label: const Text('Durum: Aktif'),
                        onDeleted: () {
                          ref.read(_stockFilterProvider.notifier).state =
                              _StockFilter.all;
                          ref.read(_stockPageProvider.notifier).state = 0;
                        },
                      ),
                    if (filter == _StockFilter.passive)
                      InputChip(
                        label: const Text('Durum: Pasif'),
                        onDeleted: () {
                          ref.read(_stockFilterProvider.notifier).state =
                              _StockFilter.all;
                          ref.read(_stockPageProvider.notifier).state = 0;
                        },
                      ),
                    if (search.trim().isNotEmpty)
                      InputChip(
                        label: Text('Arama: ${search.trim()}'),
                        onDeleted: () {
                          ref.read(_stockSearchProvider.notifier).state = '';
                          ref.read(_stockPageProvider.notifier).state = 0;
                        },
                      ),
                    if (extraFilters.contains(_StockExtraFilter.barcodeOnly))
                      InputChip(
                        label: const Text('Barkodlu'),
                        onDeleted: () {
                          final current = ref
                              .read(_stockExtraFiltersProvider.notifier)
                              .state;
                          final next = Set<_StockExtraFilter>.from(current)
                            ..remove(_StockExtraFilter.barcodeOnly);
                          ref
                              .read(_stockExtraFiltersProvider.notifier)
                              .state = next;
                          ref.read(_stockPageProvider.notifier).state = 0;
                        },
                      ),
                    if (extraFilters.contains(_StockExtraFilter.lowStock))
                      InputChip(
                        label: const Text('Stok az'),
                        onDeleted: () {
                          final current = ref
                              .read(_stockExtraFiltersProvider.notifier)
                              .state;
                          final next = Set<_StockExtraFilter>.from(current)
                            ..remove(_StockExtraFilter.lowStock);
                          ref
                              .read(_stockExtraFiltersProvider.notifier)
                              .state = next;
                          ref.read(_stockPageProvider.notifier).state = 0;
                        },
                      ),
                    if (extraFilters
                        .contains(_StockExtraFilter.withMultipliers))
                      InputChip(
                        label: const Text('Katsayılı'),
                        onDeleted: () {
                          final current = ref
                              .read(_stockExtraFiltersProvider.notifier)
                              .state;
                          final next = Set<_StockExtraFilter>.from(current)
                            ..remove(_StockExtraFilter.withMultipliers);
                          ref
                              .read(_stockExtraFiltersProvider.notifier)
                              .state = next;
                          ref.read(_stockPageProvider.notifier).state = 0;
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s4,
                children: [
                  ChoiceChip(
                    label: const Text('Aktif'),
                    selected: filter == _StockFilter.active,
                    onSelected: (_) {
                      ref.read(_stockFilterProvider.notifier).state =
                          _StockFilter.active;
                      ref.read(_stockPageProvider.notifier).state = 0;
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Pasif'),
                    selected: filter == _StockFilter.passive,
                    onSelected: (_) {
                      ref.read(_stockFilterProvider.notifier).state =
                          _StockFilter.passive;
                      ref.read(_stockPageProvider.notifier).state = 0;
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Tümü'),
                    selected: filter == _StockFilter.all,
                    onSelected: (_) {
                      ref.read(_stockFilterProvider.notifier).state =
                          _StockFilter.all;
                      ref.read(_stockPageProvider.notifier).state = 0;
                    },
                  ),
                ],
              ),
            ),
            if (hasActiveFilters) ...[
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s8,
                    vertical: AppSpacing.s4,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  ref.read(_stockSearchProvider.notifier).state = '';
                  ref.read(_stockFilterProvider.notifier).state =
                      _StockFilter.all;
                  ref.read(_stockExtraFiltersProvider.notifier).state =
                      <_StockExtraFilter>{};
                  ref.read(_stockPageProvider.notifier).state = 0;
                },
                child: const Text('Filtreleri Sıfırla'),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s4,
          children: [
            ChoiceChip(
              label: const Text('Barkodlu'),
              selected: extraFilters.contains(_StockExtraFilter.barcodeOnly),
              onSelected: (_) {
                final current =
                    ref.read(_stockExtraFiltersProvider.notifier).state;
                final next = current.contains(_StockExtraFilter.barcodeOnly)
                    ? (Set<_StockExtraFilter>.from(current)
                      ..remove(_StockExtraFilter.barcodeOnly))
                    : (Set<_StockExtraFilter>.from(current)
                      ..add(_StockExtraFilter.barcodeOnly));
                ref.read(_stockExtraFiltersProvider.notifier).state = next;
                ref.read(_stockPageProvider.notifier).state = 0;
              },
            ),
            ChoiceChip(
              label: const Text('Stok az'),
              selected: extraFilters.contains(_StockExtraFilter.lowStock),
              onSelected: (_) {
                final current =
                    ref.read(_stockExtraFiltersProvider.notifier).state;
                final next = current.contains(_StockExtraFilter.lowStock)
                    ? (Set<_StockExtraFilter>.from(current)
                      ..remove(_StockExtraFilter.lowStock))
                    : (Set<_StockExtraFilter>.from(current)
                      ..add(_StockExtraFilter.lowStock));
                ref.read(_stockExtraFiltersProvider.notifier).state = next;
                ref.read(_stockPageProvider.notifier).state = 0;
              },
            ),
            ChoiceChip(
              label: const Text('Katsayılı'),
              selected:
                  extraFilters.contains(_StockExtraFilter.withMultipliers),
              onSelected: (_) {
                final current =
                    ref.read(_stockExtraFiltersProvider.notifier).state;
                final next = current.contains(_StockExtraFilter.withMultipliers)
                    ? (Set<_StockExtraFilter>.from(current)
                      ..remove(_StockExtraFilter.withMultipliers))
                    : (Set<_StockExtraFilter>.from(current)
                      ..add(_StockExtraFilter.withMultipliers));
                ref.read(_stockExtraFiltersProvider.notifier).state = next;
                ref.read(_stockPageProvider.notifier).state = 0;
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;

            final summary = Builder(
              builder: (context) {
                final approxTotal = hasNext
                    ? '${visibleCount.toString()}+'
                    : visibleCount.toString();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toplam: $approxTotal',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Gösterilen: $visibleCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            );

            final controls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<_StockSortOption>(
                  value: sortOption,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(_stockSortOptionProvider.notifier).state =
                          value;
                      ref.read(_stockPageProvider.notifier).state = 0;
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: _StockSortOption.nameAsc,
                      child: Text('Ada göre'),
                    ),
                    DropdownMenuItem(
                      value: _StockSortOption.codeAsc,
                      child: Text('Koda göre'),
                    ),
                    DropdownMenuItem(
                      value: _StockSortOption.stockAscending,
                      child: Text('Stok azdan'),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.s8),
                ToggleButtons(
                  isSelected: [
                    viewMode == _StockViewMode.grouped,
                    viewMode == _StockViewMode.flat,
                  ],
                  onPressed: (index) {
                    ref.read(_stockViewModeProvider.notifier).state = index == 0
                        ? _StockViewMode.grouped
                        : _StockViewMode.flat;
                  },
                  borderRadius: BorderRadius.circular(20),
                  constraints: const BoxConstraints(minHeight: 36),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                      child: Text('Gruplu'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                      child: Text('Düz liste'),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.s8),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: page > 0
                      ? () {
                          ref.read(_stockPageProvider.notifier).state =
                              page - 1;
                        }
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: hasNext
                      ? () {
                          ref.read(_stockPageProvider.notifier).state =
                              page + 1;
                        }
                      : null,
                ),
              ],
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: AppSpacing.s8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: controls,
                  ),
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                summary,
                controls,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s8),
      ],
    );

    final listItems = <Widget>[headerItem];

    if (!isKeyboardOpen) {
      final contentItems = stocksAsync.when(
        loading: () => const <Widget>[
          _StockListLoadingSkeleton(),
        ],
        error: (e, _) => <Widget>[
          AppErrorState(
            message: 'Stoklar yüklenemedi',
            onRetry: () => ref.invalidate(stocksFutureProvider),
          ),
        ],
        data: (stocks) {
          if (stocks.isEmpty) {
            // Arama veya ek filtre varsa "sonuç yok" kabul et
            final hasFilter = search.trim().isNotEmpty || extraFilters.isNotEmpty;

            if (hasFilter) {
              return <Widget>[
                AppEmptyState(
                  title: 'Sonuç bulunamadı',
                  subtitle: 'Filtreleri sıfırlayıp tekrar deneyin.',
                  action: TextButton(
                    onPressed: () {
                      ref.read(_stockSearchProvider.notifier).state = '';
                      ref.read(_stockFilterProvider.notifier).state =
                          _StockFilter.all;
                      ref.read(_stockExtraFiltersProvider.notifier).state =
                          <_StockExtraFilter>{};
                      ref.read(_stockPageProvider.notifier).state = 0;
                    },
                    child: const Text('Filtreleri Sıfırla'),
                  ),
                ),
              ];
            }

            return <Widget>[
              AppEmptyState(
                title: 'Kayıt bulunamadı',
                subtitle:
                    'Yeni stok ekleyerek listeyi oluşturmaya başlayabilirsiniz.',
                action: PrimaryButton(
                  label: 'Yeni Stok',
                  icon: Icons.add,
                  onPressed: () => GoRouter.of(context).go('/stocks/new'),
                ),
              ),
            ];
          }

          // Barkod gibi görünen aramada tek sonuç varsa detay aç.
          if (_looksLikeBarcode(search) && stocks.length == 1) {
            if (_lastSingleResultSearch != search) {
              _lastSingleResultSearch = search;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => _StockDetailSheet(stock: stocks.first),
                );
              });
            }
          } else {
            _lastSingleResultSearch = null;
          }

          final effectiveSelectedIds = selectedIds;
          final children = <Widget>[];

          if (selectionMode) {
            children.add(
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      final ids = <String>{};
                      for (final s in stocks) {
                        if (s.id != null) {
                          ids.add(s.id!);
                        }
                      }
                      ref.read(_selectedStockIdsProvider.notifier).state = ids;
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                    ),
                    child: const Text('Tümünü seç'),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  TextButton(
                    onPressed: () {
                      ref.read(_selectedStockIdsProvider.notifier).state =
                          <String>{};
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                    ),
                    child: const Text('Seçimi temizle'),
                  ),
                ],
              ),
            );
            children.add(const SizedBox(height: AppSpacing.s8));
          }

          List<Widget> buildFlatList() {
            return [
              for (final stock in stocks)
                Builder(
                  builder: (context) {
                    final id = stock.id;
                    final isSelected =
                        id != null && effectiveSelectedIds.contains(id);
                    return _StockListRow(
                      stock: stock,
                      selectionMode: selectionMode,
                      selected: isSelected,
                      onSelectedChanged: (checked) {
                        if (id == null) return;
                        final notifier =
                            ref.read(_selectedStockIdsProvider.notifier);
                        final current = Set<String>.from(notifier.state);
                        if (checked == true) {
                          current.add(id);
                        } else {
                          current.remove(id);
                        }
                        notifier.state = current;
                      },
                      onEdited: () {
                        ref.invalidate(stocksFutureProvider);
                      },
                    );
                  },
                ),
            ];
          }

          List<Widget> buildGroupedList() {
            final groups = <String, Map<String, Map<String, List<Stock>>>>{};

            String normGroup(String? value) =>
                (value == null || value.trim().isEmpty) ? 'Grupsuz' : value.trim();
            String normSub(String? value) =>
                (value == null || value.trim().isEmpty) ? 'Diğer' : value.trim();

            for (final stock in stocks) {
              final g = normGroup(stock.groupName);
              final sg = normSub(stock.subgroupName);
              final ssg = normSub(stock.subsubgroupName);

              groups.putIfAbsent(
                g,
                () => <String, Map<String, List<Stock>>>{},
              );
              final subMap = groups[g]!;
              subMap.putIfAbsent(sg, () => <String, List<Stock>>{});
              final subsubMap = subMap[sg]!;
              subsubMap.putIfAbsent(ssg, () => <Stock>[]);
              subsubMap[ssg]!.add(stock);
            }

            final groupKeys = groups.keys.toList()..sort();

            final listChildren = <Widget>[];

            for (final g in groupKeys) {
              final subMap = groups[g]!;
              final subKeys = subMap.keys.toList()..sort();

              listChildren.add(
                ExpansionTile(
                  title: Text(g),
                  children: [
                    for (final sg in subKeys)
                      Builder(
                        builder: (context) {
                          final subsubMap = subMap[sg]!;
                          final subsubKeys = subsubMap.keys.toList()..sort();

                          return ExpansionTile(
                            title: Text(sg),
                            children: [
                              for (final ssg in subsubKeys)
                                Builder(
                                  builder: (context) {
                                    final leafStocks = subsubMap[ssg]!;
                                    return ExpansionTile(
                                      title: Text(ssg),
                                      children: [
                                        for (final stock in leafStocks)
                                          Builder(
                                            builder: (context) {
                                              final id = stock.id;
                                              final isSelected = id != null &&
                                                  effectiveSelectedIds.contains(id);
                                              return _StockListRow(
                                                stock: stock,
                                                selectionMode: selectionMode,
                                                selected: isSelected,
                                                onSelectedChanged: (checked) {
                                                  if (id == null) {
                                                    return;
                                                  }
                                                  final notifier = ref.read(
                                                    _selectedStockIdsProvider
                                                        .notifier,
                                                  );
                                                  final current =
                                                      Set<String>.from(notifier.state);
                                                  if (checked == true) {
                                                    current.add(id);
                                                  } else {
                                                    current.remove(id);
                                                  }
                                                  notifier.state = current;
                                                },
                                                onEdited: () {
                                                  ref.invalidate(
                                                    stocksFutureProvider,
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                      ],
                                    );
                                  },
                                ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              );
            }

            return listChildren;
          }

          if (search.trim().isNotEmpty || viewMode == _StockViewMode.flat) {
            children.addAll(buildFlatList());
          } else {
            children.addAll(buildGroupedList());
          }

          return children;
        },
      );

      listItems.addAll(contentItems);
    }

    return AppScaffold(
      title: selectionMode && selectedCount > 0
          ? 'Stok Bilgileri ($selectedCount seçili)'
          : 'Stok Bilgileri',
      resizeToAvoidBottomInset: false,
      actions: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: () {
            ref.invalidate(stocksFutureProvider);
          },
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'İpucu: filtreleri kullan',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Listeyi daraltmak için filtre ve aramayı kullanın.'),
              ),
            );
          },
          icon: const Icon(Icons.help_outline),
        ),
        IconButton(
          tooltip: 'Toplu seçim',
          onPressed: () {
            final current =
                ref.read(_selectionModeProvider.notifier).state;
            if (current) {
              ref
                  .read(_selectedStockIdsProvider.notifier)
                  .state = <String>{};
              ref.read(_selectionModeProvider.notifier).state = false;
            } else {
              ref.read(_selectionModeProvider.notifier).state = true;
            }
          },
          icon: Icon(
            selectionMode
                ? Icons.check_box
                : Icons.check_box_outline_blank,
          ),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => GoRouter.of(context).go('/stocks/new'),
        child: const Icon(Icons.add),
      ),
      bottom: selectionMode && selectedCount > 0
          ? _BulkActionBar(
              selectedCount: selectedCount,
              loading: _bulkLoading,
              onSetActive: () => _applyBulkSetActive(
                stocks: stocksData,
                selectedIds: selectedIds,
                isActive: true,
              ),
              onSetPassive: () => _applyBulkSetActive(
                stocks: stocksData,
                selectedIds: selectedIds,
                isActive: false,
              ),
              onDelete: () => _applyBulkDelete(
                stocks: stocksData,
                selectedIds: selectedIds,
              ),
              onDeletePermanent: () => _applyBulkDeletePermanently(
                stocks: stocksData,
                selectedIds: selectedIds,
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: listItems.length,
          itemBuilder: (context, index) => listItems[index],
        ),
      ),
    );
  }
}

enum _StockFilter { all, active, passive }

class _StockListRow extends StatelessWidget {
  const _StockListRow({
    required this.stock,
    required this.selectionMode,
    required this.selected,
    required this.onSelectedChanged,
    this.onEdited,
  });

  final Stock stock;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool?> onSelectedChanged;
  final VoidCallback? onEdited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imagePath = stock.imagePath;
    String? imageUrl;
    if (imagePath != null && imagePath.isNotEmpty) {
      imageUrl = supabaseClient
          .storage
          .from(kStockImagesBucketId)
          .getPublicUrl(imagePath);
    }

    final code = stock.code;
    final barcode = stock.barcode;
    final hasBarcode = barcode != null && barcode.isNotEmpty;
    final quantity = stock.quantity ?? 0;
    final isLowStock = quantity <= 5;

    final subtitleText = StringBuffer()
      ..write('KOD: ')
      ..write(code)
      ..write(' • Barkod: ')
      ..write(hasBarcode ? barcode : '—');

    Future<void> toggleActive(BuildContext context) async {
      if (stock.id == null) return;
      final messenger = ScaffoldMessenger.of(context);
      final newValue = !stock.isActive;
      try {
        await stockRepository.updateStock(
          stock: stock.copyWith(isActive: newValue),
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(newValue ? 'Aktif yapıldı' : 'Pasif yapıldı'),
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Durum güncellenemedi: $e')),
        );
      }
    }

    void copyToClipboard(BuildContext context, String label, String value) {
      Clipboard.setData(ClipboardData(text: value));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label kopyalandı')),
      );
    }

    Future<void> deleteStock(BuildContext context) async {
      if (stock.id == null) return;
      final messenger = ScaffoldMessenger.of(context);
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Stok kalıcı silinsin mi?'),
              content: Text(
                '"${stock.name}" stoğu kalıcı olarak silinecek. Bu işlem geri alınamaz. Devam etmek istiyor musunuz?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Kalıcı sil'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;
      try {
        await stockRepository.deleteStockPermanently(stock.id!);
        messenger.showSnackBar(
          const SnackBar(content: Text('Stok kalıcı olarak silindi')),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Stok silinemedi: $e')),
        );
      }
    }

    void openDetail(BuildContext context) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return _StockDetailSheet(stock: stock);
        },
      );
    }
    final isActive = stock.isActive;
    final statusChip = isActive
        ? const AppStatusChip.active()
        : const AppStatusChip.inactive();

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (selectionMode) {
            onSelectedChanged(!selected);
          } else {
            openDetail(context);
          }
        },
        child: Stack(
          children: [
            if (isLowStock)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  color: colorScheme.error.withValues(alpha: 0.7),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 600;

                  final leading = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectionMode)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.s8),
                          child: Checkbox(
                            value: selected,
                            onChanged: (value) => onSelectedChanged(value),
                          ),
                        ),
                      if (imageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.inventory_2_outlined),
                        ),
                    ],
                  );

                  final titleColumn = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stock.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        subtitleText.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Wrap(
                        spacing: AppSpacing.s4,
                        runSpacing: AppSpacing.s4,
                        children: [
                          if (stock.packBarcode != null &&
                              stock.packBarcode!.isNotEmpty)
                            const Chip(
                              label: Text('Paket'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          if (stock.boxBarcode != null &&
                              stock.boxBarcode!.isNotEmpty)
                            const Chip(
                              label: Text('Koli'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          if (isLowStock)
                            Chip(
                              label: const Text('Stok az'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              avatar: Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ],
                  );

                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Düzenle',
                        onPressed: selectionMode
                            ? null
                            : () async {
                                if (stock.id == null) return;
                                final result = await GoRouter.of(context)
                                    .push<bool>('/stocks/${stock.id}/edit');
                                if (result == true) {
                                  onEdited?.call();
                                }
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune),
                        tooltip: 'Hızlı düzenle',
                        onPressed:
                            selectionMode ? null : () => openDetail(context),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Daha fazla',
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'copyCode',
                            child: Text('Kodu kopyala'),
                          ),
                          PopupMenuItem(
                            value: 'copyBarcode',
                            enabled: hasBarcode,
                            child: const Text('Barkodu kopyala'),
                          ),
                          const PopupMenuItem(
                            value: 'detail',
                            child: Text('Detay gör'),
                          ),
                          PopupMenuItem(
                            value: 'toggleActive',
                            child: Text(
                              stock.isActive ? 'Pasif yap' : 'Aktif yap',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Sil'),
                          ),
                        ],
                        onSelected: (value) {
                          switch (value) {
                            case 'copyCode':
                              copyToClipboard(context, 'Kod', code);
                              break;
                            case 'copyBarcode':
                              if (hasBarcode) {
                                copyToClipboard(context, 'Barkod', barcode);
                              }
                              break;
                            case 'toggleActive':
                              toggleActive(context);
                              break;
                            case 'detail':
                              openDetail(context);
                              break;
                            case 'delete':
                              deleteStock(context);
                              break;
                          }
                        },
                      ),
                    ],
                  );

                  final infoWrap = Wrap(
                    spacing: AppSpacing.s12,
                    runSpacing: AppSpacing.s8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      statusChip,
                      Text(
                        'Stok: ${quantity.toStringAsFixed(0)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isLowStock
                              ? colorScheme.error
                              : theme.textTheme.bodySmall?.color,
                        ),
                      ),
                      if (stock.salePrice1 != null)
                        Text(
                          'Fiyat: ${formatMoney(stock.salePrice1)}',
                          style: theme.textTheme.bodySmall,
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
                            leading,
                            const SizedBox(width: AppSpacing.s12),
                            Expanded(child: titleColumn),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.s12),
                        infoWrap,
                        const SizedBox(height: AppSpacing.s8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: actions,
                        ),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leading,
                      const SizedBox(width: AppSpacing.s12),
                      Expanded(child: titleColumn),
                      const SizedBox(width: AppSpacing.s12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          statusChip,
                          const SizedBox(height: AppSpacing.s8),
                          Text(
                            'Stok: ${quantity.toStringAsFixed(0)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isLowStock
                                  ? colorScheme.error
                                  : theme.textTheme.bodySmall?.color,
                            ),
                          ),
                          if (stock.salePrice1 != null) ...[
                            const SizedBox(height: AppSpacing.s4),
                            Text(
                              'Fiyat: ${formatMoney(stock.salePrice1)}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.s8),
                          actions,
                        ],
                      ),
                    ],
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

class _StockListLoadingSkeleton extends StatelessWidget {
  const _StockListLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.surfaceContainerHighest;

    final children = <Widget>[];
    for (var i = 0; i < 8; i++) {
      children.add(
        Card(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s12),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Container(
                        height: 10,
                        width: MediaQuery.of(context).size.width * 0.4,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (i != 7) {
        children.add(const SizedBox(height: AppSpacing.s4));
      }
    }

    return Column(children: children);
  }
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.selectedCount,
    required this.loading,
    required this.onSetActive,
    required this.onSetPassive,
    required this.onDelete,
    required this.onDeletePermanent,
  });

  final int selectedCount;
  final bool loading;
  final VoidCallback onSetActive;
  final VoidCallback onSetPassive;
  final VoidCallback onDelete;
  final VoidCallback onDeletePermanent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$selectedCount ürün seçili',
              style: textTheme.bodyMedium,
            ),
            Row(
              children: [
                TextButton(
                  onPressed: loading ? null : onSetActive,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                    ),
                  ),
                  child: const Text('Aktif yap'),
                ),
                const SizedBox(width: AppSpacing.s8),
                TextButton(
                  onPressed: loading ? null : onSetPassive,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                    ),
                  ),
                  child: const Text('Pasif yap'),
                ),
                const SizedBox(width: AppSpacing.s8),
                TextButton(
                  onPressed: loading ? null : onDelete,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                    ),
                  ),
                  child: const Text('Pasif yap (seçili)'),
                ),
                const SizedBox(width: AppSpacing.s8),
                TextButton(
                  onPressed: loading ? null : onDeletePermanent,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                    ),
                  ),
                  child: const Text('Kalıcı sil (seçili)'),
                ),
                if (loading) ...[
                  const SizedBox(width: AppSpacing.s8),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StockDetailSheet extends StatelessWidget {
  const _StockDetailSheet({
    required this.stock,
  });

  final Stock stock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      stock.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              Text('Kod: ${stock.code}'),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'Barkod: ${stock.barcode != null && stock.barcode!.isNotEmpty ? stock.barcode : 'Barkod yok'}',
              ),
              const SizedBox(height: AppSpacing.s8),
              FutureBuilder<List<StockUnit>>(
                future: stock.id == null
                    ? Future.value(<StockUnit>[])
                    : stockRepository.fetchStockUnits(stock.id!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.s8),
                      child: LinearProgressIndicator(minHeight: 2),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final unit = snapshot.data!.first;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Birim: Adet'),
                      const SizedBox(height: AppSpacing.s4),
                      Text('Paket katsayısı: ${unit.packContainsPiece ?? 1}'),
                      const SizedBox(height: AppSpacing.s4),
                      Text('Koli katsayısı: ${unit.caseContainsPiece ?? 1}'),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                  );
                },
              ),
              Text(
                'Satış fiyatları',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
        Text(
        'Fiyat 1: '
        '${stock.salePrice1 == null ? '-' : formatMoney(stock.salePrice1)}',
        ),
              const SizedBox(height: AppSpacing.s4),
              Text(
              'Fiyat 2: '
              '${stock.salePrice2 == null ? '-' : formatMoney(stock.salePrice2)}',
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
              'Fiyat 3: '
              '${stock.salePrice3 == null ? '-' : formatMoney(stock.salePrice3)}',
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
              'Fiyat 4: '
              '${stock.salePrice4 == null ? '-' : formatMoney(stock.salePrice4)}',
              ),
              const SizedBox(height: AppSpacing.s8),
              Row(
                children: [
                  stock.isActive
                      ? const AppStatusChip.active()
                      : const AppStatusChip.inactive(),
                ],
              ),
              const SizedBox(height: AppSpacing.s16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: stock.name));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ad kopyalandı')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Kopyala'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        if (stock.id == null) return;
                        Navigator.of(context).pop();
                        GoRouter.of(context)
                            .go('/stocks/${stock.id}/edit');
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Düzenle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

