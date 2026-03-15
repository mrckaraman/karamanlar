import 'package:core/core.dart' as core;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../return_create_controller.dart';
import '../return_strings.dart';
import 'return_empty_state.dart';

class ReturnCustomerPickerCard extends ConsumerWidget {
  const ReturnCustomerPickerCard({
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

    final selected = state.selectedCustomer;
    final customersAsync = ref.watch(returnCustomersProvider);

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
                  ReturnStrings.step1Title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: core.AppSpacing.s4),
                Text(
                  ReturnStrings.step1Help,
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

    Widget selectedCustomerCard(core.Customer customer) {
      final chips = <Widget>[];

      if (customer.code.trim().isNotEmpty) {
        chips.add(_InfoChip(
            label: ReturnStrings.customerCodeLabel,
            value: customer.code.trim()));
      }
      final phone = (customer.phone ?? '').trim();
      if (phone.isNotEmpty) {
        chips.add(
            _InfoChip(label: ReturnStrings.customerPhoneLabel, value: phone));
      }

      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(core.AppSpacing.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ReturnStrings.customerSelectedTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: controller.clearCustomer,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text(ReturnStrings.customerChange),
                  ),
                ],
              ),
              const SizedBox(height: core.AppSpacing.s8),
              Text(
                customer.displayName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: core.AppSpacing.s8),
                Wrap(
                  spacing: core.AppSpacing.s8,
                  runSpacing: core.AppSpacing.s8,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget searchField() {
      final text = state.customerSearch;
      return TextField(
        decoration: InputDecoration(
          labelText: ReturnStrings.customerSearchLabel,
          hintText: ReturnStrings.customerSearchHint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: ReturnStrings.actionClear,
                  onPressed: () => controller.setCustomerSearch(''),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        onChanged: controller.setCustomerSearch,
        textInputAction: TextInputAction.search,
      );
    }

    Widget customersList(List<core.Customer> customers) {
      if (customers.isEmpty) {
        return const ReturnEmptyState(
          title: ReturnStrings.customerNoResultTitle,
          subtitle: ReturnStrings.customerNoResultSubtitle,
          icon: Icons.search_off_rounded,
        );
      }

      return SizedBox(
        height: 340,
        child: Scrollbar(
          child: ListView.separated(
            itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final customer = customers[index];
              final isSelected = selected?.id == customer.id;

              final subtitlePieces = <String>[];
              if (customer.code.trim().isNotEmpty) {
                subtitlePieces.add(customer.code.trim());
              }
              final phone = (customer.phone ?? '').trim();
              if (phone.isNotEmpty) {
                subtitlePieces.add(phone);
              }

              final subtitleText = subtitlePieces.join(' • ');

              return Material(
                color: isSelected
                    ? cs.primary.withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => controller.selectCustomer(customer),
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
                            Icons.person_outline_rounded,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subtitleText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitleText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
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
            if (selected != null) ...[
              selectedCustomerCard(selected),
              const SizedBox(height: core.AppSpacing.s16),
            ],
            searchField(),
            const SizedBox(height: core.AppSpacing.s12),
            customersAsync.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, _) => ReturnEmptyState(
                title: ReturnStrings.loadFailedTitle,
                subtitle: ReturnStrings.loadFailedSubtitle('$e'),
                icon: Icons.error_outline_rounded,
                action: TextButton.icon(
                  onPressed: () => ref.invalidate(returnCustomersProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text(ReturnStrings.actionRefresh),
                ),
              ),
              data: (customers) => customersList(customers),
            ),
          ],
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
