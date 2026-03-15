import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _invoiceCustomerDetailProvider = FutureProvider.autoDispose
    .family<AdminInvoiceCustomerPickEntry, String>((ref, customerId) {
  return adminInvoiceCustomerRepository.fetchCustomerWithLastInvoiceById(
    customerId,
  );
});

class InvoiceNewFormPage extends ConsumerStatefulWidget {
  const InvoiceNewFormPage({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  ConsumerState<InvoiceNewFormPage> createState() => _InvoiceNewFormPageState();
}

class _InvoiceNewFormPageState extends ConsumerState<InvoiceNewFormPage> {
  late DateTime _invoiceDate;
  String _invoiceNo = '';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _invoiceDate = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync =
        ref.watch(_invoiceCustomerDetailProvider(widget.customerId));

    return AppScaffold(
      title: 'Yeni Fatura',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: customerAsync.when(
          loading: () => const AppLoadingState(),
          error: (error, stackTrace) => AppErrorState(
            message: error.toString(),
          ),
          data: (customer) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCustomerSummaryCard(context, customer),
                const SizedBox(height: 16),
                _buildFormCard(context),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: PrimaryButton(
                    label: _submitting ? 'İşleniyor...' : 'Faturayı Kes',
                    onPressed:
                        _submitting ? null : () => _handleSubmit(customer),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCustomerSummaryCard(
    BuildContext context,
    AdminInvoiceCustomerPickEntry customer,
  ) {
    final theme = Theme.of(context);
    final lastInvoiceText = customer.lastInvoiceNo == null ||
            customer.lastInvoiceNo!.trim().isEmpty
        ? '—'
        : customer.lastInvoiceNo!;

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if ((customer.customerCode ?? '').isNotEmpty) ...[
                        Text(
                          customer.customerCode!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      if ((customer.customerCode ?? '').isNotEmpty &&
                          (customer.phone ?? '').isNotEmpty)
                        const SizedBox(width: 8),
                      if ((customer.phone ?? '').isNotEmpty)
                        Text(
                          customer.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Son Fatura',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    lastInvoiceText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary
                          .withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final theme = Theme.of(context);
    final dateText =
        '${_invoiceDate.day.toString().padLeft(2, '0')}.${_invoiceDate.month.toString().padLeft(2, '0')}.${_invoiceDate.year}';

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fatura Bilgileri',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Fatura No (opsiyonel)',
                hintText: 'Boş bırakılırsa sistem üretecek',
              ),
              onChanged: (value) {
                setState(() {
                  _invoiceNo = value.trim();
                });
              },
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _pickDate(context),
              child: AbsorbPointer(
                child: TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Fatura Tarihi',
                  ),
                  controller: TextEditingController(text: dateText),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Toplam Tutar',
                hintText: 'Kalemlerden hesaplanacak (yakında)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );

    if (picked != null) {
      setState(() {
        _invoiceDate = picked;
      });
    }
  }

  Future<void> _handleSubmit(AdminInvoiceCustomerPickEntry customer) async {
    if (!mounted) return;

    setState(() {
      _submitting = true;
    });

    String? createdId;
    try {
      createdId = await adminInvoiceRepository.createInvoiceForCustomer(
        customerId: customer.customerId,
        invoiceNo: _invoiceNo.isEmpty ? null : _invoiceNo,
        invoiceDate: _invoiceDate,
        totalAmount: 0,
      );
    } catch (e) {
      createdId = null;
      // Hata bilgisi submit sonrası gosterilecek.
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    if (createdId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Fatura oluşturulurken hata oluştu, lütfen tekrar deneyin.'),
        ),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    context.go('/invoices/$createdId');
  }
}
