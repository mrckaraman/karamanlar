import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../utils/formatters_tr.dart';

final _orderCustomerSearchProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final _orderSelectedCustomerProvider =
    StateProvider.autoDispose<AdminInvoiceCustomerPickEntry?>((ref) {
  return null;
});

final _orderCustomersFutureProvider =
    FutureProvider.autoDispose<List<AdminInvoiceCustomerPickEntry>>((ref) {
  final search = ref.watch(_orderCustomerSearchProvider);
  return adminInvoiceCustomerRepository.fetchCustomersWithLastInvoice(
    search: search.trim().isEmpty ? null : search.trim(),
    limit: 100,
  );
});

final _orderProductSearchProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final _orderProductsFutureProvider =
    FutureProvider.autoDispose<List<CustomerProduct>>((ref) {
  final customer = ref.watch(_orderSelectedCustomerProvider);
  if (customer == null) {
    return Future.value(const <CustomerProduct>[]);
  }

  final search = ref.watch(_orderProductSearchProvider);
  return customerProductRepository.fetchProducts(
    customerId: customer.customerId,
    page: 0,
    pageSize: 50,
    search: search.trim().isEmpty ? null : search.trim(),
  );
});

final _orderNoteProvider = StateProvider.autoDispose<String>((ref) {
  return '';
});

final _orderSavingProvider = StateProvider.autoDispose<bool>((ref) {
  return false;
});

class _CartNotifier extends StateNotifier<List<AdminOrderItemDraft>> {
  _CartNotifier() : super(const <AdminOrderItemDraft>[]);

  void clear() {
    state = const <AdminOrderItemDraft>[];
  }

  void addOrMerge(AdminOrderItemDraft draft) {
    final index = state.indexWhere(
      (e) =>
          e.stockId == draft.stockId &&
          e.unitName == draft.unitName &&
          e.unitPrice == draft.unitPrice &&
          e.multiplier == draft.multiplier,
    );

    if (index == -1) {
      state = <AdminOrderItemDraft>[...state, draft];
      return;
    }

    final existing = state[index];
    final merged = AdminOrderItemDraft(
      stockId: existing.stockId,
      name: existing.name,
      unitName: existing.unitName,
      quantity: existing.quantity + draft.quantity,
      unitPrice: existing.unitPrice,
      multiplier: existing.multiplier,
    );

    final next = [...state];
    next[index] = merged;
    state = next;
  }

  void updateAt(int index, AdminOrderItemDraft nextItem) {
    if (index < 0 || index >= state.length) return;
    final next = [...state];
    next[index] = nextItem;
    state = next;
  }

  void removeAt(int index) {
    if (index < 0 || index >= state.length) return;
    final next = [...state]..removeAt(index);
    state = next;
  }
}

final _orderCartProvider =
    StateNotifierProvider.autoDispose<_CartNotifier, List<AdminOrderItemDraft>>(
  (ref) => _CartNotifier(),
);

extension on List<AdminOrderItemDraft> {
  double get total => fold(0, (sum, e) => sum + e.lineTotal);
}

class OrderCreatePage extends ConsumerStatefulWidget {
  const OrderCreatePage({super.key});

  @override
  ConsumerState<OrderCreatePage> createState() => _OrderCreatePageState();
}

class _OrderCreatePageState extends ConsumerState<OrderCreatePage> {
  final _feedbackKey = GlobalKey<_BarcodeFeedbackOverlayState>();

  final _successPlayer = AudioPlayer();
  final _errorPlayer = AudioPlayer();

  bool _audioReady = false;

  @override
  void initState() {
    super.initState();
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

  Future<void> openBarcodeCamera() async {
    if (!mounted) return;

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return const _BarcodeScannerDialog();
      },
    );

    if (!mounted) return;
    final trimmed = (code ?? '').trim();
    if (trimmed.isEmpty) return;

