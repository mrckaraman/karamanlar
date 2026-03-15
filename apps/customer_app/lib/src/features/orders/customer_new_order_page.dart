import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../widgets/stock_image_thumbnail.dart';
import '../../../core/crashlytics/crash_logger.dart';

class UserFacingException implements Exception {
  UserFacingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ValidatedAdd {
  const _ValidatedAdd({
    required this.unitPrice,
    required this.unitName,
    required this.qty,
  });

  final double unitPrice;
  final String unitName;
  final int qty;
}

final _productSearchProvider = StateProvider<String>((ref) => '');

final _selectedGroupNameProvider = StateProvider<String?>((ref) => null);

final _groupNamesFutureProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final customerId = ref.watch(customerIdProvider);
  if (customerId == null || customerId.isEmpty) {
    return <String>[];
  }

  return customerProductRepository.fetchGroupNames(customerId: customerId);
});

final _productsFutureProvider =
    FutureProvider.autoDispose<List<CustomerProduct>>((ref) async {
  final search = ref.watch(_productSearchProvider).trim();
  final groupName = ref.watch(_selectedGroupNameProvider);
  final customerId = ref.watch(customerIdProvider);

  if (customerId == null || customerId.isEmpty) {
    return <CustomerProduct>[];
  }

  return customerProductRepository.fetchProducts(
    customerId: customerId,
    page: 0,
    pageSize: 50,
    search: search.isEmpty ? null : search,
    groupName: groupName,
  );
});

class CustomerNewOrderPage extends ConsumerStatefulWidget {
  const CustomerNewOrderPage({super.key});

  @override
  ConsumerState<CustomerNewOrderPage> createState() => _CustomerNewOrderPageState();
}

class _CustomerNewOrderPageState extends ConsumerState<CustomerNewOrderPage> {
  final _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _productSectionKey = GlobalKey();
  final GlobalKey<_BarcodeFeedbackOverlayState> _feedbackKey =
      GlobalKey<_BarcodeFeedbackOverlayState>();

  final AudioPlayer _successPlayer = AudioPlayer();
  final AudioPlayer _errorPlayer = AudioPlayer();
  bool _audioReady = false;

