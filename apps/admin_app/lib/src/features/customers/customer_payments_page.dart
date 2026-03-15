import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import 'customer_finance_providers.dart';

enum _PaymentsRange { days7, days30, monthToDate, all }

final _paymentCustomerSearchProvider =
    StateProvider.autoDispose<String>((ref) => '');

final _paymentCustomersFutureProvider =
    FutureProvider.autoDispose<List<Customer>>((ref) async {
  final search = ref.watch(_paymentCustomerSearchProvider);
  return customerRepository.fetchCustomers(
    search: search,
    isActive: true,
    limit: 50,
  );
});

class CustomerPaymentsPage extends ConsumerStatefulWidget {
  const CustomerPaymentsPage({
    super.key,
    required this.customerId,
  });

  final String customerId;

  @override
  ConsumerState<CustomerPaymentsPage> createState() => _CustomerPaymentsPageState();
}

class _CustomerPaymentsPageState extends ConsumerState<CustomerPaymentsPage> {
  DateTime? _from;
  DateTime? _to;

  _PaymentsRange _range = _PaymentsRange.days30;
  PaymentMethod? _methodFilter;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = now;
    _from = now.subtract(const Duration(days: 30));
  }

  CustomerPaymentsRequest _buildRequest() {
    return (
      customerId: widget.customerId,
      from: _from,
      to: _to,
    );
  }

  void _setRange(_PaymentsRange range) {
    setState(() {
      _range = range;
      final now = DateTime.now();
      switch (range) {
        case _PaymentsRange.days7:
          _to = now;
          _from = now.subtract(const Duration(days: 7));
          break;
        case _PaymentsRange.days30:
          _to = now;
          _from = now.subtract(const Duration(days: 30));
          break;
        case _PaymentsRange.monthToDate:
          _to = now;
          _from = DateTime(now.year, now.month, 1);
          break;
        case _PaymentsRange.all:
          _to = now;
          _from = null;
          break;
      }
    });

    _invalidatePayments();
  }

  void _invalidatePayments() {
    final request = _buildRequest();
    ref.invalidate(customerPaymentsProvider(request));
  }

  Future<void> _openEditSheet(PaymentRow row) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _EditPaymentSheet(row: row);
      },
    );

    if (result == true && mounted) {
      _invalidatePayments();

      if (widget.customerId != '_all') {
        ref.invalidate(customerStatementProvider((
          customerId: widget.customerId,
          from: null,
          to: null,
          type: 'all',
        )));
        ref.invalidate(customerBalanceProvider(widget.customerId));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tahsilat güncellendi.'),
        ),
      );
    }
  }

  Future<void> _confirmCancel(PaymentRow row) async {
    if (row.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu tahsilat zaten iptal edilmiş.')),
      );
      return;
    }

    final theme = Theme.of(context);
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Tahsilatı İptal Et'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bu tahsilat kaydını iptal etmek üzeresiniz.\n'
                'İptal edilen tahsilatlar toplam hesaplamalarına dahil edilmez.',
              ),
              const SizedBox(height: 12),
              const Text('İptal sebebi (opsiyonel):'),
              const SizedBox(height: 8),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Örn: Hatalı kayıt, yanlış tutar vb.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('İptal Et'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final reason = reasonController.text.trim();
      final result = await AsyncValue.guard(() async {
        await adminCustomerLedgerRepository.cancelPayment(row.id, reason);
      });

      if (!mounted) return;

      if (result.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'İptal hatası: ${AppException.messageOf(result.error!)}',
            ),
          ),
        );
        return;
      }

      _invalidatePayments();

        if (widget.customerId != '_all') {
          ref.invalidate(customerStatementProvider((
            customerId: widget.customerId,
            from: null,
            to: null,
            type: 'all',
          )));
          ref.invalidate(customerBalanceProvider(widget.customerId));
        }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tahsilat iptal edildi.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _buildRequest();
    final paymentsAsync = ref.watch(customerPaymentsProvider(request));
    final summaryAsync = ref.watch(
      customerPaymentsSummaryProvider((customerId: widget.customerId)),
    );

    return AppScaffold(
      title: 'Tahsilatlar',
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              _invalidatePayments();
            },
            child: paymentsAsync.when(
              loading: () => const AppLoadingState(),
              error: (e, _) => AppErrorState(
                message: 'Tahsilatlar yüklenemedi: ${AppException.messageOf(e)}',
                onRetry: _invalidatePayments,
              ),
              data: (rows) {
                final filteredRows = _applyPaymentFilters(
                  rows,
                  method: _methodFilter,
                );

                if (rows.isEmpty) {
                      return ListView(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.s16,
                      right: AppSpacing.s16,
                      top: AppSpacing.s16,
                      bottom: AppSpacing.s32,
                    ),
                    children: [
                          summaryAsync.when(
                            data: (s) => _PaymentsSummaryCard(
                              summary: _PaymentsSummary(
                                total: s.total,
                                today: s.today,
                                monthToDate: s.monthToDate,
                                count: s.count,
                              ),
                            ),
                            loading: () => const Card(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('Özet yükleniyor...'),
                              ),
                            ),
                            error: (e, _) => Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'Özet yüklenemedi: ${AppException.messageOf(e)}',
                                ),
                              ),
                            ),
                          ),
                      const SizedBox(height: AppSpacing.s16),
                      const AppEmptyState(
                        title: 'Tahsilat bulunamadı',
                        subtitle:
                            'Bu müşteri için seçilen tarih aralığında tahsilat yok.',
                      ),
                    ],
                  );
                }

                final methods = _extractPaymentMethods(rows);

                return ListView.separated(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.s16,
                    right: AppSpacing.s16,
                    top: AppSpacing.s16,
                    bottom: 80,
                  ),
                  itemCount: filteredRows.length + 2,
                  separatorBuilder: (_, index) {
                    if (index < 2) {
                      return const SizedBox(height: AppSpacing.s12);
                    }
                    return const Divider(height: 1);
                  },
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return summaryAsync.when(
                        data: (s) => _PaymentsSummaryCard(
                          summary: _PaymentsSummary(
                            total: s.total,
                            today: s.today,
                            monthToDate: s.monthToDate,
                            count: s.count,
                          ),
                        ),
                        loading: () => const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Özet yükleniyor...'),
                          ),
                        ),
                        error: (e, _) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Özet yüklenemedi: ${AppException.messageOf(e)}',
                            ),
                          ),
                        ),
                      );
                    }
                    if (index == 1) {
                      return _PaymentsFiltersRow(
                        range: _range,
                        onRangeChanged: _setRange,
                        methods: methods,
                        selectedMethod: _methodFilter,
                        onMethodChanged: (value) {
                          setState(() {
                            _methodFilter = value;
                          });
                        },
                      );
                    }

                    final row = filteredRows[index - 2];
                    return _PaymentListRow(
                      row: row,
                      onEdit: () => _openEditSheet(row),
                      onCancel: () => _confirmCancel(row),
                    );
                  },
                );
              },
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: () async {
                final result = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (sheetContext) {
                    return const _SinglePaymentSheet();
                  },
                );

                if (result == true && context.mounted) {
                  _invalidatePayments();

                  if (widget.customerId != '_all') {
                    ref.invalidate(customerStatementProvider((
                      customerId: widget.customerId,
                      from: null,
                      to: null,
                      type: 'all',
                    )));
                    ref.invalidate(customerBalanceProvider(widget.customerId));
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tahsilat kaydedildi.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Tahsilat Ekle'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinglePaymentSheet extends ConsumerStatefulWidget {
  const _SinglePaymentSheet();

  @override
  ConsumerState<_SinglePaymentSheet> createState() =>
      _SinglePaymentSheetState();
}

class _SinglePaymentSheetState
    extends ConsumerState<_SinglePaymentSheet> {
  Customer? _selectedCustomer;
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _date = DateTime.now();
  AsyncValue<void> _saveState = const AsyncData<void>(null);

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  double? _parseAmount(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cari seçin.')),
      );
      return;
    }

    final session = supabaseClient.auth.currentSession;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Oturum bulunamadı. Lütfen tekrar giriş yapın.'),
        ),
      );
      return;
    }

    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir tutar girin.')),
      );
      return;
    }

    setState(() => _saveState = const AsyncLoading<void>());

    final result = await AsyncValue.guard(() async {
      await adminCustomerLedgerRepository.insertPayment(
        customerId: customer.id,
        amount: amount,
        paymentMethod: _method,
        paymentDate: _date,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      );
    });

    if (!mounted) return;
    setState(() => _saveState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Kaydetme hatası: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(_paymentCustomersFutureProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.s16,
          right: AppSpacing.s16,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
          top: AppSpacing.s16,
        ),
        child: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tahsilat Ekle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  Text(
                    'Cari',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  AppSearchField(
                    hintText: 'Cari adı / kodu ara',
                    initialValue: '',
                    padded: false,
                    onChanged: (value) => ref
                        .read(_paymentCustomerSearchProvider.notifier)
                        .state = value,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  customersAsync.when(
                    loading: () => const AppLoadingState(),
                    error: (e, _) => AppErrorState(
                      message: 'Cariler yüklenemedi: ${AppException.messageOf(e)}',
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
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          final selected = _selectedCustomer?.id == c.id;
                          return AppListTile(
                            title: c.name,
                            subtitle: c.code,
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  )
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedCustomer = c;
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Tutar',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Yöntem',
                    ),
                    items: PaymentMethod.values
                        .map(
                          (m) => DropdownMenuItem<PaymentMethod>(
                            value: m,
                            child: Text(m.labelTr),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _method = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tarih: ${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.s4,
                          ),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _date = picked);
                          }
                        },
                        child: const Text('Tarih Seç'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama (opsiyonel)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  PrimaryButton(
                    label:
                        _saveState.isLoading ? 'Kaydediliyor...' : 'Kaydet',
                    expand: true,
                    onPressed: _saveState.isLoading ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentsSummary {
  const _PaymentsSummary({
    required this.total,
    required this.today,
    required this.monthToDate,
    required this.count,
  });

  final double total;
  final double today;
  final double monthToDate;
  final int count;
}

class _EditPaymentSheet extends StatefulWidget {
  const _EditPaymentSheet({
    required this.row,
  });

  final PaymentRow row;

  @override
  State<_EditPaymentSheet> createState() => _EditPaymentSheetState();
}

class _EditPaymentSheetState extends State<_EditPaymentSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late PaymentMethod _method;
  late DateTime _date;
  AsyncValue<void> _saveState = const AsyncData<void>(null);

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
    text: widget.row.amount.toStringAsFixed(2),
    );
    _descriptionController = TextEditingController(
      text: widget.row.description,
    );
    _method = widget.row.method;
    _date = widget.row.date;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  double? _parseAmount(String text) {
    if (text.trim().isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    final amount = _parseAmount(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçerli bir tutar girin.')),
      );
      return;
    }

    setState(() => _saveState = const AsyncLoading<void>());

    final result = await AsyncValue.guard(() async {
      await adminCustomerLedgerRepository.updatePayment(
        id: widget.row.id,
        amount: amount,
        method: _method,
        date: _date,
        description: _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim(),
      );

    });

    if (!mounted) return;
    setState(() => _saveState = result);

    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Güncelleme hatası: ${AppException.messageOf(result.error!)}',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.s16,
          right: AppSpacing.s16,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
          top: AppSpacing.s16,
        ),
        child: SingleChildScrollView(
          child: Card(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tahsilatı Düzenle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Tutar',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  DropdownButtonFormField<PaymentMethod>(
                    initialValue: _method,
                    decoration: const InputDecoration(
                      labelText: 'Yöntem',
                    ),
                    items: PaymentMethod.values
                        .map(
                          (m) => DropdownMenuItem<PaymentMethod>(
                            value: m,
                            child: Text(m.labelTr),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _method = value);
                    },
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
            'Tarih: ${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}',
          ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s8,
                            vertical: AppSpacing.s4,
                          ),
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _date = picked);
                          }
                        },
                        child: const Text('Tarih Seç'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama (opsiyonel)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s16),
                  PrimaryButton(
                    label:
                        _saveState.isLoading ? 'Kaydediliyor...' : 'Kaydet',
                    expand: true,
                    onPressed: _saveState.isLoading ? null : _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _PaymentsSummaryCard extends StatelessWidget {
  const _PaymentsSummaryCard({
    required this.summary,
  });

  final _PaymentsSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tahsilat Özeti',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    label: 'Toplam',
                    value: summary.total,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Bugün',
                    value: summary.today,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Bu ay',
                    value: summary.monthToDate,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'İşlem sayısı: ${summary.count}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
		  formatMoney(value),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PaymentsFiltersRow extends StatelessWidget {
  const _PaymentsFiltersRow({
    required this.range,
    required this.onRangeChanged,
    required this.methods,
    required this.selectedMethod,
    required this.onMethodChanged,
  });

  final _PaymentsRange range;
  final ValueChanged<_PaymentsRange> onRangeChanged;
  final List<PaymentMethod> methods;
  final PaymentMethod? selectedMethod;
  final ValueChanged<PaymentMethod?> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s8,
          runSpacing: AppSpacing.s4,
          children: [
            ChoiceChip(
              label: const Text('Son 7 gün'),
              selected: range == _PaymentsRange.days7,
              onSelected: (_) => onRangeChanged(_PaymentsRange.days7),
            ),
            ChoiceChip(
              label: const Text('Son 30 gün'),
              selected: range == _PaymentsRange.days30,
              onSelected: (_) => onRangeChanged(_PaymentsRange.days30),
            ),
            ChoiceChip(
              label: const Text('Bu ay'),
              selected: range == _PaymentsRange.monthToDate,
              onSelected: (_) => onRangeChanged(_PaymentsRange.monthToDate),
            ),
            ChoiceChip(
              label: const Text('Tümü'),
              selected: range == _PaymentsRange.all,
              onSelected: (_) => onRangeChanged(_PaymentsRange.all),
            ),
          ],
        ),
        if (methods.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s4,
            children: [
              ChoiceChip(
                label: const Text('Tüm yöntemler'),
                selected: selectedMethod == null,
                onSelected: (_) => onMethodChanged(null),
              ),
              for (final method in methods)
                ChoiceChip(
                  label: Text(method.labelTr),
                  selected: selectedMethod == method,
                  onSelected: (_) => onMethodChanged(method),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PaymentListRow extends StatelessWidget {
  const _PaymentListRow({
    required this.row,
    required this.onEdit,
    required this.onCancel,
  });

  final PaymentRow row;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountText = formatMoney(row.amount);
    final dateText = formatDate(row.date);

    final isCancelled = row.isCancelled;

    final textColor = isCancelled
      ? theme.colorScheme.outline
      : theme.textTheme.bodyMedium?.color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                if (row.description.isNotEmpty)
                  Text(
                    row.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor,
                    ),
                  ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Yöntem: ${row.method.labelTr}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isCancelled
                        ? theme.colorScheme.outline
                        : theme.colorScheme.onSurface
                            .withValues(alpha: 0.7),
                  ),
                ),
                if (isCancelled) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    'İptal edildi${row.cancelReason != null && row.cancelReason!.isNotEmpty ? ' (${row.cancelReason})' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                amountText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isCancelled
                      ? theme.colorScheme.outline
                      : theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              PopupMenuButton<String>(
                itemBuilder: (context) {
                  if (isCancelled) {
                    return const [
                      PopupMenuItem<String>(
                        value: 'cancelled',
                        enabled: false,
                        child: Text('İptal edilmiş'),
                      ),
                    ];
                  }
                  return const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text('Düzenle'),
                    ),
                    PopupMenuItem<String>(
                      value: 'cancel',
                      child: Text('Tahsilatı İptal Et'),
                    ),
                  ];
                },
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'cancel') {
                    onCancel();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<PaymentRow> _applyPaymentFilters(
  List<PaymentRow> rows, {
  PaymentMethod? method,
}) {
  var result = rows;

  if (method != null) {
    result = result.where((r) => r.method == method).toList();
  }

  return result;
}

List<PaymentMethod> _extractPaymentMethods(List<PaymentRow> rows) {
  final methods = rows.map((r) => r.method).toSet().toList()
    ..sort((a, b) => a.dbValue.compareTo(b.dbValue));
  return methods;
}
