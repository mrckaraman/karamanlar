import 'dart:async';

import 'package:core/core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/formatters_tr.dart';
import '../return_create_controller.dart';
import '../return_strings.dart';
import 'return_empty_state.dart';

class ReturnSummaryCard extends ConsumerStatefulWidget {
  const ReturnSummaryCard({
    super.key,
    required this.stepBadge,
    this.compact = false,
  });

  final String stepBadge;
  final bool compact;

  @override
  ConsumerState<ReturnSummaryCard> createState() => _ReturnSummaryCardState();
}

class _ReturnSummaryCardState extends ConsumerState<ReturnSummaryCard> {
  Timer? _successTimer;
  bool _showSuccess = false;

  @override
  void dispose() {
    _successTimer?.cancel();
    super.dispose();
  }

  void _flashSuccess() {
    _successTimer?.cancel();
    setState(() => _showSuccess = true);
    _successTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showSuccess = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final state = ref.watch(returnCreateControllerProvider);
    final controller = ref.read(returnCreateControllerProvider.notifier);

    final customer = state.selectedCustomer;

    final warnings = <String>[];
    if (customer == null) warnings.add(ReturnStrings.warningMissingCustomer);
    if (state.lines.isEmpty) warnings.add(ReturnStrings.warningNoLines);
    if (state.lines.any((e) => e.unitPrice == 0)) {
      warnings.add(ReturnStrings.warningZeroPrice);
    }

    final saveLabel = state.saveState.isLoading
        ? ReturnStrings.saveLoading
        : (_showSuccess
            ? ReturnStrings.saveSuccess
            : ReturnStrings.savePrimary);

    final saveIcon = state.saveState.isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(_showSuccess ? Icons.check_circle_rounded : Icons.save_rounded);

    Future<void> handleSave() async {
      if (!state.canSave) return;

      final messenger = ScaffoldMessenger.of(context);

      await controller.saveAllLines();

      if (!mounted) return;

      final result = ref.read(returnCreateControllerProvider).saveState;

      if (result.hasError) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${ReturnStrings.snackSaveFailed}: '
              '${core.AppException.messageOf(result.error!)}',
            ),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text(ReturnStrings.snackSaved)),
      );

      _flashSuccess();

      // Kaydetme sonrası controller tamamen temizlensin.
      controller.clearAll();
    }

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
                  ReturnStrings.step4Title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: core.AppSpacing.s4),
                Text(
                  ReturnStrings.summaryHelp,
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

    Widget summaryRow(
        {required String label, required String value, bool bold = false}) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            value,
            style: bold
                ? theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700)
                : theme.textTheme.bodyMedium,
          ),
        ],
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(core.AppSpacing.s12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ReturnStrings.summaryTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  summaryRow(
                    label: ReturnStrings.summaryCustomer,
                    value: customer?.displayName ?? '-',
                    bold: true,
                  ),
                  const SizedBox(height: 8),
                  summaryRow(
                    label: ReturnStrings.summaryLineCount,
                    value: state.lineCount.toString(),
                  ),
                  const SizedBox(height: 8),
                  summaryRow(
                    label: ReturnStrings.summaryQty,
                    value: formatQtyTr(state.totalQty),
                  ),
                  const SizedBox(height: 8),
                  summaryRow(
                    label: ReturnStrings.summaryNotes,
                    value: state.noteCount.toString(),
                  ),
                  const SizedBox(height: 8),
                  summaryRow(
                    label: ReturnStrings.summaryAmount,
                    value: formatMoney(state.totalAmount),
                    bold: true,
                  ),
                  if (state.saveProgress != null &&
                      state.saveState.isLoading) ...[
                    const SizedBox(height: 12),
                    _ProgressRow(progress: state.saveProgress!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (warnings.isNotEmpty)
              ReturnEmptyState(
                title: ReturnStrings.summaryWarnings,
                subtitle: warnings.join(' '),
                icon: Icons.rule_rounded,
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.canSave ? handleSave : null,
                icon: saveIcon,
                label: Text(saveLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.progress});

  final (int savedCount, int total) progress;

  @override
  Widget build(BuildContext context) {
    final saved = progress.$1;
    final total = progress.$2;
    final pct = total <= 0 ? 0.0 : saved / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ReturnStrings.saveProgressLabel(saved, total)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: pct.isFinite ? pct : null, minHeight: 2),
      ],
    );
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
