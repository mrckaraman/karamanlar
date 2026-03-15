import 'package:core/core.dart' hide isValidUuid;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/formatters_tr.dart';
import '../../utils/uuid_utils.dart';
import '../invoices/invoice_providers.dart';
import 'orders_list_page.dart'
  show ordersFiltersProvider, adminOrdersProvider, adminOrderCountsProvider;
import 'services/order_print_service.dart';
import 'widgets/order_status_chip.dart';

final _orderDetailProvider =
    FutureProvider.family.autoDispose<AdminOrderDetail, String>((ref, id) {
  return adminOrderRepository.fetchOrderDetail(id);
});

class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _saving = false;
  String? _note;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (!isValidUuid(widget.orderId)) {
      return const AppScaffold(
        title: 'Sipariş Detayı',
        body: Center(
          child: Text('Geçersiz sipariş ID bilgisi.'),
        ),
      );
    }

    final detailAsync = ref.watch(_orderDetailProvider(widget.orderId));

    final printButton = IconButton(
      tooltip: 'Yazdır',
      icon: const Icon(Icons.print),
      onPressed: detailAsync.maybeWhen(
        data: (detail) {
          return () async {
            await OrderPrintService.printOrder(detail);
          };
        },
        orElse: () => null,
      ),
    );

    return AppScaffold(
      title: 'Sipariş Detayı',
      actions: [printButton],
      body: detailAsync.when(
        loading: () => const AppLoadingState(),
        error: (e, _) => AppErrorState(
          message: 'Sipariş detayı yüklenemedi: $e',
          onRetry: () => ref.invalidate(_orderDetailProvider(widget.orderId)),
        ),
        data: (detail) {
          _note ??= detail.note;

          final items = detail.items;
          final orderNo = detail.orderNo;
          final nextStatus = _nextStatus(detail.status);

          final orderLabel = orderNo != null ? 'Sipariş #$orderNo' : 'Sipariş';
          final dateText = _formatDate(detail.createdAt);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.customerName,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
                            '$orderLabel • $dateText',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        OrderStatusChip(status: detail.status),
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          _formatAmount(detail.totalAmount),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                if ((_note ?? '').trim().isNotEmpty)
                  Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Not',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text((_note ?? '').trim()),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.s12),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kalemler',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          if (items.isEmpty)
                            const Text(
                              'Bu sipariş için kalem bulunamadı.',
                            ),
                          if (items.isNotEmpty)
                            Expanded(
                              child: ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  final qtyText =
                                      '${formatQtyTr(item.quantity)} ${item.unit}';
                                  final unitPriceText =
                                      formatMoney(item.unitPrice);
                                  final lineTotalText =
                                      _formatAmount(item.lineTotal);

                                  return ListTile(
                                    title: Text(item.name),
                                    subtitle: Text(
                                      '$qtyText x $unitPriceText',
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(lineTotalText),
                                        const SizedBox(
                                          width: AppSpacing.s4,
                                        ),
                                        PopupMenuButton<_OrderItemMenuAction>(
                                          tooltip: 'Kalem işlemleri',
                                          onSelected: (action) {
                                            switch (action) {
                                              case _OrderItemMenuAction.edit:
                                                _showEditItemSheet(
                                                  detail,
                                                  item,
                                                );
                                                break;
                                              case _OrderItemMenuAction.delete:
                                                _confirmDeleteItem(
                                                  detail,
                                                  item,
                                                );
                                                break;
                                            }
                                          },
                                          itemBuilder: (context) => const [
                                            PopupMenuItem<_OrderItemMenuAction>(
                                              value: _OrderItemMenuAction.edit,
                                              child: Text('Düzenle'),
                                            ),
                                            PopupMenuItem<_OrderItemMenuAction>(
                                              value:
                                                  _OrderItemMenuAction.delete,
                                              child: Text('Sil'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: AppSpacing.s8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Toplam: ${formatMoney(detail.totalAmount)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  children: [
                    if (_detailPrimaryActionLabel(detail.status) != null &&
                        nextStatus != null)
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await _updateStatus(
                                    detail,
                                    nextStatus,
                                  );
                                },
                          child: Text(
                            _detailPrimaryActionLabel(detail.status)!,
                          ),
                        ),
                      ),
                    if (_detailPrimaryActionLabel(detail.status) != null &&
                        nextStatus != null)
                      const SizedBox(width: AppSpacing.s8),
                    if (!_isCancelled(detail.status) &&
                        !_isShipped(detail.status))
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  await _showCancelDialog(detail);
                                },
                          child: const Text('İptal et'),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _updateStatus(
    AdminOrderDetail detail,
    String newStatus,
  ) async {
    final current = detail.status.trim().toLowerCase();
    final next = newStatus.trim().toLowerCase();
    if (current == next) {
      return;
    }

    final isApproveTransition = current == 'new' && next == 'approved';
    final isCompleteTransition = next == 'completed';

    try {
      setState(() {
        _saving = true;
      });
      if (isApproveTransition) {
        try {
          await supabaseClient.rpc(
            'rpc_approve_order',
            params: <String, dynamic>{'p_order_id': widget.orderId},
          );
        } on PostgrestException catch (e) {
          if (kDebugMode) {
            debugPrint(
              'approve failed (detail): \\${e.code} \\${e.message} \\${e.details}',
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Onay başarısız: \\${e.message}'),
              ),
            );
          }
          rethrow;
        }
      } else {
        await adminOrderRepository.updateOrderStatus(
          orderId: widget.orderId,
          status: next,
        );
      }

      if (isCompleteTransition) {
        String? invoiceId;
        try {
          invoiceId = await adminInvoiceRepository.convertOrderToInvoice(
            orderId: widget.orderId,
          );
          if (kDebugMode) {
            debugPrint('[ADMIN] invoice created: $invoiceId');
          }
        } catch (e) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fatura oluşturulamadı: $e'),
            ),
          );
          return;
        }

        final filter = ref.read(ordersFiltersProvider);
        ref.invalidate(adminOrdersProvider(filter));
        ref.invalidate(adminOrderCountsProvider(filter));
        ref.invalidate(_orderDetailProvider(widget.orderId));
        ref.read(adminInvoicesReloadTokenProvider.notifier).state++;

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sipariş tamamlandı ve faturaya dönüştürüldü.'),
          ),
        );

        if (invoiceId.isNotEmpty) {
          context.go('/invoices/$invoiceId');
        }
      } else {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isApproveTransition
                  ? 'Sipariş onaylandı'
                  : 'Sipariş durumu başarıyla güncellendi.',
            ),
          ),
        );
        ref.invalidate(_orderDetailProvider(widget.orderId));
      }
    } on PostgrestException {
      // Hata üstte handle edildi, sadece _saving sıfırlansın.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Durum güncellenemedi: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _showCancelDialog(AdminOrderDetail detail) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Siparişi iptal et?'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'İptal sebebi (opsiyonel)',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('İptal Et'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final reason = controller.text.trim();
    final existingNote = (detail.note ?? '').trim();
    String? newNote = existingNote.isEmpty ? null : existingNote;
    if (reason.isNotEmpty) {
      final cancelLine = 'İptal: $reason';
      if (newNote == null || newNote.isEmpty) {
        newNote = cancelLine;
      } else {
        newNote = '$newNote\n$cancelLine';
      }
    }

    try {
      setState(() {
        _saving = true;
      });
      await adminOrderRepository.updateOrderStatusAndNote(
        orderId: widget.orderId,
        status: 'cancelled',
        note: newNote,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sipariş iptal edildi.'),
        ),
      );
      ref.invalidate(_orderDetailProvider(widget.orderId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İptal işlemi başarısız: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

enum _OrderItemMenuAction { edit, delete }

extension on AdminOrderItemEntry {
  String get idOrStockId => id.isNotEmpty ? id : stockId;
}

extension on BuildContext {
  void showSnackBarMessage(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

extension _AdminOrderDetailActions on _OrderDetailPageState {
  Future<void> _showEditItemSheet(
    AdminOrderDetail detail,
    AdminOrderItemEntry item,
  ) async {
    final theme = Theme.of(context);
    final pageContext = context;

    final qtyController = TextEditingController(
      text: formatQtyTr(item.quantity),
    );
    final priceController = TextEditingController(
      text: item.unitPrice.toStringAsFixed(2),
    );

    String currentUnit = item.unit.trim();
    bool currentUnitInitialized = false;

    double parseTrNumber(String raw) {
      var text = raw.trim();
      if (text.isEmpty) return 0;

      // Remove currency symbols and spaces (including non-breaking space).
      text = text.replaceAll(RegExp(r'[\s\u00A0₺]'), '');

      // If comma exists, treat comma as decimal separator.
      if (text.contains(',')) {
        text = text.replaceAll('.', '');
        text = text.replaceAll(',', '.');
      }

      // Keep only digits, minus and dot.
      text = text.replaceAll(RegExp(r'[^0-9\-.]'), '');

      return double.tryParse(text) ?? 0;
    }

    Future<List<AdminUnitOption>> unitsFuture =
        adminOrderRepository.fetchStockUnitOptions(item.stockId);

    await showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      builder: (sheetContext) {
        bool saving = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

            return FutureBuilder<List<AdminUnitOption>>(
              future: unitsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.s16,
                      right: AppSpacing.s16,
                      top: AppSpacing.s12,
                      bottom: bottomInset + AppSpacing.s12,
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: AppSpacing.s16,
                      right: AppSpacing.s16,
                      top: AppSpacing.s12,
                      bottom: bottomInset + AppSpacing.s12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Birimler yüklenemedi.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          '${snapshot.error}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              setModalState(() {
                                unitsFuture = adminOrderRepository
                                    .fetchStockUnitOptions(item.stockId);
                              });
                            },
                            child: const Text('Tekrar dene'),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final options = snapshot.data ?? const <AdminUnitOption>[];

                double unitMultiplierFor(String unitName) {
                  final trimmed = unitName.trim();
                  if (trimmed.isEmpty) return 1;

                  final opt = options.cast<AdminUnitOption?>().firstWhere(
                        (o) => o != null && o.name == trimmed,
                        orElse: () => null,
                      );
                  final m = opt?.multiplier ?? 1;
                  return m > 0 ? m : 1;
                }

                if (!currentUnitInitialized) {
                  // selectedUnitName benzeri: daha önce seçili birim varsa onu kullan,
                  // yoksa item.unit'ten gel.
                  final selectedUnitName = currentUnit;
                  final baseUnit = (selectedUnitName.isNotEmpty
                          ? selectedUnitName
                          : item.unit)
                      .trim();
                  currentUnit = baseUnit;

                  final names = options.map((e) => e.name).toSet();
                  // currentUnit boşsa veya options içinde yoksa -> default/first fallback
                  if (currentUnit.isEmpty || !names.contains(currentUnit)) {
                    AdminUnitOption? chosen;
                    final defaults = options.where((o) => o.isDefault).toList();
                    if (defaults.isNotEmpty) {
                      chosen = defaults.first;
                    } else if (options.isNotEmpty) {
                      chosen = options.first;
                    }
                    if (chosen != null) {
                      currentUnit = chosen.name;
                    } else {
                      // Hiç birim yoksa dropdown'da null kullanabilmek için boş bırak.
                      currentUnit = '';
                    }
                  }

                  currentUnitInitialized = true;
                }

                final qtyPreview = parseTrNumber(qtyController.text);
                final pricePreview = parseTrNumber(priceController.text);

                final realQtyPreview =
                  qtyPreview * unitMultiplierFor(currentUnit);

                final bool hasPreview = qtyPreview > 0 && pricePreview >= 0;
                final double? linePreview =
                  hasPreview ? realQtyPreview * pricePreview : null;
                final String linePreviewText =
                    linePreview != null ? _formatAmount(linePreview) : '-';

                final bool hasUnits = options.isNotEmpty;
                final Widget unitField;
                if (!hasUnits) {
                  unitField = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Birim',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        'Birim bulunamadı',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  );
                } else {
                  unitField = DropdownButtonFormField<String>(
                    initialValue: currentUnit.isNotEmpty ? currentUnit : null,
                    decoration: const InputDecoration(
                      labelText: 'Birim',
                    ),
                    items: options
                        .map(
                          (opt) => DropdownMenuItem<String>(
                            value: opt.name,
                            child: Text(
                              '${opt.name} (${_formatUnitMultiplier(opt.multiplier)} adet)',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() {
                        currentUnit = value;
                      });
                    },
                  );
                }

                return Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.s16,
                    right: AppSpacing.s16,
                    top: AppSpacing.s12,
                    bottom: bottomInset + AppSpacing.s12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Kalem düzenle',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        item.name,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      unitField,
                      const SizedBox(height: AppSpacing.s12),
                      TextFormField(
                        controller: qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Miktar',
                        ),
                        onChanged: (_) {
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      TextFormField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Birim fiyat',
                        ),
                        onChanged: (_) {
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Satır Toplamı',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            linePreviewText,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: saving || !hasUnits
                              ? null
                              : () async {
                                  final qtyText =
                                      qtyController.text;
                                  final priceText = priceController.text;

                                  final qty = parseTrNumber(qtyText);
                                  final unitPrice = parseTrNumber(priceText);

                                  if (qty <= 0) {
                                    context.showSnackBarMessage(
                                      'Miktar 0 dan büyük olmalı.',
                                    );
                                    return;
                                  }
                                  if (unitPrice < 0) {
                                    context.showSnackBarMessage(
                                      'Birim fiyat 0 veya daha büyük olmalı.',
                                    );
                                    return;
                                  }

                                  setModalState(() {
                                    saving = true;
                                  });

                                  try {
                                    final realQty =
                                        qty * unitMultiplierFor(currentUnit);
                                    final lineTotal = realQty * unitPrice;
                                    await adminOrderRepository.updateOrderItem(
                                      itemId: item.idOrStockId,
                                      qty: qty,
                                      unitName: currentUnit,
                                      unitPrice: unitPrice,
                                      lineTotal: lineTotal,
                                    );
                                    await adminOrderRepository
                                        .recalculateOrderTotal(detail.id);
                                    if (!mounted) return;
                                    ref.invalidate(
                                      _orderDetailProvider(widget.orderId),
                                    );
                                    if (!pageContext.mounted) return;
                                    Navigator.of(pageContext).pop();
                                    pageContext.showSnackBarMessage(
                                      'Kalem güncellendi.',
                                    );
                                  } catch (e) {
                                    if (!mounted || !pageContext.mounted) {
                                      return;
                                    }
                                    pageContext.showSnackBarMessage(
                                      'Kalem güncellenemedi: $e',
                                    );
                                  } finally {
                                    if (mounted) {
                                      setModalState(() {
                                        saving = false;
                                      });
                                    }
                                  }
                                },
                          child: saving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Kaydet'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteItem(
    AdminOrderDetail detail,
    AdminOrderItemEntry item,
  ) async {
    final pageContext = context;

    final confirmed = await showDialog<bool>(
      context: pageContext,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kalemi sil'),
          content: Text(
            'Bu kalemi silmek istiyor musun?\n\n${item.name}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await adminOrderRepository.deleteOrderItem(item.idOrStockId);
      await adminOrderRepository.recalculateOrderTotal(detail.id);
      if (!mounted || !pageContext.mounted) return;
      ref.invalidate(_orderDetailProvider(widget.orderId));
      pageContext.showSnackBarMessage('Kalem silindi.');
    } catch (e) {
      if (!mounted || !pageContext.mounted) return;
      pageContext.showSnackBarMessage('Kalem silinemedi: $e');
    }
  }
}

String _formatDate(DateTime date) {
  return formatDate(date);
}

String _formatAmount(double value) {
  return formatMoney(value);
}

String _formatUnitMultiplier(double multiplier) {
  if (multiplier % 1 == 0) {
    return multiplier.toInt().toString();
  }
  return multiplier.toString();
}

String? _detailPrimaryActionLabel(String status) {
  final s = status.trim().toLowerCase();
  switch (s) {
    case 'new':
      return 'Onayla';
    case 'approved':
      return 'Hazırlanıyor';
    case 'preparing':
      return 'Sevk edildi';
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

bool _isCancelled(String status) => status.trim().toLowerCase() == 'cancelled';

bool _isShipped(String status) => status.trim().toLowerCase() == 'shipped';
