import 'dart:async';

import 'package:core/core.dart' as core;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../customers/customer_finance_providers.dart' as finance;
import 'return_strings.dart';

enum ReturnGrouping {
  none,
  byProduct,
  byCategory,
  byCustomer,
}

extension ReturnGroupingX on ReturnGrouping {
  String get labelTr {
    switch (this) {
      case ReturnGrouping.none:
        return ReturnStrings.groupingNone;
      case ReturnGrouping.byProduct:
        return ReturnStrings.groupingByProduct;
      case ReturnGrouping.byCategory:
        return ReturnStrings.groupingByCategory;
      case ReturnGrouping.byCustomer:
        return ReturnStrings.groupingByCustomer;
    }
  }
}

@immutable
class ReturnLineDraft {
  const ReturnLineDraft({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.note,
  });

  final String id;
  final core.CustomerProduct product;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String? note;

  double get lineTotal => quantity * unitPrice;

  ReturnLineDraft copyWith({
    core.CustomerProduct? product,
    double? quantity,
    String? unit,
    double? unitPrice,
    String? note,
  }) {
    return ReturnLineDraft(
      id: id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      note: note,
    );
  }
}

@immutable
class ReturnCreateState {
  const ReturnCreateState({
    this.customerSearch = '',
    this.selectedCustomer,
    this.selectedGroupName,
    this.productSearch = '',
    this.debouncedProductSearch = '',
    this.selectedProduct,
    this.grouping = ReturnGrouping.none,
    this.lines = const <ReturnLineDraft>[],
    this.saveState = const AsyncData<void>(null),
    this.saveProgress,
  });

  final String customerSearch;
  final core.Customer? selectedCustomer;

  /// Ürün grubu/kategori filtresi. `null` => tümü.
  final String? selectedGroupName;

  /// Ürün listesi için client-side arama.
  final String productSearch;

  /// Ürün listesi için debounce'lu arama (server-side fetch tetikler).
  final String debouncedProductSearch;
  final core.CustomerProduct? selectedProduct;

  final ReturnGrouping grouping;
  final List<ReturnLineDraft> lines;

  /// Kaydetme akışı (loading/success/error) UI için.
  final AsyncValue<void> saveState;

  /// Çoklu satır kaydında ilerleme göstermek için.
  /// (savedCount, total)
  final (int savedCount, int total)? saveProgress;

  int get lineCount => lines.length;

  int get uniqueProductCount =>
      lines.map((e) => e.product.stockId).toSet().length;

  double get totalQty => lines.fold<double>(0, (sum, e) => sum + e.quantity);

  double get totalAmount =>
      lines.fold<double>(0, (sum, e) => sum + e.lineTotal);

  int get noteCount =>
      lines.where((e) => (e.note ?? '').trim().isNotEmpty).length;

  bool get canSave =>
      selectedCustomer != null && lines.isNotEmpty && !saveState.isLoading;

  ReturnCreateState copyWith({
    String? customerSearch,
    core.Customer? selectedCustomer,
    bool clearSelectedCustomer = false,
    String? selectedGroupName,
    bool clearSelectedGroupName = false,
    String? productSearch,
    String? debouncedProductSearch,
    core.CustomerProduct? selectedProduct,
    bool clearSelectedProduct = false,
    ReturnGrouping? grouping,
    List<ReturnLineDraft>? lines,
    AsyncValue<void>? saveState,
    (int savedCount, int total)? saveProgress,
    bool clearSaveProgress = false,
  }) {
    return ReturnCreateState(
      customerSearch: customerSearch ?? this.customerSearch,
      selectedCustomer: clearSelectedCustomer
          ? null
          : (selectedCustomer ?? this.selectedCustomer),
      selectedGroupName: clearSelectedGroupName
          ? null
          : (selectedGroupName ?? this.selectedGroupName),
      productSearch: productSearch ?? this.productSearch,
      debouncedProductSearch:
          debouncedProductSearch ?? this.debouncedProductSearch,
      selectedProduct: clearSelectedProduct
          ? null
          : (selectedProduct ?? this.selectedProduct),
      grouping: grouping ?? this.grouping,
      lines: lines ?? this.lines,
      saveState: saveState ?? this.saveState,
      saveProgress:
          clearSaveProgress ? null : (saveProgress ?? this.saveProgress),
    );
  }
}

