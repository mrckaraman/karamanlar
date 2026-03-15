import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';
import '../stocks/barcode_scanner_page.dart';

final _customerSearchProvider = StateProvider<String>((ref) => '');
final _productSearchProvider = StateProvider<String>((ref) => '');

final _customersFutureProvider = FutureProvider.autoDispose((ref) async {
  final search = ref.watch(_customerSearchProvider);
  return customerRepository.fetchCustomers(
    search: search,
    isActive: true,
    limit: 100,
  );
});

final _productsFutureProvider = FutureProvider.autoDispose((ref) async {
  final search = ref.watch(_productSearchProvider);
  return stockRepository.fetchStocks(
    search: search,
    isActive: true,
    page: 0,
    pageSize: 50,
  );
});

class AdminSalePage extends ConsumerStatefulWidget {
  const AdminSalePage({
    super.key,
    this.presetCustomerId,
  });

  final String? presetCustomerId;

  @override
  ConsumerState<AdminSalePage> createState() => _AdminSalePageState();
}

class _AdminSalePageState extends ConsumerState<AdminSalePage> {
  Customer? _selectedCustomer;
  final _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final List<_SaleCartLine> _cartLines = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    // Eğer müşteri önceden seçili gelmek isteniyorsa, POS açılışında yükle.
    final presetId = widget.presetCustomerId;
    if (presetId != null && presetId.isNotEmpty) {
      _loadPresetCustomer(presetId);
    }
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPresetCustomer(String customerId) async {
    try {
      final repo = ref.read(customerRepositoryProvider);
      final customer = await repo.fetchCustomerById(customerId);
      if (!mounted) return;

      if (customer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ön tanımlı cari bulunamadı.'),
          ),
        );
        return;
      }

      setState(() {
        _selectedCustomer = customer;
      });

