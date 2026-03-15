import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../utils/formatters_tr.dart';

class AdminInvoiceEditPage extends ConsumerStatefulWidget {
  const AdminInvoiceEditPage({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<AdminInvoiceEditPage> createState() => _AdminInvoiceEditPageState();
}

class _AdminInvoiceEditPageState extends ConsumerState<AdminInvoiceEditPage> {
  DateTime? _invoiceDate;
  bool _loading = false;
  bool _saving = false;
  String? _loadError;

  final List<_EditableInvoiceItem> _items = <_EditableInvoiceItem>[];

  DateTime? _initialInvoiceDate;
  final List<_EditableInvoiceItem> _initialItems = <_EditableInvoiceItem>[];

  double _effectiveQty({
    required double qty,
    required String unitName,
    required double packQty,
    required double boxQty,
  }) {
    final u = unitName.trim().toLowerCase();
    if (u.isEmpty || u == 'adet') return qty;

    final safePackQty = packQty > 0 ? packQty : 1;
    final safeBoxQty = boxQty > 0 ? boxQty : 1;

    if (u == 'paket') {
      return qty * safePackQty;
    }

    if (u == 'koli') {
      // Koli ve paket birbirinden bağımsız: koli = qty × boxQty
      return qty * safeBoxQty;
    }

    // Bilinmeyen birim: dönüşüm uygulama.
    return qty;
  }

  void _syncItemFromControllers(_EditableInvoiceItem item, {String? unitNameOverride}) {
    final qty = _parseTrNumber(item.qtyController.text);
    final price = _parseTrNumber(item.priceController.text);
    final unitName = unitNameOverride ?? item.unitName;
    final effectiveQty = _effectiveQty(
      qty: qty,
      unitName: unitName,
      packQty: item.packQty,
      boxQty: item.boxQty,
    );

    item.qty = qty;
    item.unitPrice = price;
    item.unitName = unitName;
    item.total = effectiveQty * price;
  }

  double _parseTrNumber(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return 0;

    // Remove currency symbols and spaces (including non-breaking space).
    text = text.replaceAll(RegExp(r'[\s\u00A0₺]'), '');

    // If we have a comma, assume comma is decimal separator and dots are thousands.
    if (text.contains(',')) {
      text = text.replaceAll('.', '');
      text = text.replaceAll(',', '.');
    }

    // Keep only digits, minus, and dot.
    text = text.replaceAll(RegExp(r'[^0-9\-.]'), '');

    return double.tryParse(text) ?? 0;
  }

  String _formatUnitMultiplier(double multiplier) {
    if (multiplier % 1 == 0) {
      return multiplier.toInt().toString();
    }
    return multiplier.toString();
  }

  void _recalculate() {
    if (_items.isEmpty) return;
    setState(() {
      for (final item in _items) {
        _syncItemFromControllers(item);
      }
    });
  }

  void _recalculateItem(_EditableInvoiceItem item) {
    setState(() {
      _syncItemFromControllers(item);
    });
  }

  @override
  void initState() {
    super.initState();
    _recalculate();
    _load();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.qtyController.dispose();
      item.priceController.dispose();
    }
    for (final item in _initialItems) {
      item.qtyController.dispose();
      item.priceController.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final detail = await adminInvoiceRepository.fetchInvoiceById(widget.invoiceId);
      final items = await adminInvoiceRepository.fetchInvoiceItems(widget.invoiceId);

        _invoiceDate =
            detail.invoiceDate ?? detail.issuedAt ?? detail.createdAt ?? DateTime.now();

      _items
        ..clear()
        ..addAll(
          items.map(
            (e) => _EditableInvoiceItem(
              stockId: e.stockId,
              stockName: e.stockName,
              unitName: e.unitName,
              qty: e.qty,
              unitPrice: e.unitPrice,
              unitOptions: const <String>[],
            ),
          ),
        );

      // Snapshot alınmadan önce controller'lardan hesapla.
      _recalculate();

      // Önce eski snapshot controller'larını dispose et.
      for (final item in _initialItems) {
        item.qtyController.dispose();
        item.priceController.dispose();
      }
      _initialItems.clear();

        // Başlangıç snapshot'ını al (değişiklik kontrolü için).
        _initialInvoiceDate = _invoiceDate;
        _initialItems
          ..clear()
          ..addAll(_items.map((e) => e.copy()));

      if (!mounted) return;
      setState(() {
        _loading = false;
      });

      // Ürün birim seçeneklerini stok bilgileri üzerinden hydrate et.
      // (UI'da sadece dropdown seçeneklerini göstermek için)
      await _hydrateUnitOptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _hydrateUnitOptions() async {
    // Boşsa veya yükleme sırasında tekrar çağrılırsa gereksiz istek atma.
    if (!mounted || _items.isEmpty) return;

    final stockIds = _items
        .map((e) => e.stockId)
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    if (stockIds.isEmpty) return;

    final Map<String, _StockUnitMeta> metaByStockId = <String, _StockUnitMeta>{};

    await Future.wait(
      stockIds.map((stockId) async {
        metaByStockId[stockId] = await _buildUnitMetaForStock(stockId);
      }),
    );

    if (!mounted) return;

    setState(() {
      for (final item in _items) {
        final meta = metaByStockId[item.stockId];
        item.unitOptions = meta?.options ?? const <String>['adet', 'paket', 'koli'];
        item.packQty = meta?.packQty ?? 0;
        item.boxQty = meta?.boxQty ?? 0;

        // Dönüşüm bilgisi geldiyse, mevcut controller değerlerine göre toplamı da güncelle.
        _syncItemFromControllers(item);
      }
    });
  }

  Future<_StockUnitMeta> _buildUnitMetaForStock(String stockId) async {
    // Fallback: her zaman en az bu üçlü gösterilebilir.
    const fallback = <String>['adet', 'paket', 'koli'];

    String? readText(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final v = map[key];
        if (v == null) continue;
        if (v is String) return v;
        return v.toString();
      }
      return null;
    }

    String normalizeKnownUnitName(String? value, String fallbackValue) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return fallbackValue;
      final lower = trimmed.toLowerCase();
      if (lower == 'adet') return 'adet';
      if (lower == 'paket') return 'paket';
      if (lower == 'koli') return 'koli';
      return trimmed;
    }

    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      if (v is String && v.trim().isNotEmpty) {
        // TR formatı (1.000,50) olasılığı için basit normalize.
        final trimmed = v.trim();
        final normalized = trimmed.contains(',')
            ? trimmed.replaceAll('.', '').replaceAll(',', '.')
            : trimmed;
        return double.tryParse(normalized) ?? 0;
      }
      return 0;
    }

    double readNumber(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final v = map[key];
        final d = toDouble(v);
        if (d > 0) return d;
      }
      return 0;
    }