final returnCreateControllerProvider = StateNotifierProvider.autoDispose<
    ReturnCreateController, ReturnCreateState>(
  (ref) => ReturnCreateController(ref),
);

class ReturnCreateController extends StateNotifier<ReturnCreateState> {
  ReturnCreateController(this._ref) : super(const ReturnCreateState());

  final Ref _ref;
  Timer? _productSearchDebounce;

  @override
  void dispose() {
    _productSearchDebounce?.cancel();
    super.dispose();
  }

  void setCustomerSearch(String value) {
    state = state.copyWith(customerSearch: value);
  }

  void selectCustomer(core.Customer customer) {
    state = state.copyWith(
      selectedCustomer: customer,
      clearSelectedGroupName: true,
      productSearch: '',
      debouncedProductSearch: '',
      clearSelectedProduct: true,
      lines: const <ReturnLineDraft>[],
      saveState: const AsyncData<void>(null),
      clearSaveProgress: true,
    );
  }

  void clearCustomer() {
    state = state.copyWith(
      clearSelectedCustomer: true,
      clearSelectedGroupName: true,
      productSearch: '',
      debouncedProductSearch: '',
      clearSelectedProduct: true,
      lines: const <ReturnLineDraft>[],
      saveState: const AsyncData<void>(null),
      clearSaveProgress: true,
    );
  }

  /// Tam temizle: cari araması dahil tüm taslağı sıfırlar.
  void clearAll() {
    state = const ReturnCreateState();
  }

  Future<void> prefillCustomerById(String customerId) async {
    final trimmedId = customerId.trim();
    if (trimmedId.isEmpty) return;

    // Kullanıcı zaten bir cari seçtiyse, otomatik prefill ile override etme.
    final alreadySelected = state.selectedCustomer;
    if (alreadySelected != null) {
      if (alreadySelected.id == trimmedId) {
        return;
      }
      return;
    }

    final customer = await core.customerRepository.fetchCustomerById(trimmedId);
    if (customer == null) return;
    if (!mounted) return;

    selectCustomer(customer);
  }

  /// Taslağı sıfırlar: cari kalsın, satırlar ve ürün seçimi temizlensin.
  void resetDraft() {
    state = state.copyWith(
      clearSelectedGroupName: true,
      productSearch: '',
      debouncedProductSearch: '',
      clearSelectedProduct: true,
      lines: const <ReturnLineDraft>[],
      grouping: ReturnGrouping.none,
      saveState: const AsyncData<void>(null),
      clearSaveProgress: true,
    );
  }

  void setSelectedGroupName(String? value) {
    final v = value?.trim();
    state = state.copyWith(
      selectedGroupName: (v == null || v.isEmpty) ? null : v,
      clearSelectedProduct: true,
    );
  }

  void setProductSearch(String value) {
    final next = value;
    state = state.copyWith(productSearch: next);

    _productSearchDebounce?.cancel();
    final trimmed = next.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(debouncedProductSearch: '');
      return;
    }

    // 1 karakterlik aramada server-side fetch tetikleme.
    if (trimmed.length < 2) {
      if (state.debouncedProductSearch.isNotEmpty) {
        state = state.copyWith(debouncedProductSearch: '');
      }
      return;
    }