    await _tryAddProductByBarcode(
      context,
      trimmed,
      showNotFoundMessage: true,
    );
  }

  Future<bool> _tryAddProductByBarcode(
    BuildContext context,
    String rawBarcode, {
    required bool showNotFoundMessage,
  }) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return false;

    final customer = ref.read(_orderSelectedCustomerProvider);
    if (customer == null) return false;

    // 1) Barkod tipini stocks tablosundan çöz.
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
            'barcode.eq.$barcode,pack_barcode.eq.$barcode,box_barcode.eq.$barcode',
          )
          .maybeSingle();
    } catch (_) {
      stockRow = null;
    }

    if (stockRow == null || stockRow is! Map) {
      await _playError();
      _feedbackKey.currentState?.showError();
      if (showNotFoundMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barkod bulunamadı.')),
        );
      }
      return false;
    }

    final stockMap = Map<String, dynamic>.from(stockRow);
    final stockId = (stockMap['id'] as String?)?.trim() ?? '';
    if (stockId.isEmpty) {
      await _playError();
      _feedbackKey.currentState?.showError();
      if (showNotFoundMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barkod bulunamadı.')),
        );
      }
      return false;
    }

    String readText(String key) {
      final v = stockMap[key];
      if (v == null) return '';
      return v.toString().trim();
    }

    double readDoubleFrom(Map<String, dynamic>? map, String key) {
      final v = map?[key];
      if (v == null) return 1;
      if (v is num) return v.toDouble();
      final s = v.toString().trim();
      if (s.isEmpty) return 1;
      final normalized =
          s.contains(',') ? s.replaceAll('.', '').replaceAll(',', '.') : s;
      return double.tryParse(normalized) ?? 1;
    }

    Map<String, dynamic>? extractStockUnitsMap() {
      final units = stockMap['stock_units'];
      if (units is Map) {
        return Map<String, dynamic>.from(units);
      }
      if (units is List && units.isNotEmpty && units.first is Map) {
        return Map<String, dynamic>.from(units.first as Map);
      }
      return null;
    }

    final stockBarcode = readText('barcode');
    final packBarcode = readText('pack_barcode');
    final boxBarcode = readText('box_barcode');
    final stockUnitsMap = extractStockUnitsMap();
    final packQty = readDoubleFrom(stockUnitsMap, 'pack_qty');
    final boxQty = readDoubleFrom(stockUnitsMap, 'box_qty');

    final String unitName;
    final double multiplier;
    if (stockBarcode.isNotEmpty && stockBarcode == barcode) {
      unitName = 'adet';
      multiplier = 1;
    } else if (packBarcode.isNotEmpty && packBarcode == barcode) {
      unitName = 'paket';
      multiplier = packQty > 0 ? packQty : 0;
    } else if (boxBarcode.isNotEmpty && boxBarcode == barcode) {
      unitName = 'koli';
      multiplier = boxQty > 0 ? boxQty : 0;
    } else {
      await _playError();
      _feedbackKey.currentState?.showError();
      if (showNotFoundMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Barkod bulunamadı.')),
        );
      }
      return false;
    }

    if (unitName != 'adet' && multiplier <= 0) {
      await _playError();
      _feedbackKey.currentState?.showError();
      if (showNotFoundMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün birim dönüşüm bilgisi eksik.')),
        );
      }
      return false;
    }

    // 2) Müşteri ürünlerinden fiyat bilgisini al.
    final products = await customerProductRepository.fetchProducts(
      customerId: customer.customerId,
      page: 0,
      pageSize: 5,
      search: barcode,
    );

    final product = products.firstWhere(
      (p) => p.stockId.trim() == stockId,
      orElse: () => const CustomerProduct(
        stockId: '',
        name: '',
        code: '',
      ),
    );

    if (product.stockId.isEmpty) {
      await _playError();
      _feedbackKey.currentState?.showError();
      if (showNotFoundMessage && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu cari için ürün fiyatı bulunamadı.')),
        );
      }
      return false;
    }

    // Barkod okutulunca 1 birim (adet/paket/koli) ekle.
    final draft = AdminOrderItemDraft(
      stockId: product.stockId,
      name: product.name,
      unitName: unitName,
      quantity: 1,
      unitPrice: product.baseUnitPrice,
      multiplier: unitName == 'adet' ? 1 : multiplier,
    );

    ref.read(_orderCartProvider.notifier).addOrMerge(draft);

    await _playSuccess();
    _feedbackKey.currentState?.showSuccess(
      productName: product.name,
      unit: unitName,
      multiplier: unitName == 'adet' ? null : multiplier,
    );

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customerSearch = ref.watch(_orderCustomerSearchProvider);
    final selectedCustomer = ref.watch(_orderSelectedCustomerProvider);
    final customersAsync = ref.watch(_orderCustomersFutureProvider);
    final productSearch = ref.watch(_orderProductSearchProvider);
    final productsAsync = ref.watch(_orderProductsFutureProvider);
    final cart = ref.watch(_orderCartProvider);
    final note = ref.watch(_orderNoteProvider);
    final saving = ref.watch(_orderSavingProvider);

    return AppScaffold(
      title: 'Yeni Sipariş',
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1000;
              final padding = EdgeInsets.all(isWide ? 24 : 12);

          Widget buildHeader() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sipariş oluştur',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Önce cariyi seçin, sonra ürünleri sepete ekleyin ve kaydedin. Sipariş numarası otomatik oluşturulur.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            );
          }

          Widget buildCustomerCard({required bool fillHeight}) {
            Widget buildList() {
              return customersAsync.when(
                loading: () => const AppLoadingState(),
                error: (e, _) => AppErrorState(message: 'Cari yüklenemedi: $e'),
                data: (customers) {
                  if (customers.isEmpty) {
                    return const AppEmptyState(
                      title: 'Cari bulunamadı',
                      subtitle:
                          'Henüz cari tanımlı değil veya görüntüleme yetkiniz yok.',
                    );
                  }

                  return ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final c = customers[index];
                      final isSelected =
                          selectedCustomer?.customerId == c.customerId;
                      final subtitle = <String>[
                        if ((c.customerCode ?? '').trim().isNotEmpty)
                          'Kod: ${c.customerCode}',
                        if ((c.phone ?? '').trim().isNotEmpty) c.phone!,
                        if ((c.lastInvoiceNo ?? '').trim().isNotEmpty)
                          'Son fatura: ${c.lastInvoiceNo}',
                      ].join(' • ');

                      return ListTile(
                        title: Text(c.displayName),
                        subtitle:
                            subtitle.trim().isEmpty ? null : Text(subtitle),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : null,
                        onTap: saving
                            ? null
                            : () {
                                ref
                                    .read(_orderSelectedCustomerProvider
                                        .notifier)
                                    .state = c;
                                ref.read(_orderProductSearchProvider.notifier)
                                    .state = '';
                                ref.read(_orderCartProvider.notifier).clear();
                              },
                      );
                    },
                  );
                },
              );
            }

            final listWidget = fillHeight
                ? Expanded(child: buildList())
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: buildList(),
                  );

            return Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cari',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (selectedCustomer != null)
                          Text(
                            'Seçili',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    AppSearchField(
                      hintText: 'Cari adı / telefon / kod ara',
                      initialValue: customerSearch,
                      padded: false,
                      onChanged: saving
                          ? null
                          : (value) {
                              ref
                                  .read(_orderCustomerSearchProvider.notifier)
                                  .state = value;
                            },
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    if (selectedCustomer != null) ...[
                      Text(
                        'Seçili cari: ${selectedCustomer.displayName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                    ],
                    listWidget,
                  ],
                ),
              ),
            );
          }

          Widget buildProductCard({required bool fillHeight}) {
            final enabled = selectedCustomer != null && !saving;

            Widget buildList() {
              if (selectedCustomer == null) {
                return const AppEmptyState(
                  title: 'Önce cari seçin',
                  subtitle:
                      'Ürünleri listelemek için önce sipariş oluşturulacak cariyi seçin.',
                );
              }

              return productsAsync.when(
                loading: () => const AppLoadingState(),
                error: (e, _) => AppErrorState(message: 'Ürünler yüklenemedi: $e'),
                data: (products) {
                  if (products.isEmpty) {
                    return const AppEmptyState(
                      title: 'Ürün bulunamadı',
                      subtitle:
                          'Arama kriterlerinize uygun ürün bulunamadı veya cari için fiyat tanımı yok.',
                    );
                  }

                  return ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = products[index];

                      final price = p.effectivePrice ?? p.baseUnitPrice;
                      final subtitleParts = <String>[
                        if (p.code.trim().isNotEmpty) 'Kod: ${p.code}',
                        'Fiyat: ${formatMoney(price)}',
                      ];

                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text(subtitleParts.join(' • ')),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Satış geçmişi',
                              icon: const Icon(Icons.history_outlined),
                              onPressed: !enabled
                                  ? null
                                  : () => _showProductSalesHistorySheet(
                                        context: context,
                                        customerId: selectedCustomer.customerId,
                                        product: p,
                                      ),
                            ),
                            IconButton(
                              tooltip: 'Sepete ekle',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: !enabled
                                  ? null
                                  : () async {
                                      final draft =
                                          await _showAddOrEditItemDialog(
                                        context: context,
                                        product: p,
                                      );
                                      if (draft == null) return;
                                      ref
                                          .read(_orderCartProvider.notifier)
                                          .addOrMerge(draft);
                                    },
                            ),
                          ],
                        ),
                        onTap: !enabled
                            ? null
                            : () async {
                                final draft = await _showAddOrEditItemDialog(
                                  context: context,
                                  product: p,
                                );
                                if (draft == null) return;
                                ref.read(_orderCartProvider.notifier)
                                    .addOrMerge(draft);
                              },
                      );
                    },
                  );
                },
              );
            }

            final listWidget = fillHeight
                ? Expanded(child: buildList())
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: buildList(),
                  );

            return Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ürünler',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    Text(
                      'Barkod okut',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    _BarcodeInputField(
                      enabled: enabled,
                      onBarcode: (code, showNotFound) =>
                          _tryAddProductByBarcode(
                        context,
                        code,
                        showNotFoundMessage: showNotFound,
                      ),
                      onScanTap: enabled ? openBarcodeCamera : null,
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    AppSearchField(
                      hintText: 'Ürün adı / kod / barkod ara',
                      initialValue: productSearch,
                      padded: false,
                      onChanged: enabled
                          ? (value) {
                              ref
                                  .read(_orderProductSearchProvider.notifier)
                                  .state = value;
                            }
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    listWidget,
                  ],
                ),
              ),
            );
          }

          Widget buildCartCard({required bool fillHeight}) {
            final canSave =
                selectedCustomer != null && cart.isNotEmpty && !saving;

            Widget buildList() {
              if (cart.isEmpty) {
                return const AppEmptyState(
                  title: 'Sepet boş',
                  subtitle: 'Ürün listesinden ürün ekleyin.',
                );
              }

              return ListView.separated(
                itemCount: cart.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = cart[index];
                  final subtitle =
                      '${item.quantity.toStringAsFixed(2)} ${item.unitName} • '
                      '${formatMoney(item.shownUnitPrice)} • '
                      'Tutar: ${formatMoney(item.lineTotal)}';

                  return ListTile(
                    title: Text(item.name),
                    subtitle: Text(subtitle),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Düzenle',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: saving
                              ? null
                              : () async {
                                  final edited =
                                      await _showEditDraftDialog(
                                    context: context,
                                    current: item,
                                  );
                                  if (edited == null) return;
                                  ref.read(_orderCartProvider.notifier)
                                      .updateAt(index, edited);
                                },
                        ),
                        IconButton(
                          tooltip: 'Sil',
                          icon: const Icon(Icons.delete_outline),
                          onPressed:
                              saving ? null : () => ref.read(_orderCartProvider.notifier).removeAt(index),
                        ),
                      ],
                    ),
                  );
                },
              );
            }

            final listWidget = fillHeight
                ? Expanded(child: buildList())
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: buildList(),
                  );

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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Kalem: ${cart.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        Text(
                          'Toplam: ${formatMoney(cart.total)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    listWidget,
                    const SizedBox(height: AppSpacing.s12),
                    TextFormField(
                      enabled: !saving,
                      initialValue: note,
                      decoration: const InputDecoration(
                        labelText: 'Not (opsiyonel)',
                        hintText: 'Sipariş notu...',
                      ),
                      maxLines: 2,
                      onChanged: (value) {
                        ref.read(_orderNoteProvider.notifier).state = value;
                      },
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canSave
                            ? () => _save(context, ref)
                            : null,
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(saving ? 'Kaydediliyor...' : 'Siparişi Kaydet'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!isWide) {
            return ListView(
              padding: padding,
              children: [
                buildHeader(),
                const SizedBox(height: 12),
                buildCustomerCard(fillHeight: false),
                const SizedBox(height: 12),
                buildProductCard(fillHeight: false),
                const SizedBox(height: 12),
                buildCartCard(fillHeight: false),
              ],
            );
          }

          return Padding(
            padding: padding,
            child: SizedBox.expand(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildHeader(),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: buildCustomerCard(fillHeight: true)),
                              const SizedBox(height: 12),
                              Expanded(child: buildProductCard(fillHeight: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: buildCartCard(fillHeight: true),
                  ),
                ],
              ),
            ),
          );
            },
          ),
          BarcodeFeedbackOverlay(key: _feedbackKey),
        ],
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

    final theme = Theme.of(context);
    final bg = _isSuccess
        ? theme.colorScheme.secondary
        : theme.colorScheme.error;
    final fg = _isSuccess
        ? theme.colorScheme.onSecondary
        : theme.colorScheme.onError;

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
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: fg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((_productName ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _productName!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if ((_detail ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _detail!,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: fg,
                            fontWeight: FontWeight.w600,
                          ),
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

class _BarcodeInputField extends StatefulWidget {
  const _BarcodeInputField({
    required this.enabled,
    required this.onBarcode,
    this.onScanTap,
  });

  final bool enabled;

  /// Returns true if barcode was successfully added to cart.
  final Future<bool> Function(String code, bool showNotFoundMessage) onBarcode;

  final VoidCallback? onScanTap;

  @override
  State<_BarcodeInputField> createState() => _BarcodeInputFieldState();
}

class _BarcodeInputFieldState extends State<_BarcodeInputField> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitFromEnter(String value) async {
    if (!widget.enabled) return;

    final code = value.trim();
    if (code.isEmpty) return;
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      await widget.onBarcode(code, true);
    } finally {
      if (mounted) {
        _controller.clear();
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled && !_busy,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: 'Barkod okut veya yaz',
        suffixIcon: widget.onScanTap == null
            ? null
            : IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Kamerayla okut',
                onPressed: (widget.enabled && !_busy) ? widget.onScanTap : null,
              ),
      ),
      onSubmitted: (value) {
        _submitFromEnter(value);
      },
    );
  }
}

