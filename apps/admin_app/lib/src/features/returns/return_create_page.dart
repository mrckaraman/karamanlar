import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'return_create_controller.dart';
import 'return_strings.dart';
import '../../utils/uuid_utils.dart' as uuid;
import 'widgets/return_customer_picker_card.dart';
import 'widgets/return_lines_section.dart';
import 'widgets/return_product_picker_card.dart';
import 'widgets/return_summary_card.dart';

class ReturnCreatePage extends ConsumerStatefulWidget {
  const ReturnCreatePage({
    super.key,
    this.initialCustomerId,
    this.initialProductId,
    this.initialBarcode,
  });

  final String? initialCustomerId;
  final String? initialProductId;
  final String? initialBarcode;

  @override
  ConsumerState<ReturnCreatePage> createState() => _ReturnCreatePageState();
}

class _ReturnCreatePageState extends ConsumerState<ReturnCreatePage> {
  String? _prefilledCustomerId;
  String? _prefilledProductId;
  String? _prefilledBarcode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryPrefill());
  }

  @override
  void didUpdateWidget(covariant ReturnCreatePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCustomerId != widget.initialCustomerId ||
        oldWidget.initialProductId != widget.initialProductId ||
        oldWidget.initialBarcode != widget.initialBarcode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryPrefill());
    }
  }

  Future<void> _tryPrefill() async {
    final controller = ref.read(returnCreateControllerProvider.notifier);

    void showSuccessSnack() {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            duration: ReturnStrings.snackSuccessDuration,
            backgroundColor: Colors.green,
            content: Text(ReturnStrings.snackProductAdded),
          ),
        );
    }

    final rawCustomerId = widget.initialCustomerId;
    final rawProductId = widget.initialProductId;
    final rawBarcode = widget.initialBarcode;

    final customerId = rawCustomerId?.trim();
    final productId = rawProductId?.trim();
    final barcode = rawBarcode?.trim();

    if (customerId != null &&
        customerId.isNotEmpty &&
        _prefilledCustomerId != customerId &&
        uuid.isValidUuid(customerId)) {
      _prefilledCustomerId = customerId;
      await controller.prefillCustomerById(customerId);
    }

    final selectedCustomer =
        ref.read(returnCreateControllerProvider).selectedCustomer;

    if (barcode != null && barcode.isNotEmpty && _prefilledBarcode != barcode) {
      if (barcode.length < 6) {
        return;
      }
      if (selectedCustomer == null) {
        controller.setProductSearch(barcode);
      } else {
        _prefilledBarcode = barcode;
        final added = await controller.prefillByBarcode(barcode);
        if (!mounted) return;
        if (added) {
          showSuccessSnack();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(ReturnStrings.snackBarcodeNotFound)),
          );
        }
      }
    }

    if (productId != null &&
        productId.isNotEmpty &&
        _prefilledProductId != productId) {
      if (!uuid.isValidUuid(productId)) {
        return;
      }
      if (selectedCustomer == null) {
        controller.setProductSearch(productId);
      } else {
        _prefilledProductId = productId;
        final added = await controller.prefillProductById(productId);
        if (!mounted) return;
        if (added) {
          showSuccessSnack();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Customer?>(
      returnCreateControllerProvider.select((s) => s.selectedCustomer),
      (previous, next) {
        if (previous == null && next != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _tryPrefill());
        }
      },
    );

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final state = ref.watch(returnCreateControllerProvider);
    final controller = ref.read(returnCreateControllerProvider.notifier);

    Widget header() {
      final canResetDraft =
          state.selectedCustomer != null || state.lines.isNotEmpty;
      final canClearAll =
          canResetDraft || state.customerSearch.trim().isNotEmpty;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ReturnStrings.pageTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  ReturnStrings.pageSubtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              TextButton.icon(
                onPressed: canResetDraft ? controller.resetDraft : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text(ReturnStrings.actionResetDraft),
              ),
              OutlinedButton.icon(
                onPressed: canClearAll ? controller.clearAll : null,
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text(ReturnStrings.actionClearAll),
              ),
            ],
          ),
        ],
      );
    }

    return AppScaffold(
      title: ReturnStrings.pageTitle,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 980;

          if (!isWide) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header(),
                  const SizedBox(height: AppSpacing.s16),
                  const ReturnCustomerPickerCard(
                      stepBadge: ReturnStrings.step1Badge),
                  const SizedBox(height: AppSpacing.s16),
                  const ReturnProductPickerCard(
                      stepBadge: ReturnStrings.step2Badge),
                  const SizedBox(height: AppSpacing.s16),
                  const ReturnLinesSection(stepBadge: ReturnStrings.step3Badge),
                  const SizedBox(height: AppSpacing.s16),
                  const ReturnSummaryCard(stepBadge: ReturnStrings.step4Badge),
                ],
              ),
            );
          }

          // Wide / web layout: two columns + sticky-ish summary.
          return SizedBox(
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header(),
                const SizedBox(height: AppSpacing.s16),
                const Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              ReturnCustomerPickerCard(
                                stepBadge: ReturnStrings.step1Badge,
                              ),
                              SizedBox(height: AppSpacing.s16),
                              ReturnProductPickerCard(
                                stepBadge: ReturnStrings.step2Badge,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: AppSpacing.s16),
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: ReturnLinesSection(
                                  stepBadge: ReturnStrings.step3Badge,
                                ),
                              ),
                            ),
                            SizedBox(height: AppSpacing.s16),
                            ReturnSummaryCard(
                              stepBadge: ReturnStrings.step4Badge,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
