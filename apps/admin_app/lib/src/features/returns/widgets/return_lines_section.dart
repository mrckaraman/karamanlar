import 'package:core/core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../utils/formatters_tr.dart';
import '../return_create_controller.dart';
import '../return_strings.dart';
import 'return_empty_state.dart';

class ReturnLinesSection extends ConsumerWidget {
  const ReturnLinesSection({
    super.key,
    required this.stepBadge,
  });

  final String stepBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final state = ref.watch(returnCreateControllerProvider);
    final controller = ref.read(returnCreateControllerProvider.notifier);

    final lines = state.lines;

    Widget stepHeader() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepBadge(label: stepBadge),
          const SizedBox(width: core.AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ReturnStrings.step3Title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: core.AppSpacing.s4),
                Text(
                  ReturnStrings.linesHelp,
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

    Widget groupingRow() {
      final isCustomerGroupingDisabled = state.selectedCustomer == null;

      return Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<ReturnGrouping>(
              key: ValueKey<ReturnGrouping>(state.grouping),
              initialValue: state.grouping,
              decoration: const InputDecoration(
                labelText: ReturnStrings.groupingLabel,
              ),
              items: ReturnGrouping.values
                  .map(
                    (g) => DropdownMenuItem<ReturnGrouping>(
                      value: g,
                      enabled: g == ReturnGrouping.byCustomer
                          ? !isCustomerGroupingDisabled
                          : true,
                      child: Text(g.labelTr),
                    ),
                  )
                  .toList(),
              onChanged: (g) {
                if (g == null) return;
                if (g == ReturnGrouping.byCustomer &&
                    isCustomerGroupingDisabled) {
                  return;
                }
                controller.setGrouping(g);
              },
            ),
          ),
        ],
      );
    }

    Widget totalsFooter() {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(core.AppSpacing.s12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Wrap(
          spacing: core.AppSpacing.s16,
          runSpacing: core.AppSpacing.s8,
          children: [
            _Metric(
              label: ReturnStrings.linesTotalsLineCount,
              value: state.lineCount.toString(),
            ),
            _Metric(
              label: ReturnStrings.linesTotalsUniqueProducts,
              value: state.uniqueProductCount.toString(),
            ),
            _Metric(
              label: ReturnStrings.linesTotalsQty,
              value: formatQtyTr(state.totalQty),
            ),
            _Metric(
              label: ReturnStrings.linesTotalsAmount,
              value: formatMoney(state.totalAmount),
              isEmphasis: true,
            ),
          ],
        ),
      );
    }

    Widget buildUngroupedList(BoxConstraints constraints) {
      final isWide = constraints.maxWidth >= 920;
      if (lines.isEmpty) {
        return const ReturnEmptyState(
          title: ReturnStrings.linesEmptyTitle,
          subtitle: ReturnStrings.linesEmptySubtitle,
          icon: Icons.playlist_add_rounded,
        );
      }

      if (isWide) {
        return _LinesTable(lines: lines);
      }

      return Column(
        children: [
          for (final line in lines) ...[
            _LineCard(line: line),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    Widget buildGroupedView(BoxConstraints constraints) {
      if (lines.isEmpty) {
        return const ReturnEmptyState(
          title: ReturnStrings.linesEmptyTitle,
          subtitle: ReturnStrings.linesEmptySubtitle,
          icon: Icons.playlist_add_rounded,
        );
      }

      final grouping = state.grouping;
      if (grouping == ReturnGrouping.none) {
        return buildUngroupedList(constraints);
      }

      String groupKey(ReturnLineDraft l) {
        switch (grouping) {
          case ReturnGrouping.byProduct:
            return l.product.name;
          case ReturnGrouping.byCategory:
            final g = (l.product.groupName ?? '').trim();
            if (g.isEmpty) return ReturnStrings.groupUngrouped;
            return g == core.CustomerProductRepository.ungroupedGroupName
                ? ReturnStrings.groupUngrouped
                : g;
          case ReturnGrouping.byCustomer:
            return state.selectedCustomer?.displayName ??
                ReturnStrings.groupCustomerFallback;
          case ReturnGrouping.none:
            return '';
        }
      }

      final Map<String, List<ReturnLineDraft>> groups = {};
      for (final l in lines) {
        final key = groupKey(l);
        groups.putIfAbsent(key, () => []).add(l);
      }

      final sortedKeys = groups.keys.toList()..sort();

      return Column(
        children: [
          for (final key in sortedKeys) ...[
            _GroupTile(
              title: key,
              lines: groups[key]!,
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(core.AppSpacing.s16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                stepHeader(),
                const SizedBox(height: core.AppSpacing.s16),
                groupingRow(),
                const SizedBox(height: core.AppSpacing.s12),
                buildGroupedView(constraints),
                const SizedBox(height: core.AppSpacing.s12),
                totalsFooter(),
                const SizedBox(height: 2),
                Text(
                  ReturnStrings.linesFooterHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                // Actions are embedded in summary card.
              ],
            );
          },
        ),
      ),
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

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.isEmphasis = false,
  });

  final String label;
  final String value;
  final bool isEmphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: isEmphasis ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LineCard extends ConsumerWidget {
  const _LineCard({required this.line});

  final ReturnLineDraft line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(line.lineTotal),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            line.product.code,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _MiniPill(
                icon: Icons.scale_outlined,
                text: '${formatQtyTr(line.quantity)} ${line.unit}',
              ),
              _MiniPill(
                icon: Icons.sell_outlined,
                text: ReturnStrings.unitPriceLabel(formatMoney(line.unitPrice)),
              ),
              if ((line.note ?? '').trim().isNotEmpty)
                const _MiniPill(
                  icon: Icons.sticky_note_2_outlined,
                  text: ReturnStrings.lineNoteChip,
                ),
            ],
          ),
          if ((line.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              line.note!.trim(),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _openEditDialog(context, ref, line),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text(ReturnStrings.lineActionEdit),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => ref
                    .read(returnCreateControllerProvider.notifier)
                    .removeLine(line.id),
                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                label: Text(
                  ReturnStrings.lineActionDelete,
                  style: TextStyle(color: cs.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEditDialog(
    BuildContext context,
    WidgetRef ref,
    ReturnLineDraft line,
  ) async {
    final controller = ref.read(returnCreateControllerProvider.notifier);

    final qtyController = TextEditingController(
      text: line.quantity.toStringAsFixed(3).replaceAll('.', ','),
    );
    final unitPriceController = TextEditingController(
      text: line.unitPrice.toStringAsFixed(2).replaceAll('.', ','),
    );
    final noteController = TextEditingController(text: line.note ?? '');

    String unit = line.unit;

    double? parse(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return null;
      return double.tryParse(trimmed.replaceAll(',', '.'));
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(ReturnStrings.editLineDialogTitle),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qtyController,
                  decoration: const InputDecoration(
                      labelText: ReturnStrings.editLineQtyLabel),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(
                      labelText: ReturnStrings.editLineUnitLabel),
                  items: ReturnStrings.units
                      .map(
                        (u) => DropdownMenuItem<String>(
                          value: u,
                          child: Text(u),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    unit = v;
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unitPriceController,
                  decoration: const InputDecoration(
                      labelText: ReturnStrings.editLineUnitPriceLabel),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: ReturnStrings.editLineNoteLabel),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(ReturnStrings.editLineCancel),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = parse(qtyController.text) ?? 0;
                final unitPrice = parse(unitPriceController.text) ?? 0;

                if (qty <= 0 || unitPrice < 0) {
                  return;
                }

                controller.updateLine(
                  line.id,
                  quantity: qty,
                  unit: unit,
                  unitPrice: unitPrice,
                  note: noteController.text,
                );

                Navigator.of(dialogContext).pop();
              },
              child: const Text(ReturnStrings.editLineSave),
            ),
          ],
        );
      },
    );

    qtyController.dispose();
    unitPriceController.dispose();
    noteController.dispose();
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesTable extends ConsumerWidget {
  const _LinesTable({required this.lines});

  final List<ReturnLineDraft> lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: const Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _HeaderCell(ReturnStrings.tableHeaderProduct),
                  ),
                  Expanded(
                    flex: 2,
                    child: _HeaderCell(ReturnStrings.tableHeaderQty),
                  ),
                  Expanded(
                    flex: 2,
                    child: _HeaderCell(
                      ReturnStrings.tableHeaderUnitPrice,
                      alignRight: true,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _HeaderCell(
                      ReturnStrings.tableHeaderTotal,
                      alignRight: true,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _HeaderCell(
                      ReturnStrings.tableHeaderAction,
                      alignRight: true,
                    ),
                  ),
                ],
              ),
            ),
            for (final l in lines)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: cs.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l.product.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          if ((l.note ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              l.note!.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${formatQtyTr(l.quantity)} ${l.unit}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatMoney(l.unitPrice),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        formatMoney(l.lineTotal),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: ReturnStrings.lineActionEdit,
                            onPressed: () => _LineCard(line: l)
                                ._openEditDialog(context, ref, l),
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                          IconButton(
                            tooltip: ReturnStrings.lineActionDelete,
                            onPressed: () => ref
                                .read(returnCreateControllerProvider.notifier)
                                .removeLine(l.id),
                            icon: Icon(Icons.delete_outline_rounded,
                                size: 20, color: cs.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text, {this.alignRight = false});

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: theme.textTheme.labelMedium?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _GroupTile extends StatefulWidget {
  const _GroupTile({required this.title, required this.lines});

  final String title;
  final List<ReturnLineDraft> lines;

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final total = widget.lines.fold<double>(
      0,
      (sum, e) => sum + e.lineTotal,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        ReturnStrings.groupLineCount(widget.lines.length),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatMoney(total),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final l in widget.lines) ...[
                      _LineCard(line: l),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