  final List<_OrderCartLine> _cartLines = <_OrderCartLine>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    CrashLogger.logScreen('customer_new_order');
    _prepareAudio();
  }

  Future<void> _prepareAudio() async {
    try {
      await _successPlayer.setAsset('assets/sounds/beep.mp3');
      await _errorPlayer.setAsset('assets/sounds/error.mp3');
      if (!mounted) return;
      setState(() {
        _audioReady = true;
      });
    } catch (_) {
      // Ses sistemi hazır olmasa da barkod akışı çalışmaya devam eder.
    }
  }

  @override
  void dispose() {
    _barcodeFocusNode.unfocus();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    _scrollController.dispose();
    _successPlayer.dispose();
    _errorPlayer.dispose();
    super.dispose();
  }

  Future<void> _playSuccess() async {
    try {
      if (_audioReady) {
        await _successPlayer.stop();
        await _successPlayer.seek(Duration.zero);
        await _successPlayer.play();
      }
    } catch (_) {}
  }

  Future<void> _playError() async {
    try {
      if (_audioReady) {
        await _errorPlayer.stop();
        await _errorPlayer.seek(Duration.zero);
        await _errorPlayer.play();
      }
    } catch (_) {}
  }

  String _normalizeBarcode(String input) {
    return input
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^0-9]'), '');
  }

  Map<String, dynamic>? _extractStockUnitsMap(dynamic stockUnits) {
    if (stockUnits is Map) {
      return Map<String, dynamic>.from(stockUnits);
    }
    if (stockUnits is List && stockUnits.isNotEmpty && stockUnits.first is Map) {
      return Map<String, dynamic>.from(stockUnits.first as Map);
    }
    return null;
  }

  double _readQtyFrom(Map<String, dynamic>? map, String key) {
    final v = map?[key];
    if (v == null) return 1;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return 1;
    final normalized =
        s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s;
    return double.tryParse(normalized) ?? 1;
  }

  double get _cartSubtotal =>
      _cartLines.fold<double>(0, (sum, line) => sum + line.total);

  int get _cartLineCount => _cartLines.length;

  Future<void> _openBarcodeScanner() async {
    if (!mounted) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _BarcodeScannerSheet(),
    );

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    _barcodeController.text = result;
    await _handleBarcodeSubmitted(result);
  }

  void _focusBarcodeField() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _barcodeFocusNode.requestFocus();
    });
  }

  _ValidatedAdd _validateAdd({
    required double baseUnitPrice,
    required String unitKey, // 'base' | 'pack' | 'box'
    required int quantity,
    double? packMultiplier,
    double? boxMultiplier,
  }) {
    if (quantity <= 0) {
      throw UserFacingException('Miktar 0 olamaz.');
    }

    if (baseUnitPrice <= 0) {
      throw UserFacingException(
        'Bu ürün için geçerli bir satış fiyatı tanımlı değil.',
      );
    }

    if (unitKey == 'pack' && (packMultiplier == null || packMultiplier <= 0)) {
      throw UserFacingException(
        'Bu ürün için paket birim katsayısı tanımlı değil.',
      );
    }

    if (unitKey == 'box' && (boxMultiplier == null || boxMultiplier <= 0)) {
      throw UserFacingException(
        'Bu ürün için koli birim katsayısı tanımlı değil.',
      );
    }

    double multiplier = 1.0;
    switch (unitKey) {
      case 'pack':
        multiplier = packMultiplier!;
        break;
      case 'box':
        multiplier = boxMultiplier!;
        break;
      case 'base':
      default:
        multiplier = 1.0;
        break;
    }

    final unitPrice = baseUnitPrice * multiplier;

    String unitName;
    switch (unitKey) {
      case 'pack':
        unitName = 'PAKET';
        break;
      case 'box':
        unitName = 'KOLİ';
        break;
      case 'base':
      default:
        unitName = 'ADET';
        break;
    }

    return _ValidatedAdd(
      unitPrice: unitPrice,
      unitName: unitName,
      qty: quantity,
    );
  }

  double _computeUnitPrice({
    required String unit,
    required double baseUnitPrice,
    double? packMultiplier,
    double? boxMultiplier,
    StockUnit? stockUnit,
  }) {
    double multiplier = 1.0;

    if (unit == 'pack') {
      final m = packMultiplier ?? stockUnit?.packContainsPiece?.toDouble();
      multiplier = (m == null || m <= 0) ? 1.0 : m;
    } else if (unit == 'box') {
      final m = boxMultiplier ?? stockUnit?.caseContainsPiece?.toDouble();
      multiplier = (m == null || m <= 0) ? 1.0 : m;
    }

    return baseUnitPrice * multiplier;
  }

  void _addOrIncrementLine({
    required Stock stock,
    StockUnit? stockUnit,
    required String unit,
    required double baseUnitPrice,
    required String baseUnitName,
    String? packUnitName,
    double? packMultiplier,
    String? boxUnitName,
    double? boxMultiplier,
    double quantityDelta = 1,
  }) {
    setState(() {
      final existingIndex = _cartLines.indexWhere(
        (l) => l.stock.id == stock.id && l.unit == unit,
      );

      if (existingIndex >= 0) {
        final line = _cartLines[existingIndex];
        line.quantity += quantityDelta;
      } else {
        final effectiveBasePrice = baseUnitPrice;
        final unitPrice = _computeUnitPrice(
          unit: unit,
          baseUnitPrice: effectiveBasePrice,
          packMultiplier: packMultiplier,
          boxMultiplier: boxMultiplier,
          stockUnit: stockUnit,
        );
        _cartLines.add(
          _OrderCartLine(
            stock: stock,
            stockUnit: stockUnit,
            unit: unit,
            quantity: quantityDelta,
            unitPrice: unitPrice,
            baseUnitPrice: effectiveBasePrice,
            baseUnitName: baseUnitName,
            packUnitName: packUnitName,
            packMultiplier: packMultiplier,
            boxUnitName: boxUnitName,
            boxMultiplier: boxMultiplier,
          ),
        );
      }
    });
  }

  void _updateLineQuantity(int index, double quantity) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      if (quantity <= 0) {
        _cartLines.removeAt(index);
      } else {
        _cartLines[index].quantity = quantity;
      }
    });
    _focusBarcodeField();
  }

  void _incrementLine(int index) {
    if (index < 0 || index >= _cartLines.length) return;
    _updateLineQuantity(index, _cartLines[index].quantity + 1);
  }

  void _decrementLine(int index) {
    if (index < 0 || index >= _cartLines.length) return;
    final current = _cartLines[index];
    if (current.quantity <= 1) {
      _removeLineWithUndo(index);
    } else {
      _updateLineQuantity(index, current.quantity - 1);
    }
  }

  void _removeLine(int index) {
    _removeLineWithUndo(index);
  }

  void _removeLineWithUndo(int index) {
    if (index < 0 || index >= _cartLines.length) return;
    final removedLine = _cartLines[index];
    setState(() {
      _cartLines.removeAt(index);
    });
    _focusBarcodeField();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Satır silindi'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () {
            setState(() {
              final insertIndex =
                  index <= _cartLines.length ? index : _cartLines.length;
              _cartLines.insert(insertIndex, removedLine);
            });
            _barcodeFocusNode.requestFocus();
          },
        ),
      ),
    );
  }

  void _updateLineUnit(int index, String unit) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      final line = _cartLines[index];
      line.unit = unit;
      line.unitPrice = _computeUnitPrice(
        unit: unit,
        baseUnitPrice: line.baseUnitPrice,
        packMultiplier: line.packMultiplier,
        boxMultiplier: line.boxMultiplier,
        stockUnit: line.stockUnit,
      );
    });
    _focusBarcodeField();
  }

  Future<void> _handleBarcodeSubmitted(String value) async {
    String code = _normalizeBarcode(value.trim());
    if (code.isEmpty) return;

    try {
      final session = supabaseClient.auth.currentSession;
      if (session == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Oturum bulunamadı, tekrar giriş yapın.'),
          ),
        );
        return;
      }

      // Barkodu stocks + stock_units join ile çöz.
      dynamic stockRow;
      try {
        stockRow = await supabaseClient
            .from('stocks')
            .select(
              '''
                id,
                name,
                barcode,
                pack_barcode,
                box_barcode,
                stock_units(pack_qty,box_qty)
              ''',
            )
            .or(
              'barcode.eq.$code,pack_barcode.eq.$code,box_barcode.eq.$code',
            )
            .maybeSingle();
      } catch (_) {
        stockRow = null;
      }

      if (!mounted) return;

      if (stockRow == null || stockRow is! Map) {
        await _playError();
        if (!mounted) return;
        _feedbackKey.currentState?.showError();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bilinmeyen barkod: $code')),
        );
        ref.read(_productSearchProvider.notifier).state = code;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _productSectionKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          }
        });
        return;
      }

      final stockMap = Map<String, dynamic>.from(stockRow);
      final stockId = (stockMap['id'] as String?)?.trim() ?? '';
      if (stockId.isEmpty) {
        await _playError();
        if (!mounted) return;
        _feedbackKey.currentState?.showError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bilinmeyen barkod: $code')),
        );
        return;
      }

      String readText(String key) {
        final v = stockMap[key];
        if (v == null) return '';
        return v.toString().trim();
      }

      String normText(String key) => _normalizeBarcode(readText(key));

      final stockBarcode = normText('barcode');
      final packBarcode = normText('pack_barcode');
      final boxBarcode = normText('box_barcode');

      final unitsMap = _extractStockUnitsMap(stockMap['stock_units']);
      final packQty = _readQtyFrom(unitsMap, 'pack_qty');
      final boxQty = _readQtyFrom(unitsMap, 'box_qty');

      String unitKey;
      if (code == stockBarcode) {
        unitKey = 'base';
      } else if (code == packBarcode) {
        unitKey = 'pack';
      } else if (code == boxBarcode) {
        unitKey = 'box';
      } else {
        await _playError();
        if (!mounted) return;
        _feedbackKey.currentState?.showError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bilinmeyen barkod: $code')),
        );
        return;
      }

      // Fiyatı doğrudan stok.salePrice1 yerine, müşteri için
      // price_tier mantığı uygulanmış view'den al.
      final customerId = ref.read(customerIdProvider);
      if (customerId == null || customerId.isEmpty) {
        throw UserFacingException(
          'Müşteri bilgisi bulunamadı. Lütfen tekrar giriş yapın.',
        );
      }

      final dynamic row = await supabaseClient
          .from('v_customer_stock_prices')
          .select(
            'stock_id, unit_price, base_unit_price, '
            'base_unit_name, pack_unit_name, pack_multiplier, '
            'box_unit_name, box_multiplier',
          )
          .eq('stock_id', stockId)
          .eq('customer_id', customerId)
          .maybeSingle();

        if (row == null) {
          throw UserFacingException(
            'Bu ürün için müşteri fiyatı bulunamadı.',
          );
        }

        final map = Map<String, dynamic>.from(row as Map);

        final num? rawPrice =
            (map['price'] as num?) ?? (map['unit_price'] as num?);
        final num? rawBaseUnitPrice =
            (map['base_unit_price'] as num?) ?? rawPrice;

        final baseUnitPrice = rawBaseUnitPrice?.toDouble() ?? 0;
        final rawBaseUnitName = map['base_unit_name'] as String?;
        final baseUnitName =
            (rawBaseUnitName == null || rawBaseUnitName.trim().isEmpty)
                ? 'Adet'
                : rawBaseUnitName.trim();

        double? pickPositive(num? v) {
          if (v == null) return null;
          final d = v.toDouble();
          return d > 0 ? d : null;
        }

        final packMultiplierFromView = pickPositive(map['pack_multiplier'] as num?);
        final boxMultiplierFromView = pickPositive(map['box_multiplier'] as num?);

        final double? packMultiplier =
          packMultiplierFromView ?? (packQty > 0 ? packQty : null);
        final double? boxMultiplier =
          boxMultiplierFromView ?? (boxQty > 0 ? boxQty : null);

        String? normalizeUnitName(String? value) {
          if (value == null) return null;
          final trimmed = value.trim();
          if (trimmed.isEmpty) return null;
          return trimmed;
        }

        final String? packUnitName =
          normalizeUnitName(map['pack_unit_name'] as String?);
        final String? boxUnitName =
          normalizeUnitName(map['box_unit_name'] as String?);

      final validated = _validateAdd(
        baseUnitPrice: baseUnitPrice,
        unitKey: unitKey,
        quantity: 1,
        packMultiplier: packMultiplier,
        boxMultiplier: boxMultiplier,
      );

      final stockWithUnit = await stockRepository.getStockWithUnit(stockId);
      if (!mounted) return;

      _addOrIncrementLine(
        stock: stockWithUnit.$1,
        stockUnit: stockWithUnit.$2,
        unit: unitKey == 'base' ? 'piece' : unitKey,
        baseUnitPrice: baseUnitPrice,
        baseUnitName: baseUnitName,
        packUnitName: packUnitName,
        packMultiplier: packMultiplier,
        boxUnitName: boxUnitName,
        boxMultiplier: boxMultiplier,
      );

      final String uiUnit;
      final double? uiMultiplier;
      switch (unitKey) {
        case 'pack':
          uiUnit = 'paket';
          uiMultiplier = packMultiplier;
          break;
        case 'box':
          uiUnit = 'koli';
          uiMultiplier = boxMultiplier;
          break;
        default:
          uiUnit = 'adet';
          uiMultiplier = null;
      }

      await _playSuccess();
      if (!mounted) return;
      _feedbackKey.currentState?.showSuccess(
        productName: stockWithUnit.$1.name,
        unit: uiUnit,
        multiplier: uiMultiplier,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${stockWithUnit.$1.name} (+${validated.qty} ${validated.unitName})',
          ),
        ),
      );
    } on UserFacingException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e, st) {
      debugPrint('[CustomerNewOrder] findStockByBarcode failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ürün sepete eklenemedi.'),
        ),
      );
    } finally {
      _barcodeController.clear();
      _focusBarcodeField();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  String _backendUnit(String unit) {
    switch (unit) {
      case 'pack':
        return 'paket';
      case 'box':
        return 'koli';
      default:
        return 'adet';
    }
  }

  Future<void> _save() async {
    if (_cartLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sepete en az bir ürün ekleyin.')),
      );
      return;
    }

    for (final line in _cartLines) {
      if (line.unitPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('"${line.stock.name}" satırında birim fiyat 0 olamaz.'),
          ),
        );
        return;
      }

      if (line.quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '"${line.stock.name}" satırında miktar 0 olamaz.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final items = <CustomerOrderItemDraft>[];

      for (final line in _cartLines.where((l) => l.stock.id != null)) {
        final qty = line.quantity;

        items.add(
          CustomerOrderItemDraft(
            stockId: line.stock.id!,
            name: line.stock.name,
            unit: _backendUnit(line.unit),
            quantity: qty,
            unitPrice: line.unitPrice,
          ),
        );
      }
      final orderId = await customerOrderRepository.createOrderFromCart(
        items: items,
      );

      if (!mounted) return;
      setState(() {
        _cartLines.clear();
      });
      ref.read(_productSearchProvider.notifier).state = '';
      _barcodeController.clear();
      _barcodeFocusNode.unfocus();
      _scrollToTop();

      context.go('/orders/$orderId');
    } catch (e, st) {
      await CrashLogger.recordSupabaseError(
        e,
        st,
        reason: 'supabase_insert_failed',
        operation: 'createOrderFromCart',
        table: 'orders',
      );
      debugPrint('[CustomerNewOrder] createOrderFromCart failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İşlem başarısız. Lütfen tekrar deneyin.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _confirmClearCart() async {
    if (_cartLines.isEmpty) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sepeti temizle'),
            content: const Text(
              'Sepetteki tüm satırlar silinecek. Devam etmek istiyor musunuz?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sepeti temizle'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() {
      _cartLines.clear();
    });
    _barcodeController.clear();
    _focusBarcodeField();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_productsFutureProvider);
    final groupNamesAsync = ref.watch(_groupNamesFutureProvider);
    final selectedGroupName = ref.watch(_selectedGroupNameProvider);
    final canSave = _cartLines.isNotEmpty;

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyB,
        ): const _FocusBarcodeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _FocusBarcodeIntent: CallbackAction<_FocusBarcodeIntent>(
            onInvoke: (intent) {
              _focusBarcodeField();
              return null;
            },
          ),
        },
        child: AppScaffold(
          title: 'Yeni Sipariş',
          actions: [
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Faturalarım',
              onPressed: () {
                FocusScope.of(context).unfocus();
                context.go('/invoices');
              },
            ),
          ],
          body: Stack(
            children: [
              SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.s8),
                    _BarcodeSection(
                      controller: _barcodeController,
                      focusNode: _barcodeFocusNode,
                      onSubmitted: _handleBarcodeSubmitted,
                      onScanTap: _openBarcodeScanner,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    _ProductSection(
                      sectionKey: _productSectionKey,
                      groupNamesAsync: groupNamesAsync,
                      selectedGroupName: selectedGroupName,
                      onGroupSelected: (groupName) {
                        ref.read(_selectedGroupNameProvider.notifier).state =
                            groupName;
                        ref.read(_productSearchProvider.notifier).state = '';
                      },
                      onClearGroup: () {
                        ref.read(_selectedGroupNameProvider.notifier).state =
                            null;
                        ref.read(_productSearchProvider.notifier).state = '';
                      },
                      productsAsync: productsAsync,
                      searchText: ref.watch(_productSearchProvider),
                      onSearchChanged: (value) => ref
                          .read(_productSearchProvider.notifier)
                          .state = value,
                      onAddToCart: (product) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final session = supabaseClient.auth.currentSession;
                          if (session == null) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Oturum bulunamadı, tekrar giriş yapın.',
                                ),
                              ),
                            );
                            return;
                          }

                          final result = await stockRepository
                              .getStockWithUnit(product.stockId);
                          if (!mounted) return;

                          final baseUnitPrice = product.baseUnitPrice;
                          String unitKey = 'base';
                          if ((product.boxMultiplier ?? 0) > 0) {
                            unitKey = 'box';
                          } else if ((product.packMultiplier ?? 0) > 0) {
                            unitKey = 'pack';
                          }

                          final validated = _validateAdd(
                            baseUnitPrice: baseUnitPrice,
                            unitKey: unitKey,
                            quantity: 1,
                            packMultiplier: product.packMultiplier,
                            boxMultiplier: product.boxMultiplier,
                          );

                          final baseUnitName = product.baseUnitName;
                          final packUnitName = product.packUnitName;
                          final packMultiplier = product.packMultiplier;
                          final boxUnitName = product.boxUnitName;
                          final boxMultiplier = product.boxMultiplier;
                          final unitForCart =
                              unitKey == 'base' ? 'piece' : unitKey;
                          _addOrIncrementLine(
                            stock: result.$1,
                            stockUnit: result.$2,
                            unit: unitForCart,
                            baseUnitPrice: baseUnitPrice,
                            baseUnitName: baseUnitName,
                            packUnitName: packUnitName,
                            packMultiplier: packMultiplier,
                            boxUnitName: boxUnitName,
                            boxMultiplier: boxMultiplier,
                          );
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                '${product.name} (+${validated.qty} ${validated.unitName})',
                              ),
                            ),
                          );
                        } on UserFacingException catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(
                            SnackBar(content: Text(e.message)),
                          );
                        } catch (e, st) {
                          unawaited(
                            CrashLogger.recordError(
                              e,
                              st,
                              reason: 'customer_add_to_cart_failed',
                              fatal: false,
                            ),
                          );
                          debugPrint(
                            '[CustomerNewOrder] onAddToCart failed: $e',
                          );
                          debugPrintStack(stackTrace: st);
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Ürün sepete eklenemedi.'),
                            ),
                          );
                        }
                      },
                      onBarcodeTap: (product) {
                        final barcode = product.barcode;
                        if (barcode == null || barcode.isEmpty) {
                          return;
                        }
                        _barcodeController.text = barcode;
                        _handleBarcodeSubmitted(barcode);
                      },
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    _SummarySection(
                      itemCount: _cartLineCount,
                      total: _cartSubtotal,
                      onClearCart: _confirmClearCart,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    _CartSection(
                      cartLines: _cartLines,
                      onIncrement: _incrementLine,
                      onDecrement: _decrementLine,
                      onRemoveLine: _removeLine,
                      onUnitChanged: _updateLineUnit,
                      onQuantityChanged: _updateLineQuantity,
                      onEmptyCta: _scrollToTop,
                    ),
                    const SizedBox(height: AppSpacing.s24),
                  ],
                ),
              ),
              BarcodeFeedbackOverlay(key: _feedbackKey),
            ],
          ),
          bottom: SafeArea(
            top: false,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: PrimaryButton(
                  label:
                      _saving ? 'Sipariş oluşturuluyor...' : 'Siparişi Oluştur',
                  icon: Icons.send_outlined,
                  expand: true,
                  onPressed: !_saving && canSave ? _save : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BarcodeFeedbackOverlay extends StatefulWidget {
  const BarcodeFeedbackOverlay({super.key});

  @override
  State<BarcodeFeedbackOverlay> createState() => _BarcodeFeedbackOverlayState();
}

class _BarcodeFeedbackOverlayState extends State<BarcodeFeedbackOverlay> {
  bool _visible = false;
  double _opacity = 0;
  Duration _fadeDuration = const Duration(milliseconds: 150);

  bool _isSuccess = true;
  String _title = '';
  String? _productName;
  String? _detail;

  Timer? _hideTimer;

  static const _fadeInMs = 150;
  static const _visibleMs = 800;
  static const _fadeOutMs = 300;

  void showSuccess({
    required String productName,
    required String unit,
    required double? multiplier,
  }) {
    final lower = unit.trim().toLowerCase();
    String detail;
    if (lower == 'adet') {
      detail = '+1 adet';
    } else if (multiplier != null && multiplier > 0) {
      final m = (multiplier % 1 == 0)
          ? multiplier.toInt().toString()
          : multiplier.toString();
      detail = '+1 $lower ($m adet)';
    } else {
      detail = '+1 $lower';
    }

    _show(
      isSuccess: true,
      title: '✓ Sepete eklendi',
      productName: productName,
      detail: detail,
    );
  }

  void showError() {
    _show(
      isSuccess: false,
      title: 'Barkod bulunamadı',
      productName: null,
      detail: null,
    );
  }

  void _show({
    required bool isSuccess,
    required String title,
    required String? productName,
    required String? detail,
  }) {
    _hideTimer?.cancel();

    setState(() {
      _isSuccess = isSuccess;
      _title = title;
      _productName = productName;
      _detail = detail;
      _visible = true;
      _fadeDuration = const Duration(milliseconds: _fadeInMs);
      _opacity = 1;
    });

    _hideTimer = Timer(
      const Duration(milliseconds: _fadeInMs + _visibleMs),
      () {
        if (!mounted) return;
        setState(() {
          _fadeDuration = const Duration(milliseconds: _fadeOutMs);
          _opacity = 0;
        });

        _hideTimer = Timer(
          const Duration(milliseconds: _fadeOutMs),
          () {
            if (!mounted) return;
            setState(() {
              _visible = false;
            });
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    const successBg = Color(0xFF2ECC71);
    const errorBg = Color(0xFFE74C3C);
    final bg = _isSuccess ? successBg : errorBg;

    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: _fadeDuration,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      if ((_productName ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _productName!.trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if ((_detail ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          _detail!.trim(),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusBarcodeIntent extends Intent {
  const _FocusBarcodeIntent();
}

class _BarcodeSection extends StatelessWidget {
  const _BarcodeSection({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onScanTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function(String) onSubmitted;
  final VoidCallback onScanTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Barkod ile ekleme',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: false,
                  decoration: InputDecoration(
                    labelText: 'Barkod okuyun veya yazın',
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (value.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Temizle',
                            onPressed: () {
                              controller.clear();
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                focusNode.requestFocus();
                              });
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.camera_alt_outlined),
                          tooltip: 'Kamerayla tara',
                          onPressed: onScanTap,
                        ),
                      ],
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) async {
                    final code = value.trim();
                    if (code.isEmpty) return;
                    await onSubmitted(code);
                    controller.clear();
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Barkod okutun ve Enter tuşuna basın',
              style: textTheme.bodySmall?.copyWith(
                color: textTheme.bodySmall?.color?.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({
    required this.sectionKey,
    required this.groupNamesAsync,
    required this.selectedGroupName,
    required this.onGroupSelected,
    required this.onClearGroup,
    required this.productsAsync,
    required this.searchText,
    required this.onSearchChanged,
    required this.onAddToCart,
    this.onBarcodeTap,
  });

  final Key sectionKey;
  final AsyncValue<List<String>> groupNamesAsync;
  final String? selectedGroupName;
  final ValueChanged<String> onGroupSelected;
  final VoidCallback onClearGroup;
  final AsyncValue<List<CustomerProduct>> productsAsync;
  final String searchText;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<CustomerProduct> onAddToCart;
  final ValueChanged<CustomerProduct>? onBarcodeTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    String groupLabel(String raw) {
      if (raw == CustomerProductRepository.ungroupedGroupName) {
        return 'Diğer';
      }
      return raw;
    }

    Widget buildProductsList() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            hintText: 'Ürün adı / kodu / barkod ara',
            initialValue: searchText,
            padded: false,
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: AppSpacing.s8),
          productsAsync.when(
            loading: () => const AppLoadingState(),
            error: (e, _) => AppErrorState(
              message: 'Ürünler yüklenemedi: $e',
            ),
            data: (products) {
              if (products.isEmpty) {
                return const AppEmptyState(
                  title: 'Ürün bulunamadı',
                  subtitle:
                      'Arama kriterlerini değiştirerek tekrar deneyebilirsiniz.',
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final p = products[index];
                  final price = p.effectivePrice ?? 0;
                  final subtitle = 'Fiyat: '
                      '${price.toStringAsFixed(2)} TL';
                  return AppListTile(
                    dense: true,
                    leading: StockImageThumbnail(
                      imagePath: p.imagePath,
                      size: 36,
                    ),
                    title: p.name,
                    subtitle: subtitle,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p.barcode != null && p.barcode!.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            tooltip: 'Barkod ile ekle',
                            onPressed: onBarcodeTap != null
                                ? () => onBarcodeTap!(p)
                                : null,
                          ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => onAddToCart(p),
                        ),
                      ],
                    ),
                    onTap: () => onAddToCart(p),
                  );
                },
              );
            },
          ),
        ],
      );
    }

    return Card(
      key: sectionKey,
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ürünler',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            groupNamesAsync.when(
              loading: () => const AppLoadingState(),
              error: (e, _) => AppErrorState(
                message: 'Ürün grupları yüklenemedi: $e',
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  // Grup tanımı yoksa eski davranış: direkt ürün listesi.
                  return buildProductsList();
                }

                if (selectedGroupName == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Önce ürün grubunu seçin',
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      ...groups.map(
                        (g) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(groupLabel(g)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => onGroupSelected(g),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grup: ${groupLabel(selectedGroupName!)}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onClearGroup,
                        child: const Text('Değiştir'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    buildProductsList(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodeScannerSheet extends StatefulWidget {
  const _BarcodeScannerSheet();

  @override
  State<_BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<_BarcodeScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final value = barcodes.first.rawValue;
    if (value == null || value.trim().isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height * 0.6;

    return SizedBox(
      height: height,
      child: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error, child) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Tarayıcıdan kamera izni verin ve sayfayı yenileyin.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.redAccent),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.itemCount,
    required this.total,
    required this.onClearCart,
  });

  final int itemCount;
  final double total;
  final VoidCallback onClearCart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Özet',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text('Kalem sayısı: $itemCount'),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Toplam tutar: ${total.toStringAsFixed(2)} TL',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            if (itemCount > 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClearCart,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Sepeti temizle'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CartSection extends StatelessWidget {
  const _CartSection({
    required this.cartLines,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemoveLine,
    required this.onUnitChanged,
    required this.onQuantityChanged,
    required this.onEmptyCta,
  });

  final List<_OrderCartLine> cartLines;
  final void Function(int index) onIncrement;
  final void Function(int index) onDecrement;
  final void Function(int index) onRemoveLine;
  final void Function(int index, String unit) onUnitChanged;
  final void Function(int index, double quantity) onQuantityChanged;
  final VoidCallback onEmptyCta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (cartLines.isEmpty) {
      return AppEmptyState(
        title: 'Sepet boş',
        subtitle: 'Ürün listesine dokunarak veya barkod okutarak ekleyin.',
        action: PrimaryButton(
          label: 'Ürün ekle',
          icon: Icons.add,
          onPressed: onEmptyCta,
        ),
      );
    }

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sepet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cartLines.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final line = cartLines[index];
                return _CartLineTile(
                  index: index,
                  line: line,
                  onIncrement: onIncrement,
                  onDecrement: onDecrement,
                  onRemove: onRemoveLine,
                  onUnitChanged: onUnitChanged,
                  onQuantityChanged: onQuantityChanged,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.index,
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onUnitChanged,
    required this.onQuantityChanged,
  });

  final int index;
  final _OrderCartLine line;
  final void Function(int index) onIncrement;
  final void Function(int index) onDecrement;
  final void Function(int index) onRemove;
  final void Function(int index, String unit) onUnitChanged;
  final void Function(int index, double quantity) onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantityController =
        TextEditingController(text: line.quantity.toStringAsFixed(2));

    String unitLabel(String unit) {
      if (unit == 'pack') {
        final packName = line.packUnitName;
        final mult = line.packMultiplier;
        if (packName != null && mult != null && mult > 0) {
          final intMult = mult.toInt();
          final baseName = line.baseUnitName.toLowerCase();
          return '$packName ($intMult $baseName)';
        }
        return packName ?? 'Paket';
      }

      if (unit == 'box') {
        final boxName = line.boxUnitName;
        final mult = line.boxMultiplier;
        if (boxName != null && mult != null && mult > 0) {
          final intMult = mult.toInt();
          final baseName = line.baseUnitName.toLowerCase();
          return '$boxName ($intMult $baseName)';
        }
        return boxName ?? 'Koli';
      }

      return line.baseUnitName;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                line.stock.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              iconSize: 20,
              tooltip: 'Satırı sil',
              onPressed: () => onRemove(index),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                'Birim: ${unitLabel(line.unit)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = (constraints.maxWidth - AppSpacing.s12) / 2;
            return Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s4,
              children: [
                SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: line.unit,
                    items: buildUnitOptions(
                      baseUnitName: line.baseUnitName,
                      baseMultiplier: 1,
                      packUnitName: line.packUnitName,
                      packMultiplier: line.packMultiplier,
                      boxUnitName: line.boxUnitName,
                      boxMultiplier: line.boxMultiplier,
                      stockId: line.stock.id,
                    )
                        .map(
                          (o) => DropdownMenuItem<String>(
                            value: o.code,
                            child: Text(o.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        onUnitChanged(index, value);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Birim',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: fieldWidth,
                  child: Row(
                    children: [
                      IconButton(
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onDecrement(index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Expanded(
                        child: TextField(
                          controller: quantityController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            labelText: 'Miktar',
                          ),
                          onTap: () {
                            quantityController.selection = TextSelection(
                              baseOffset: 0,
                              extentOffset: quantityController.text.length,
                            );
                          },
                          onSubmitted: (value) {
                            final q = double.tryParse(
                                  value.replaceAll(',', '.'),
                                ) ??
                                line.quantity;
                            onQuantityChanged(index, q);
                          },
                        ),
                      ),
                      IconButton(
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onIncrement(index),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Text(
              'Birim fiyat: ${line.unitPrice.toStringAsFixed(2)} TL',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          'Satır tutarı: ${line.total.toStringAsFixed(2)} TL',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          'Temel adet: ${line.basePieces.toStringAsFixed(2)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _OrderCartLine {
  _OrderCartLine({
    required this.stock,
    required this.stockUnit,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.baseUnitPrice,
    required this.baseUnitName,
    this.packUnitName,
    this.packMultiplier,
    this.boxUnitName,
    this.boxMultiplier,
  });

  final Stock stock;
  final StockUnit? stockUnit;
  String unit;
  double quantity;
  double unitPrice;
  double baseUnitPrice;
  String baseUnitName;
  String? packUnitName;
  double? packMultiplier;
    String? boxUnitName;
    double? boxMultiplier;

  double get total => quantity * unitPrice;

  double get basePieces {
    final multiplier = () {
      if (unit == 'piece') return 1.0;
      if (unit == 'pack') {
        if (packMultiplier != null && packMultiplier! > 0) {
          return packMultiplier!;
        }
        return (stockUnit?.packContainsPiece ?? 1).toDouble();
      }
      if (unit == 'box') {
        if (boxMultiplier != null && boxMultiplier! > 0) {
          return boxMultiplier!;
        }
        return (stockUnit?.caseContainsPiece ?? 1).toDouble();
      }
      return 1.0;
    }();

    return quantity * multiplier;
  }
}