    _productSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final latest = state.productSearch.trim();
      state = state.copyWith(debouncedProductSearch: latest);
    });
  }

  void selectProduct(core.CustomerProduct product) {
    state = state.copyWith(selectedProduct: product);
  }

  void clearSelectedProduct() {
    state = state.copyWith(clearSelectedProduct: true);
  }

  String _defaultUnitForProduct(core.CustomerProduct product) {
    final rawUnitName = product.baseUnitName.trim();
    final normalized = rawUnitName.toLowerCase();
    if (normalized.contains('adet')) return ReturnStrings.unitPiece;
    if (normalized.contains('koli')) return ReturnStrings.unitBox;
    if (normalized.contains('paket')) return ReturnStrings.unitPack;
    return ReturnStrings.unitPiece;
  }

  double _defaultUnitPriceForProduct(core.CustomerProduct product) {
    final price = (product.effectivePrice ?? product.baseUnitPrice);
    if (price.isNaN || price.isInfinite) return 0;
    return price;
  }

  Future<core.CustomerProduct?> _fetchCustomerProductByStockId({
    required String customerId,
    required String stockId,
  }) async {
    final cId = customerId.trim();
    final sId = stockId.trim();
    if (cId.isEmpty || sId.isEmpty) return null;

    Future<core.CustomerProduct?> tryQuery(String column) async {
      final dynamic data = await core.supabaseClient
          .from('v_customer_stock_prices')
          .select(
            'stock_id, id, name, code, barcode, brand, image_path, '
            'unit, unit_price, base_unit_price, '
            'tax_rate, base_unit_name, pack_unit_name, pack_multiplier, '
            'box_unit_name, box_multiplier, '
            'barcode_text, group_name, subgroup_name, subsubgroup_name, is_active',
          )
          .eq('is_active', true)
          .eq('customer_id', cId)
          .eq(column, sId)
          .maybeSingle();

      if (data == null) return null;
      if (data is! Map) return null;
      return core.CustomerProduct.fromMap(Map<String, dynamic>.from(data));
    }

    // View versiyonlarına göre stok id'si `stock_id` veya `id` üzerinden tutuluyor olabilir.
    return await tryQuery('stock_id') ?? await tryQuery('id');
  }

  Future<core.CustomerProduct?> _fetchCustomerProductByBarcodeExact({
    required String customerId,
    required String barcode,
  }) async {
    final cId = customerId.trim();
    final code = barcode.trim();
    if (cId.isEmpty || code.isEmpty) return null;

    final dynamic data = await core.supabaseClient
        .from('v_customer_stock_prices')
        .select(
          'stock_id, id, name, code, barcode, brand, image_path, '
          'unit, unit_price, base_unit_price, '
          'tax_rate, base_unit_name, pack_unit_name, pack_multiplier, '
          'box_unit_name, box_multiplier, '
          'barcode_text, group_name, subgroup_name, subsubgroup_name, is_active',
        )
        .eq('is_active', true)
        .eq('customer_id', cId)
        .or('barcode.eq.$code,pack_barcode.eq.$code,box_barcode.eq.$code')
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    if (data is! Map) return null;
    return core.CustomerProduct.fromMap(Map<String, dynamic>.from(data));
  }

  Future<bool> prefillProductById(String productId) async {
    final trimmed = productId.trim();
    if (trimmed.isEmpty) return false;

    final customer = state.selectedCustomer;
    if (customer == null) {
      setProductSearch(trimmed);
      return false;
    }

    final product = await _fetchCustomerProductByStockId(
      customerId: customer.id,
      stockId: trimmed,
    );
    if (product == null) return false;
    if (!mounted) return false;

    addLine(
      product: product,
      quantity: 1,
      unit: _defaultUnitForProduct(product),
      unitPrice: _defaultUnitPriceForProduct(product),
    );

    state = state.copyWith(
      productSearch: '',
      debouncedProductSearch: '',
      clearSelectedProduct: true,
    );
    return true;
  }

  Future<bool> prefillByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length < 6) return false;

    final customer = state.selectedCustomer;
    if (customer == null) {
      setProductSearch(trimmed);
      return false;
    }

    final exact = await _fetchCustomerProductByBarcodeExact(
      customerId: customer.id,
      barcode: trimmed,
    );

    final products = exact == null
        ? await core.customerProductRepository.fetchProducts(
            customerId: customer.id,
            page: 0,
            pageSize: 10,
            search: trimmed,
            groupName: state.selectedGroupName,
          )
        : <core.CustomerProduct>[exact];

    final product = products.isEmpty ? null : products.first;
    if (product == null) return false;
    if (!mounted) return false;

    final merged = _tryIncrementExistingProduct(
      stockId: product.stockId,
      delta: 1,
      noteIfEmpty: ReturnStrings.noteFromBarcode(trimmed),
    );

    if (!merged) {
      addLine(
        product: product,
        quantity: 1,
        unit: _defaultUnitForProduct(product),
        unitPrice: _defaultUnitPriceForProduct(product),
        note: ReturnStrings.noteFromBarcode(trimmed),
      );
    }

    state = state.copyWith(
      productSearch: '',
      debouncedProductSearch: '',
      clearSelectedProduct: true,
    );
    return true;
  }

  bool _tryIncrementExistingProduct({
    required String stockId,
    required double delta,
    String? noteIfEmpty,
  }) {
    if (delta == 0) return false;
    final idx = state.lines.indexWhere((e) => e.product.stockId == stockId);
    if (idx < 0) return false;
    final existing = state.lines[idx];

    final nextQty = existing.quantity + delta;
    final nextNote = () {
      final current = (existing.note ?? '').trim();
      if (current.isNotEmpty) return existing.note;
      final replacement = (noteIfEmpty ?? '').trim();
      return replacement.isEmpty ? existing.note : replacement;
    }();

    updateLine(
      existing.id,
      quantity: nextQty,
      unit: existing.unit,
      unitPrice: existing.unitPrice,
      note: nextNote,
    );
    return true;
  }

  void setGrouping(ReturnGrouping grouping) {
    state = state.copyWith(grouping: grouping);
  }

  void addLine({
    required core.CustomerProduct product,
    required double quantity,
    required String unit,
    required double unitPrice,
    String? note,
  }) {
    final normalizedUnit = unit.trim();
    final trimmedNote = note?.trim();
    final safeNote =
        (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote;

    final draft = ReturnLineDraft(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      product: product,
      quantity: quantity,
      unit: normalizedUnit,
      unitPrice: unitPrice,
      note: safeNote,
    );

    state = state.copyWith(lines: [...state.lines, draft]);
  }

  void updateLine(
    String id, {
    required double quantity,
    required String unit,
    required double unitPrice,
    String? note,
  }) {
    final next = state.lines.map((e) {
      if (e.id != id) return e;
      return e.copyWith(
        quantity: quantity,
        unit: unit.trim(),
        unitPrice: unitPrice,
        note: () {
          final trimmed = note?.trim();
          return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
        }(),
      );
    }).toList(growable: false);
    state = state.copyWith(lines: next);
  }

  void removeLine(String id) {
    state = state.copyWith(
      lines: state.lines.where((e) => e.id != id).toList(growable: false),
    );
  }

  Future<void> saveAllLines() async {
    final customer = state.selectedCustomer;
    if (customer == null) return;
    final lines = state.lines;
    if (lines.isEmpty) return;
    if (state.saveState.isLoading) return;

    final repo = _ref.read(finance.manualRefundRepositoryProvider);

    state = state.copyWith(
      saveState: const AsyncLoading<void>(),
      saveProgress: (0, lines.length),
    );

    final result = await AsyncValue.guard(() async {
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];

        await repo.createManualRefund(
          customerId: customer.id,
          quantity: line.quantity,
          unit: line.unit,
          unitPrice: line.unitPrice,
          note: line.note,
        );

        state = state.copyWith(saveProgress: (i + 1, lines.length));
      }
    });

    // Controller dispose edilmiş olabilir.
    if (!mounted) return;

    state = state.copyWith(saveState: result);

    if (kDebugMode && result.hasError) {
      debugPrint(
        '[ReturnCreateController.saveAllLines] error=${result.error}',
      );
    }
  }
}