class _BarcodeScannerDialog extends StatefulWidget {
  const _BarcodeScannerDialog();

  @override
  State<_BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<_BarcodeScannerDialog> {
  bool _handled = false;

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((s) => s.trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;

    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          children: [
            MobileScanner(
              onDetect: _handleDetect,
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Barkod okut',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitOption {
  const _UnitOption({
    required this.unitName,
    required this.multiplier,
  });

  final String unitName;
  final double multiplier;
}

Future<void> _showProductSalesHistorySheet({
  required BuildContext context,
  required String customerId,
  required CustomerProduct product,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _ProductSalesHistorySheet(
        customerId: customerId,
        stockId: product.stockId,
        productName: product.name,
      );
    },
  );
}

class _ProductSalesHistorySheet extends StatefulWidget {
  const _ProductSalesHistorySheet({
    required this.customerId,
    required this.stockId,
    required this.productName,
  });

  final String customerId;
  final String stockId;
  final String productName;

  @override
  State<_ProductSalesHistorySheet> createState() =>
      _ProductSalesHistorySheetState();
}

class _ProductSalesHistorySheetState
    extends State<_ProductSalesHistorySheet> {
  late final Future<List<AdminCustomerProductSaleHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = adminOrderRepository.fetchCustomerProductSaleHistory(
      customerId: widget.customerId,
      stockId: widget.stockId,
      limit: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Satış Geçmişi',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.productName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<AdminCustomerProductSaleHistoryEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return AppErrorState(
                    message: 'Geçmiş yüklenemedi: ${snapshot.error}',
                  );
                }

                final items = snapshot.data ?? const <AdminCustomerProductSaleHistoryEntry>[];
                if (items.isEmpty) {
                  return const AppEmptyState(
                    title: 'Kayıt bulunamadı',
                    subtitle: 'Bu ürün için geçmiş satış kaydı bulunamadı.',
                  );
                }

                final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final e = items[index];

                      final doc = (e.orderNo != null && e.orderNo! > 0)
                          ? 'SIP-${e.orderNo!.toString().padLeft(6, '0')}'
                          : 'Sipariş';

                      final subtitle = <String>[
                        formatDateTime(e.orderCreatedAt),
                        'Miktar: ${formatQtyTr(e.qty)} ${e.unitName}',
                        'Birim: ${formatMoney(e.unitPrice)}',
                        'Tutar: ${formatMoney(e.lineTotal)}',
                      ].where((s) => s.trim().isNotEmpty).join(' • ');

                      return ListTile(
                        dense: true,
                        title: Text(doc),
                        subtitle: Text(subtitle),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<AdminOrderItemDraft?> _showAddOrEditItemDialog({
  required BuildContext context,
  required CustomerProduct product,
}) {
  final options = <_UnitOption>[
    _UnitOption(unitName: product.baseUnitName, multiplier: 1),
    if ((product.packMultiplier ?? 0) > 1)
      _UnitOption(
        unitName: (product.packUnitName?.trim().isNotEmpty ?? false)
            ? product.packUnitName!.trim()
            : 'Paket',
        multiplier: product.packMultiplier!,
      ),
    if ((product.boxMultiplier ?? 0) > 1)
      _UnitOption(
        unitName: (product.boxUnitName?.trim().isNotEmpty ?? false)
            ? product.boxUnitName!.trim()
            : 'Koli',
        multiplier: product.boxMultiplier!,
      ),
  ];

  return _showDraftDialog(
    context: context,
    title: product.name,
    stockId: product.stockId,
    defaultName: product.name,
    baseUnitPrice: product.baseUnitPrice,
    unitOptions: options,
  );
}

Future<AdminOrderItemDraft?> _showEditDraftDialog({
  required BuildContext context,
  required AdminOrderItemDraft current,
}) {
  final options = <_UnitOption>[
    _UnitOption(
      unitName: current.unitName,
      multiplier: current.multiplier,
    ),
  ];

  return _showDraftDialog(
    context: context,
    title: 'Kalem düzenle',
    stockId: current.stockId,
    defaultName: current.name,
    baseUnitPrice: current.unitPrice,
    unitOptions: options,
    actionLabel: 'Kaydet',
    initialQuantity: current.quantity,
    initialUnitName: current.unitName,
    initialMultiplier: current.multiplier,
  );
}

Future<AdminOrderItemDraft?> _showDraftDialog({
  required BuildContext context,
  required String title,
  required String stockId,
  required String defaultName,
  required double baseUnitPrice,
  required List<_UnitOption> unitOptions,
  String actionLabel = 'Ekle',
  double? initialQuantity,
  String? initialUnitName,
  double? initialMultiplier,
}) {
  final _UnitOption initialUnit = () {
    final name = initialUnitName?.trim();
    if (name == null || name.isEmpty) {
      return unitOptions.first;
    }

    if (initialMultiplier != null) {
      final m = initialMultiplier;
      return unitOptions.firstWhere(
        (u) => u.unitName == name && (u.multiplier - m).abs() < 0.000001,
        orElse: () => unitOptions.firstWhere(
          (u) => u.unitName == name,
          orElse: () => unitOptions.first,
        ),
      );
    }

    return unitOptions.firstWhere(
      (u) => u.unitName == name,
      orElse: () => unitOptions.first,
    );
  }();

  final qtyController = TextEditingController(
    text: (initialQuantity ?? 1).toStringAsFixed(2),
  );

  final baseUnitPriceNotifier = ValueNotifier<double>(baseUnitPrice);
  final selectedUnitNotifier = ValueNotifier<_UnitOption>(initialUnit);
  final qtyNotifier = ValueNotifier<double?>(null);

  double? parseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  qtyNotifier.value = parseDouble(qtyController.text);
  qtyController.addListener(() {
    qtyNotifier.value = parseDouble(qtyController.text);
  });

  Future<void> openEditPriceDialog(_UnitOption selectedUnit) async {
    final safeMultiplier =
        selectedUnit.multiplier <= 0 ? 1.0 : selectedUnit.multiplier;
    final currentShownPrice = baseUnitPriceNotifier.value * safeMultiplier;

    final controller = TextEditingController(
      text: currentShownPrice.toStringAsFixed(2),
    );

    final next = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Birim fiyatı düzenle'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bu değişiklik sadece bu sipariş kalemi için geçerlidir.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'Birim fiyat (${selectedUnit.unitName})',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final v = parseDouble(controller.text);
                if (v == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Geçerli bir fiyat girin.')),
                  );
                  return;
                }
                if (v < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Birim fiyat negatif olamaz.'),
                    ),
                  );
                  return;
                }

                Navigator.of(context).pop(v);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    if (next == null) return;

    // Girilen fiyat seçili birim için; RPC tarafı baz birim fiyatı bekliyor.
    baseUnitPriceNotifier.value = next / safeMultiplier;
  }

  return showDialog<AdminOrderItemDraft>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<_UnitOption>(
                valueListenable: selectedUnitNotifier,
                builder: (context, selectedUnit, _) {
                  if (unitOptions.length <= 1) {
                    return InputDecorator(
                      decoration: const InputDecoration(labelText: 'Birim'),
                      child: Text(selectedUnit.unitName),
                    );
                  }

                  return DropdownButtonFormField<_UnitOption>(
                    key: ValueKey(
                      'unit-${selectedUnit.unitName}-${selectedUnit.multiplier}',
                    ),
                    initialValue: selectedUnit,
                    items: unitOptions
                        .map(
                          (o) => DropdownMenuItem<_UnitOption>(
                            value: o,
                            child: Text(o.unitName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (_UnitOption? next) {
                      if (next == null) return;
                      selectedUnitNotifier.value = next;
                    },
                    decoration: const InputDecoration(labelText: 'Birim'),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                decoration: const InputDecoration(
                  labelText: 'Miktar',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<_UnitOption>(
                valueListenable: selectedUnitNotifier,
                builder: (context, selectedUnit, _) {
                  return ValueListenableBuilder<double?>(
                    valueListenable: qtyNotifier,
                    builder: (context, enteredQty, __) {
                      return ValueListenableBuilder<double>(
                        valueListenable: baseUnitPriceNotifier,
                        builder: (context, currentBaseUnitPrice, ___) {
                          final safeMultiplier = selectedUnit.multiplier <= 0
                              ? 1.0
                              : selectedUnit.multiplier;
                          final safeQty = enteredQty ?? 0;
                          final realQty = safeQty * safeMultiplier;
                          final shownPrice = currentBaseUnitPrice * safeMultiplier;
                          final lineTotal = realQty * currentBaseUnitPrice;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Birim fiyat (${selectedUnit.unitName}): ${formatMoney(shownPrice)}',
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Düzenle',
                                    onPressed: () => openEditPriceDialog(selectedUnit),
                                    icon: const Icon(Icons.edit),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Toplam: ${formatMoney(lineTotal)}',
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () {
              final qty = parseDouble(qtyController.text) ?? 0;
              final selectedUnit = selectedUnitNotifier.value;
              final unitName = selectedUnit.unitName;
              final currentBaseUnitPrice = baseUnitPriceNotifier.value;
              final multiplier =
                  selectedUnit.multiplier <= 0 ? 1.0 : selectedUnit.multiplier;
              if (qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Miktar 0 olamaz.')),
                );
                return;
              }
              if (currentBaseUnitPrice < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Birim fiyat negatif olamaz.')),
                );
                return;
              }
              if (multiplier <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Geçersiz birim çarpanı.')),
                );
                return;
              }

              Navigator.of(context).pop(
                AdminOrderItemDraft(
                  stockId: stockId,
                  name: defaultName,
                  unitName: unitName,
                  quantity: qty,
                  unitPrice: currentBaseUnitPrice,
                  multiplier: multiplier,
                ),
              );
            },
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
}

Future<void> _save(BuildContext context, WidgetRef ref) async {
  final customer = ref.read(_orderSelectedCustomerProvider);
  final items = ref.read(_orderCartProvider);
  final note = ref.read(_orderNoteProvider).trim();

  if (customer == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lütfen önce cari seçin.')),
    );
    return;
  }
  if (items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sepet boş. Lütfen ürün ekleyin.')),
    );
    return;
  }

  ref.read(_orderSavingProvider.notifier).state = true;
  try {
    final result = await adminOrderRepository.createOrderWithItemsRpc(
      customerId: customer.customerId,
      note: note.isEmpty ? null : note,
      items: items,
    );
    final orderId = result.orderId;
    final orderNo = result.orderNo;
    final formattedOrderNo = 'SIP-${orderNo.toString().padLeft(6, '0')}';

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sipariş oluşturuldu: $formattedOrderNo')),
    );
    context.go('/orders/$orderId');
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sipariş kaydedilemedi: ${AppException.messageOf(e)}'),
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(_orderSavingProvider.notifier).state = false;
    }
  }
}
