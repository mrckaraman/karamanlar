import 'package:core/core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/formatters_tr.dart';
import '../return_create_controller.dart';
import '../return_strings.dart';
import '../../stocks/barcode_scanner_page.dart';
import 'return_empty_state.dart';

class ReturnProductPickerCard extends ConsumerStatefulWidget {
  const ReturnProductPickerCard({
    super.key,
    required this.stepBadge,
  });

  final String stepBadge;

  @override
  ConsumerState<ReturnProductPickerCard> createState() =>
      _ReturnProductPickerCardState();
}

class _ReturnProductPickerCardState
    extends ConsumerState<ReturnProductPickerCard> {
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _unitPriceController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _unitPriceFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();

  String _selectedUnit = ReturnStrings.unitPiece;

  @override
  void dispose() {
    _qtyController.dispose();
    _unitPriceController.dispose();
    _noteController.dispose();
    _qtyFocus.dispose();
    _unitPriceFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  double? _parseNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  void _applyProductToForm(core.CustomerProduct product) {
    final rawUnitName = product.baseUnitName.trim();
    final normalizedUnitName = rawUnitName.toLowerCase();

    String selectedUnit;
    if (normalizedUnitName.contains('adet')) {
      selectedUnit = ReturnStrings.unitPiece;
    } else if (normalizedUnitName.contains('koli')) {
      selectedUnit = ReturnStrings.unitBox;
    } else if (normalizedUnitName.contains('paket')) {
      selectedUnit = ReturnStrings.unitPack;
    } else {
      selectedUnit = ReturnStrings.unitPiece;
    }

    final price = (product.effectivePrice ?? product.baseUnitPrice);

    setState(() {
      _selectedUnit = selectedUnit;
      if (price > 0) {
        _unitPriceController.text = price.toStringAsFixed(2);
      } else {
        _unitPriceController.clear();
      }
      _qtyController.clear();
      _noteController.clear();
    });

    // Seçim sonrası direkt miktara odaklan.
    _qtyFocus.requestFocus();
  }

  void _clearLineForm({bool keepUnit = true}) {
    _qtyController.clear();
    _unitPriceController.clear();
    _noteController.clear();
    if (!keepUnit) {
      _selectedUnit = ReturnStrings.unitPiece;
    }
  }

  bool _canAddLine(core.CustomerProduct? product) {
    if (product == null) return false;
    final qty = _parseNumber(_qtyController.text) ?? 0;
    final unitPrice = _parseNumber(_unitPriceController.text) ?? 0;
    if (qty <= 0) return false;
    if (unitPrice < 0) return false;
    return true;
  }

  double get _qty => _parseNumber(_qtyController.text) ?? 0;
  double get _unitPrice => _parseNumber(_unitPriceController.text) ?? 0;
  double get _total => _qty * _unitPrice;

  Future<void> _openBarcodeScanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );

    if (!mounted) return;
    final trimmed = (code ?? '').trim();
    if (trimmed.isEmpty) return;

    final controller = ref.read(returnCreateControllerProvider.notifier);
    controller.setProductSearch(trimmed);

    final state = ref.read(returnCreateControllerProvider);
    if (state.selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(ReturnStrings.snackSelectCustomerFirst)),
      );
      return;
    }

    final added = await controller.prefillByBarcode(trimmed);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (added) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: ReturnStrings.snackSuccessDuration,
            backgroundColor: Colors.green,
            content: Text(ReturnStrings.snackProductAdded),
          ),
        );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text(ReturnStrings.snackBarcodeNotFound)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final state = ref.watch(returnCreateControllerProvider);
    final controller = ref.read(returnCreateControllerProvider.notifier);

    final customer = state.selectedCustomer;
    final selectedProduct = state.selectedProduct;

    Widget stepHeader() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBadge(label: widget.stepBadge),
          const SizedBox(width: core.AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ReturnStrings.step2Title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: core.AppSpacing.s4),
                Text(
                  ReturnStrings.productPickHelp,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget groupFilter(String customerId) {
      final groupsAsync = ref.watch(returnGroupNamesProvider(customerId));

      return groupsAsync.when(
        loading: () => const SizedBox(
          height: 56,
          child: Center(child: LinearProgressIndicator(minHeight: 2)),
        ),
        error: (e, _) => ReturnEmptyState(
          title: ReturnStrings.groupNamesLoadFailedTitle,
          subtitle: '$e',
          icon: Icons.error_outline_rounded,
          action: TextButton.icon(
            onPressed: () =>
                ref.invalidate(returnGroupNamesProvider(customerId)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(ReturnStrings.actionRefresh),
          ),
        ),
        data: (groups) {
          final items = <DropdownMenuItem<String>>[
            const DropdownMenuItem<String>(
              value: '',
              child: Text(ReturnStrings.groupFilterAll),
            ),
            ...groups.map(
              (g) => DropdownMenuItem<String>(
                value: g,
                child: Text(
                  g == core.CustomerProductRepository.ungroupedGroupName
                      ? ReturnStrings.groupUngrouped
                      : g,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ];

          final current = state.selectedGroupName ?? '';

          return DropdownButtonFormField<String>(
            key: ValueKey<String>('return-group-$customerId-$current'),
            initialValue: current,
            decoration: const InputDecoration(
              labelText: ReturnStrings.groupFilterLabel,
            ),
            items: items,
            onChanged: (value) {
              controller.setSelectedGroupName(value);
            },
          );
        },
      );
    }

    Widget productSearchField() {
      final text = state.productSearch;
      return Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                labelText: ReturnStrings.productSearchLabel,
                hintText: ReturnStrings.productSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: ReturnStrings.actionClear,
                        onPressed: () => controller.setProductSearch(''),
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: controller.setProductSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
          const SizedBox(width: core.AppSpacing.s8),
          IconButton(
            tooltip: ReturnStrings.actionScanBarcode,
            onPressed: _openBarcodeScanner,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ],
      );
    }

    Widget productList(String customerId) {
      final productsAsync = ref.watch(
        returnProductsProvider(
          ReturnProductsQuery(
            customerId: customerId,
            groupName: state.selectedGroupName,
            search: state.debouncedProductSearch,
          ),
        ),
      );

      return productsAsync.when(
        loading: () => const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => ReturnEmptyState(
          title: ReturnStrings.productsLoadFailedTitle,
          subtitle: '$e',
          icon: Icons.error_outline_rounded,
          action: TextButton.icon(
            onPressed: () => ref.invalidate(
              returnProductsProvider(
                ReturnProductsQuery(
                  customerId: customerId,
                  groupName: state.selectedGroupName,
                  search: state.debouncedProductSearch,
                ),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(ReturnStrings.actionRefresh),
          ),
        ),
        data: (products) {
          final q = state.productSearch.trim().toLowerCase();
          final filtered = q.isEmpty
              ? products
              : products.where((p) {
                  final name = p.name.toLowerCase();
                  final code = p.code.toLowerCase();
                  final barcode = (p.barcode ?? '').toLowerCase();
                  final barcodeText = (p.barcodeText ?? '').toLowerCase();
                  return name.contains(q) ||
                      code.contains(q) ||
                      barcode.contains(q) ||
                      barcodeText.contains(q);
                }).toList(growable: false);

          if (filtered.isEmpty) {
            return const ReturnEmptyState(
              title: ReturnStrings.productEmptyTitle,
              subtitle: ReturnStrings.productEmptySubtitle,
              icon: Icons.search_off_rounded,
            );
          }

          return SizedBox(
            height: 320,
            child: Scrollbar(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  final price = (p.effectivePrice ?? p.baseUnitPrice);
                  final isSelected = selectedProduct?.stockId == p.stockId;

                  final group = (p.groupName ?? '').trim();
                  final groupLabel =
                      group == core.CustomerProductRepository.ungroupedGroupName
                          ? ReturnStrings.groupUngrouped
                          : group;

                  return Material(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        controller.selectProduct(p);
                        _applyProductToForm(p);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary.withValues(alpha: 0.55)
                                : cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    p.code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  if (groupLabel.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _Chip(text: groupLabel),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatMoney(price),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  p.baseUnitName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.65),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: cs.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      );
    }

    Widget addLineForm(core.CustomerProduct product) {
      const enabled = true;
      final canAdd = _canAddLine(product);

      final fieldWidth = MediaQuery.sizeOf(context).width;
      final twoColumns = fieldWidth >= 720;

      Widget field({required Widget child, int span = 1}) {
        if (!twoColumns) return child;
        return SizedBox(
          width: span == 2
              ? double.infinity
              : (core.AppResponsive.maxContentWidth / 2) - 24,
          child: child,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: core.AppSpacing.s12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(core.AppSpacing.s12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${ReturnStrings.productSelected}: ${product.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: ReturnStrings.actionUnselect,
                      onPressed: () {
                        controller.clearSelectedProduct();
                        setState(() {
                          _clearLineForm(keepUnit: false);
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: core.AppSpacing.s12),
                FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Wrap(
                    spacing: core.AppSpacing.s12,
                    runSpacing: core.AppSpacing.s12,
                    children: [
                      field(
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: TextField(
                            controller: _qtyController,
                            focusNode: _qtyFocus,
                            decoration: const InputDecoration(
                              labelText: ReturnStrings.fieldQtyLabel,
                              hintText: ReturnStrings.fieldQtyHint,
                            ),
                            enabled: enabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]')),
                            ],
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _unitPriceFocus.requestFocus(),
                          ),
                        ),
                      ),
                      field(
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey<String>('return-unit-$_selectedUnit'),
                            initialValue: _selectedUnit,
                            decoration: const InputDecoration(
                              labelText: ReturnStrings.fieldUnitLabel,
                            ),
                            items: ReturnStrings.units
                                .map(
                                  (u) => DropdownMenuItem<String>(
                                    value: u,
                                    child: Text(u),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedUnit = v);
                            },
                          ),
                        ),
                      ),
                      field(
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(3),
                          child: TextField(
                            controller: _unitPriceController,
                            focusNode: _unitPriceFocus,
                            decoration: const InputDecoration(
                              labelText: ReturnStrings.fieldUnitPriceLabel,
                              hintText: ReturnStrings.fieldUnitPriceHint,
                            ),
                            enabled: enabled,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]')),
                            ],
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _noteFocus.requestFocus(),
                          ),
                        ),
                      ),
                      field(
                        child: TextField(
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: ReturnStrings.fieldAmountLabel,
                            hintText: formatMoney(_total),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(4),
                          child: TextField(
                            controller: _noteController,
                            focusNode: _noteFocus,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: ReturnStrings.fieldNoteLabel,
                            ),
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) {
                              if (canAdd) {
                                _handleAddLine(product);
                              }
                            },
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              canAdd ? () => _handleAddLine(product) : null,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text(ReturnStrings.addLineCta),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (customer == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(core.AppSpacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              stepHeader(),
              const SizedBox(height: core.AppSpacing.s16),
              const ReturnEmptyState(
                title: ReturnStrings.productDisabledTitle,
                subtitle: ReturnStrings.productDisabledSubtitle,
                icon: Icons.person_search_rounded,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(core.AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            stepHeader(),
            const SizedBox(height: core.AppSpacing.s16),
            groupFilter(customer.id),
            const SizedBox(height: core.AppSpacing.s12),
            productSearchField(),
            const SizedBox(height: core.AppSpacing.s12),
            productList(customer.id),
            if (selectedProduct != null) addLineForm(selectedProduct),
          ],
        ),
      ),
    );
  }

  void _handleAddLine(core.CustomerProduct product) {
    final controller = ref.read(returnCreateControllerProvider.notifier);
    final qty = _parseNumber(_qtyController.text) ?? 0;
    final unitPrice = _parseNumber(_unitPriceController.text) ?? 0;

    if (qty <= 0 || unitPrice < 0) return;

    controller.addLine(
      product: product,
      quantity: qty,
      unit: _selectedUnit,
      unitPrice: unitPrice,
      note: _noteController.text,
    );

    // Satıra eklendikten sonra form temizlensin, cari kalsın.
    controller.clearSelectedProduct();

    setState(() {
      _clearLineForm(keepUnit: true);
    });
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.primary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.primary.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