    try {
      final dynamic stockRow = await supabaseClient
          .from('stocks')
          .select()
          .eq('id', stockId)
          .maybeSingle();

      final dynamic unitRow = await supabaseClient
          .from('stock_units')
          .select('pack_qty, box_qty')
          .eq('stock_id', stockId)
          .maybeSingle();

        final stockMap =
          stockRow is Map ? Map<String, dynamic>.from(stockRow) : <String, dynamic>{};
        final unitMap =
          unitRow is Map ? Map<String, dynamic>.from(unitRow) : <String, dynamic>{};

        final rawBaseName = readText(stockMap, const <String>[
          'base_unit_name',
          'base_unit',
          'unit',
        ]);
        final rawPackName = readText(stockMap, const <String>[
          'pack_unit_name',
          'pack_unit',
          'pack_unitname',
        ]);
        final rawBoxName = readText(stockMap, const <String>[
          'box_unit_name',
          'box_unit',
          'box_unitname',
        ]);

        // Dönüşüm bilgisi öncelikle stocks tablosundan, yoksa stock_units'tan alınır.
        // pack_qty: paket içi adet
        // box_qty: koli içi paket
        final packQty =
            readNumber(stockMap, const <String>['pack_qty', 'packCount', 'pack_count']) > 0
                ? readNumber(stockMap, const <String>['pack_qty', 'packCount', 'pack_count'])
                : readNumber(unitMap, const <String>['pack_qty', 'packCount', 'pack_count']);
        final boxQty =
            readNumber(stockMap, const <String>['box_qty', 'boxCount', 'box_count']) > 0
                ? readNumber(stockMap, const <String>['box_qty', 'boxCount', 'box_count'])
                : readNumber(unitMap, const <String>['box_qty', 'boxCount', 'box_count']);

      final baseName = normalizeKnownUnitName(rawBaseName, 'adet');
      final packName = normalizeKnownUnitName(rawPackName, 'paket');
      final boxName = normalizeKnownUnitName(rawBoxName, 'koli');

      final hasPack = packQty > 0 || ((rawPackName?.trim() ?? '').isNotEmpty);
      final hasBox = boxQty > 0 || ((rawBoxName?.trim() ?? '').isNotEmpty);

      final options = <String>[];
      options.add(baseName);
      if (hasPack) options.add(packName);
      if (hasBox) options.add(boxName);

      // Eğer hiçbir şey üretemediysek (teoride olmaz) fallback.
      if (options.isEmpty) {
        return _StockUnitMeta(
          options: fallback,
          packQty: packQty,
          boxQty: boxQty,
        );
      }

      // Uniq + sırayı koru.
      final seen = <String>{};
      final unique = <String>[];
      for (final o in options) {
        if (seen.add(o)) unique.add(o);
      }
      return _StockUnitMeta(
        options: unique,
        packQty: packQty,
        boxQty: boxQty,
      );
    } catch (_) {
      return const _StockUnitMeta(options: fallback, packQty: 0, boxQty: 0);
    }
  }

  double get invoiceTotal {
    return _items.fold<double>(0, (sum, item) => sum + item.total);
  }

  bool _hasChanges() {
    if (_initialInvoiceDate != _invoiceDate) {
      return true;
    }

    if (_initialItems.length != _items.length) {
      return true;
    }

    for (var i = 0; i < _items.length; i++) {
      final initial = _initialItems[i];
      final current = _items[i];
      if (initial.qty != current.qty ||
          initial.unitPrice != current.unitPrice ||
          initial.unitName.trim() != current.unitName.trim()) {
        return true;
      }
    }

    return false;
  }

  Future<void> _save() async {
    if (_saving || _loading) return;

    final date = _invoiceDate;
    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen fatura tarihini seçin.')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir fatura kalemi olmalıdır.')),
      );
      return;
    }

    if (!_hasChanges()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Değişiklik yok.')),
      );
      return;
    }

    final itemsPayload = _items
        .map((item) => <String, dynamic>{
              'stock_id': item.stockId,
              'stock_name': item.stockName,
              'unit_name': item.unitName,
              'qty': item.qty,
              'unit_price': item.unitPrice,
            })
        .toList();

    setState(() {
      _saving = true;
    });

    try {
      await adminInvoiceRepository.updateInvoiceWithItems(
        invoiceId: widget.invoiceId,
        invoiceDate: date,
        invoiceNo: null,
        items: itemsPayload,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fatura güncellendi.')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fatura güncellenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final current = _invoiceDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _invoiceDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = const AppLoadingState();
    } else if (_loadError != null) {
      body = AppErrorState(
        message: 'Fatura yüklenemedi: $_loadError',
        onRetry: _load,
      );
    } else {
      body = _buildForm(context);
    }

    return AppScaffold(
      title: 'Fatura Düzenle',
      body: SingleChildScrollView(
        child: body,
      ),
      bottom: SafeArea(
        top: false,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: PrimaryButton(
              label: _saving ? 'Kaydediliyor...' : 'Kaydet',
              expand: true,
              onPressed: _saving ? null : _save,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = _invoiceDate != null ? formatDate(_invoiceDate!) : '-';
    final totalText = '₺${invoiceTotal.toStringAsFixed(2)}';

    return Card
      (      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fatura Bilgileri',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tarih: $dateText',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: _pickDate,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Tarih Seç'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Text(
              'Kalemler',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            if (_items.isEmpty)
              const Text('Bu fatura için kalem bulunamadı.')
            else
              Column(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    _buildItemRow(context, _items[i]),
                ],
              ),
            const SizedBox(height: AppSpacing.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Toplam',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  totalText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(BuildContext context, _EditableInvoiceItem item) {
    final theme = Theme.of(context);
    final total = item.total;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.stockName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _buildUnitDropdown(theme, item),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: item.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Miktar',
                  ),
                  onChanged: (_) => _recalculateItem(item),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: item.priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Birim Fiyat',
                  ),
                  onChanged: (_) => _recalculateItem(item),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '₺${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              IconButton(
                tooltip: 'Kalemi sil',
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() {
                    item.qtyController.dispose();
                    item.priceController.dispose();
                    _items.remove(item);
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnitDropdown(ThemeData theme, _EditableInvoiceItem item) {
    final options = (item.unitOptions.isNotEmpty)
        ? item.unitOptions
        : const <String>['adet', 'paket', 'koli'];

    // Mevcut değer options içinde yoksa (ör. eski veri / custom birim), kaybetme.
    final currentTrimmed = item.unitName.trim();
    final mergedOptions = <String>[...options];
    if (currentTrimmed.isNotEmpty && !mergedOptions.contains(currentTrimmed)) {
      mergedOptions.add(currentTrimmed);
    }

    String? selectedValue;
    if (currentTrimmed.isNotEmpty) {
      // Case-insensitive eşleştir (DB/stock casing farklarında seçim kaybolmasın).
      selectedValue = mergedOptions.firstWhere(
        (o) => o.toLowerCase() == currentTrimmed.toLowerCase(),
        orElse: () => currentTrimmed,
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: DropdownButtonFormField<String>(
        key: ValueKey('${item.stockId}:${selectedValue ?? ''}'),
        initialValue: selectedValue,
        isDense: false,
        isExpanded: true,
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        hint: Text(
          'Birim',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        items: mergedOptions
            .map(
              (unit) => DropdownMenuItem<String>(
                value: unit,
                child: Text(
                  () {
                    final lower = unit.trim().toLowerCase();
                    if (lower == 'adet') {
                      return 'adet (1 adet)';
                    }
                    if (lower == 'paket') {
                      final packQty = item.packQty;
                      if (packQty > 0) {
                        return 'paket (${_formatUnitMultiplier(packQty)} adet)';
                      }
                      return 'paket';
                    }
                    if (lower == 'koli') {
                      final boxQty = item.boxQty;
                      if (boxQty > 0) {
                        return 'koli (${_formatUnitMultiplier(boxQty)} adet)';
                      }
                      return 'koli';
                    }
                    return unit;
                  }(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _syncItemFromControllers(item, unitNameOverride: value);
          });
        },
      ),
    );
  }
}

class _StockUnitMeta {
  const _StockUnitMeta({
    required this.options,
    required this.packQty,
    required this.boxQty,
  });

  final List<String> options;
  final double packQty;
  final double boxQty;
}

class _EditableInvoiceItem {
  _EditableInvoiceItem({
    required this.stockId,
    required this.stockName,
    required this.unitName,
    required this.qty,
    required this.unitPrice,
    required this.unitOptions,
    this.packQty = 0,
    this.boxQty = 0,
  })  : qtyController = TextEditingController(
          text: qty.toStringAsFixed(2).replaceAll('.', ','),
        ),
        priceController = TextEditingController(
          text: unitPrice.toStringAsFixed(2).replaceAll('.', ','),
        ),
        total = qty * unitPrice;

  final String stockId;
  final String stockName;
  String unitName;
  double qty;
  double unitPrice;

  // packQty: paket içi adet
  // boxQty: koli içi paket
  double packQty;
  double boxQty;

  final TextEditingController qtyController;
  final TextEditingController priceController;

  double total;

  List<String> unitOptions;

  double get lineTotal => qty * unitPrice;

  _EditableInvoiceItem copy() {
    return _EditableInvoiceItem(
      stockId: stockId,
      stockName: stockName,
      unitName: unitName,
      qty: qty,
      unitPrice: unitPrice,
      unitOptions: unitOptions,
      packQty: packQty,
      boxQty: boxQty,
    );
  }
}