final returnCustomersProvider =
    FutureProvider.autoDispose<List<core.Customer>>((ref) async {
  final search = ref.watch(
    returnCreateControllerProvider.select((s) => s.customerSearch),
  );

  return core.customerRepository.fetchCustomers(
    search: search.trim().isEmpty ? null : search.trim(),
    isActive: true,
    limit: 50,
  );
});

class ReturnProductsQuery {
  const ReturnProductsQuery({
    required this.customerId,
    required this.groupName,
    required this.search,
  });

  final String customerId;
  final String? groupName;
  final String search;

  @override
  bool operator ==(Object other) {
    return other is ReturnProductsQuery &&
        other.customerId == customerId &&
        other.groupName == groupName &&
        other.search == search;
  }

  @override
  int get hashCode => Object.hash(customerId, groupName, search);
}

final returnGroupNamesProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, customerId) {
  return core.customerProductRepository.fetchGroupNames(customerId: customerId);
});

final returnProductsProvider = FutureProvider.autoDispose
    .family<List<core.CustomerProduct>, ReturnProductsQuery>((ref, query) {
  return core.customerProductRepository.fetchProducts(
    customerId: query.customerId,
    page: 0,
    pageSize: 80,
    groupName: query.groupName,
    search: query.search.trim().isEmpty ? null : query.search.trim(),
  );
});