      // Cari hazırsa barkod alanına odaklan.
      _barcodeFocusNode.requestFocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ön tanımlı cari yüklenemedi: $e'),
        ),
      );
    }
  }


  double get _cartSubtotal =>
      _cartLines.fold(0, (sum, line) => sum + line.total);

  int get _cartLineCount => _cartLines.length;

  Future<void> _openBarcodeScanner() async {
    if (!mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    _barcodeController.text = result;
    await _handleBarcodeSubmitted(result);
  }


  double _getUnitMultiplier(String unit, StockUnit? stockUnit) {
    double multiplier = 1;
    if (unit == 'pack') {
      multiplier = (stockUnit?.packContainsPiece ?? 1).toDouble();
    } else if (unit == 'case') {
      multiplier = (stockUnit?.caseContainsPiece ?? 1).toDouble();
    }
    if (multiplier <= 0) {
      multiplier = 1;
    }
    return multiplier;
  }

  double _suggestUnitPrice(String unit, Stock stock, StockUnit? stockUnit) {
    final base = stock.salePrice1 ?? 0;
    final mult = _getUnitMultiplier(unit, stockUnit);
    return base * mult;
  }

  void _addOrIncrementLine({
    required Stock stock,
    StockUnit? stockUnit,
    required String unit,
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
        final basePiecePrice = stock.salePrice1 ?? 0;
        final unitPrice = _suggestUnitPrice(unit, stock, stockUnit);
        _cartLines.add(
          _SaleCartLine(
            stock: stock,
            stockUnit: stockUnit,
            unit: unit,
            quantity: quantityDelta,
            unitPrice: unitPrice,
            discount: 0,
            basePiecePrice: basePiecePrice,
            priceOverridden: false,
            discountType: _DiscountType.amount,
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
  }

  void _incrementLine(int index) {
    if (index < 0 || index >= _cartLines.length) return;
    _updateLineQuantity(index, _cartLines[index].quantity + 1);
  }

  void _decrementLine(int index) {
    if (index < 0 || index >= _cartLines.length) return;
    _updateLineQuantity(index, _cartLines[index].quantity - 1);
  }

  void _removeLine(int index) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      _cartLines.removeAt(index);
    });
  }

  void _updateLineUnit(int index, String unit) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      final line = _cartLines[index];
      line.unit = unit;

      if (!line.priceOverridden) {
        final multiplier = _getUnitMultiplier(unit, line.stockUnit);
        line.unitPrice = line.basePiecePrice * multiplier;
      }
    });
  }

  void _updateLineUnitPrice(int index, double price) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      final line = _cartLines[index];
      line.unitPrice = price;
      line.priceOverridden = true;
    });
  }

  void _updateLineDiscount(int index, double discount) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      _cartLines[index].discount = discount;
    });
  }

  void _updateLineDiscountType(int index, _DiscountType type) {
    setState(() {
      if (index < 0 || index >= _cartLines.length) return;
      _cartLines[index].discountType = type;
    });
  }

  Future<void> _handleBarcodeSubmitted(String value) async {
    final code = value.trim();
    if (code.isEmpty) return;

    try {
      final result = await stockRepository.findStockByBarcode(code);
      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bilinmeyen barkod: $code'),
          ),
        );
        ref.read(_productSearchProvider.notifier).state = code;
      } else {
        final stock = result.$1;
        final stockUnit = result.$2;

        String unitKey = 'piece';
        if (code == stock.barcode || code == stockUnit?.unitPieceBarcode) {
          unitKey = 'piece';
        } else if (code == stock.packBarcode ||
            code == stockUnit?.unitPackBarcode) {
          unitKey = 'pack';
        } else if (code == stock.boxBarcode ||
            code == stockUnit?.unitCaseBarcode) {
          unitKey = 'case';
        }

        _addOrIncrementLine(
          stock: stock,
          stockUnit: stockUnit,
          unit: unitKey,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${stock.name} (+1 ${_unitLabel(unitKey)})'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barkod okunamadı: $e')),
      );
    } finally {
      _barcodeController.clear();
      _barcodeFocusNode.requestFocus();
    }
  }

  String _unitLabel(String unit) {
    switch (unit) {
      case 'pack':
        return 'Paket';
      case 'case':
        return 'Koli';
      default:
        return 'Adet';
    }
  }

  Future<void> _handleSelectCustomer(Customer c) async {
    if (_selectedCustomer != null &&
        _selectedCustomer!.id != c.id &&
        _cartLines.isNotEmpty) {
      final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Müşteri değiştirilsin mi?'),
              content: const Text(
                'Müşteri değiştirildiğinde mevcut sepet temizlenecek.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Devam et'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirm) return;

      setState(() {
        _cartLines.clear();
      });
    }

    setState(() {
      _selectedCustomer = c;
    });
  }

  void _resetForNewSale() {
    setState(() {
      _selectedCustomer = null;
      _cartLines.clear();
      _barcodeController.clear();
    });
    ref.read(_customerSearchProvider.notifier).state = '';
    ref.read(_productSearchProvider.notifier).state = '';
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _save() async {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir cari seçin.')),
      );
      return;
    }
    if (_cartLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sepete en az bir ürün ekleyin.')),
      );
      return;
    }

    // Satır bazlı temel kontroller: fiyat ve iskonto mantıklı mı?
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

      final gross = line.quantity * line.unitPrice;
      if (line.discountType == _DiscountType.amount) {
        if (line.discount < 0 || line.discount > gross) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '"${line.stock.name}" satırında iskonto tutarı satır toplamını aşamaz.',
              ),
            ),
          );
          return;
        }
      } else {
        if (line.discount < 0 || line.discount > 100) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '"${line.stock.name}" satırında iskonto oranı 0-100 arasında olmalıdır.',
              ),
            ),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final customerId = _selectedCustomer!.id;
      final totalBeforeReset = _cartSubtotal;

      final items = _cartLines
            .where((line) => line.stock.id != null)
            .map((line) {
          final unitName = () {
            switch (line.unit) {
              case 'pack':
                return 'Paket';
              case 'case':
                return 'Koli';
              default:
                return 'Adet';
            }
          }();

          return <String, dynamic>{
            'stock_id': line.stock.id!,
            'qty': line.quantity,
            'unit_name': unitName,
            'unit_price': line.unitPrice,
          };
        }).toList();

      final invoiceId = await saleRepository.createPosInvoice(
        customerId: customerId,
        items: items,
      );

      if (!mounted) return;

      // Başarılı POS satışından sonra sepeti sıfırla.
      _resetForNewSale();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Satış faturaya dönüştürüldü.')),
      );

      // Premium: satış sonrası aksiyon sheet'i.
      await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) {
            return SafeArea(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Satış tamamlandı',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Toplam tutar: ${formatMoney(totalBeforeReset)}',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.s16),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        context.go('/invoices/$invoiceId');
                      },
                      child: const Text('Faturayı Gör'),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    FilledButton.tonal(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        context.go(
                          '/customers/$customerId/statement',
                        );
                      },
                      child: const Text('Cari Ekstre'),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        // Zaten resetlendi; sadece odak barcoda olsun.
                        _barcodeFocusNode.requestFocus();
                      },
                      child: const Text('Yeni Satış'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
    } catch (e) {
      if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Satış tamamlanamadı: $e'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(_customersFutureProvider);
    final productsAsync = ref.watch(_productsFutureProvider);
    final canSave =
        _selectedCustomer != null && _cartLines.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // Yeni satış ekranında geri tuşu her zaman dashboard'a götürsün.
        if (didPop || !mounted) return;
        context.go('/dashboard');
      },
      child: Shortcuts(
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
                _barcodeFocusNode.requestFocus();
                return null;
              },
            ),
          },
          child: AppScaffold(
            title: 'Yeni Satış',
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.s8),
                  _CustomerSection(
                    customersAsync: customersAsync,
                    selectedCustomer: _selectedCustomer,
                    onSearchChanged: (value) => ref
                        .read(_customerSearchProvider.notifier)
                        .state = value,
                    onSelectCustomer: _handleSelectCustomer,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _BarcodeSection(
                    controller: _barcodeController,
                    focusNode: _barcodeFocusNode,
                    onSubmitted: _handleBarcodeSubmitted,
                    onScanTap: _openBarcodeScanner,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _ProductSection(
                    productsAsync: productsAsync,
                    onSearchChanged: (value) => ref
                        .read(_productSearchProvider.notifier)
                        .state = value,
                    onAddToCart: (stock) async {
                      if (stock.id == null) return;
                      final messenger =
                          ScaffoldMessenger.of(context);
                      final result = await stockRepository
                          .getStockWithUnit(stock.id!);
                      if (!mounted) return;
                      _addOrIncrementLine(
                        stock: result.$1,
                        stockUnit: result.$2,
                        unit: 'piece',
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content:
                              Text('${stock.name} (+1 Adet)'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _SummarySection(
                    customer: _selectedCustomer,
                    itemCount: _cartLineCount,
                    total: _cartSubtotal,
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  _CartSection(
                    cartLines: _cartLines,
                    onIncrement: _incrementLine,
                    onDecrement: _decrementLine,
                    onRemoveLine: _removeLine,
                    onUnitChanged: _updateLineUnit,
                    onQuantityChanged: _updateLineQuantity,
                    onUnitPriceChanged: _updateLineUnitPrice,
                    onDiscountChanged: _updateLineDiscount,
                    onDiscountTypeChanged: _updateLineDiscountType,
                  ),
                  const SizedBox(height: AppSpacing.s24),
                ],
              ),
            ),
            bottom: SafeArea(
              top: false,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: PrimaryButton(
                    label: _saving
                        ? 'Satış tamamlanıyor...'
                        : 'Satışı Tamamla',
                    icon: Icons.save_outlined,
                    expand: true,
                    onPressed: !_saving && canSave ? _save : null,
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

class _CustomerSection extends StatelessWidget {
  const _CustomerSection({
    required this.customersAsync,
    required this.selectedCustomer,
    required this.onSearchChanged,
    required this.onSelectCustomer,
  });

  final AsyncValue<List<Customer>> customersAsync;
  final Customer? selectedCustomer;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Customer> onSelectCustomer;

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
              'Müşteri',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            AppSearchField(
              hintText: 'Cari adı / kodu ara',
              initialValue: '',
              padded: false,
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: AppSpacing.s8),
            customersAsync.when(
              loading: () => const AppLoadingState(),
              error: (e, _) => AppErrorState(
                message: 'Cari yüklenemedi: $e',
              ),
              data: (customers) {
                if (customers.isEmpty) {
                  return const AppEmptyState(
                    title: 'Cari bulunamadı',
                    subtitle:
                        'Arama kriterlerini değiştirerek tekrar deneyebilirsiniz.',
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final c = customers[index];
                    final selected = selectedCustomer?.id == c.id;
                    return AppListTile(
                      title: c.name,
                      subtitle: c.code,
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: () => onSelectCustomer(c),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSection extends StatelessWidget {
  const _ProductSection({
    required this.productsAsync,
    required this.onSearchChanged,
    required this.onAddToCart,
  });

  final AsyncValue<List<Stock>> productsAsync;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Stock> onAddToCart;

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
              'Ürünler',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            AppSearchField(
              hintText: 'Ürün adı / kodu / barkod ara',
              initialValue: '',
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
                    return AppListTile(
                      title: p.name,
                      subtitle:
						  'Fiyat: ${formatMoney(p.salePrice1 ?? 0)}'
						  '${p.quantity != null ? ' • Stok: ${p.quantity!.toStringAsFixed(2)}' : ''}',
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => onAddToCart(p),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.customer,
    required this.itemCount,
    required this.total,
  });

  final Customer? customer;
  final int itemCount;
  final double total;

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
            Text(
              'Müşteri: ${customer?.name ?? '-'}',
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
			  'Kalem sayısı: $itemCount',
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
			  'Toplam tutar: ${formatMoney(total)}',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  final ValueChanged<String> onSubmitted;
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
                  autofocus: true,
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
                  onSubmitted: onSubmitted,
                );
              },
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
    required this.onUnitPriceChanged,
    required this.onDiscountChanged,
    required this.onDiscountTypeChanged,
  });

  final List<_SaleCartLine> cartLines;
  final void Function(int index) onIncrement;
  final void Function(int index) onDecrement;
  final void Function(int index) onRemoveLine;
  final void Function(int index, String unit) onUnitChanged;
  final void Function(int index, double quantity) onQuantityChanged;
  final void Function(int index, double price) onUnitPriceChanged;
  final void Function(int index, double discount) onDiscountChanged;
    final void Function(int index, _DiscountType type) onDiscountTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (cartLines.isEmpty) {
      return const AppEmptyState(
        title: 'Sepet boş',
        subtitle: 'Ürün listesine dokunarak veya barkod okutarak ekleyin.',
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
                  onUnitPriceChanged: onUnitPriceChanged,
                  onDiscountChanged: onDiscountChanged,
                  onDiscountTypeChanged: onDiscountTypeChanged,
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
    required this.onUnitPriceChanged,
    required this.onDiscountChanged,
    required this.onDiscountTypeChanged,
  });

  final int index;
  final _SaleCartLine line;
  final void Function(int index) onIncrement;
  final void Function(int index) onDecrement;
  final void Function(int index) onRemove;
  final void Function(int index, String unit) onUnitChanged;
  final void Function(int index, double quantity) onQuantityChanged;
  final void Function(int index, double price) onUnitPriceChanged;
  final void Function(int index, double discount) onDiscountChanged;
    final void Function(int index, _DiscountType type) onDiscountTypeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quantityController =
        TextEditingController(text: line.quantity.toStringAsFixed(2));
    final priceController =
        TextEditingController(text: line.unitPrice.toStringAsFixed(2));
    final discountController =
        TextEditingController(text: line.discount.toStringAsFixed(2));

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
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: line.unit,
                items: const [
                  DropdownMenuItem(value: 'piece', child: Text('Adet')),
                  DropdownMenuItem(value: 'pack', child: Text('Paket')),
                  DropdownMenuItem(value: 'case', child: Text('Koli')),
                ],
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
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    iconSize: 20,
                    onPressed: () => onDecrement(index),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Expanded(
                    child: TextField(
                      controller: quantityController,
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
                    onPressed: () => onIncrement(index),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Birim fiyat',
                ),
                onSubmitted: (value) {
                  final p = double.tryParse(value.replaceAll(',', '.')) ??
                      line.unitPrice;
                  onUnitPriceChanged(index, p);
                },
              ),
            ),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: discountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText:
                            'İskonto (${line.discountType == _DiscountType.amount ? 'TL' : '%'})',
                      ),
                      onSubmitted: (value) {
                        final d = double.tryParse(
                              value.replaceAll(',', '.'),
                            ) ??
                            line.discount;
                        onDiscountChanged(index, d);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  DropdownButton<_DiscountType>(
                    value: line.discountType,
                    items: const [
                      DropdownMenuItem(
                        value: _DiscountType.amount,
                        child: Text('TL'),
                      ),
                      DropdownMenuItem(
                        value: _DiscountType.percent,
                        child: Text('%'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onDiscountTypeChanged(index, value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
      		  'Satır tutarı: ${formatMoney(line.total)}',
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

enum _DiscountType { amount, percent }

class _SaleCartLine {
  _SaleCartLine({
    required this.stock,
    required this.stockUnit,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.basePiecePrice,
    required this.priceOverridden,
    required this.discountType,
  });

  final Stock stock;
  final StockUnit? stockUnit;
  String unit;
  double quantity;
  double unitPrice;
  double discount;
  double basePiecePrice;
  bool priceOverridden;
  _DiscountType discountType;

  double get totalBeforeDiscount => quantity * unitPrice;

  double get total {
    final gross = totalBeforeDiscount;
    if (discountType == _DiscountType.amount) {
      return gross - discount;
    }
    final percent = discount.clamp(0, 100);
    return gross - (gross * percent / 100);
  }

  double get basePieces {
    final multiplier = () {
      if (unit == 'piece') return 1.0;
      if (unit == 'pack') {
        return (stockUnit?.packContainsPiece ?? 1).toDouble();
      }
      if (unit == 'case') {
        return (stockUnit?.caseContainsPiece ?? 1).toDouble();
      }
      return 1.0;
    }();

    return quantity * multiplier;
  }
}
