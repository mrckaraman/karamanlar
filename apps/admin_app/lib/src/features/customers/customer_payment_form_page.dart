import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CustomerPaymentFormPage extends ConsumerStatefulWidget {
  const CustomerPaymentFormPage({
    super.key,
    required this.customerId,
  });

  final String? customerId;

  @override
  ConsumerState<CustomerPaymentFormPage> createState() =>
      _CustomerPaymentFormPageState();
}

class _CustomerPaymentFormPageState
    extends ConsumerState<CustomerPaymentFormPage> {
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
    if (_saveState.isLoading) {
      return;
    }

    final customerId = widget.customerId;
    if (customerId == null || customerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geçersiz müşteri bilgisi (customerId yok).')),
      );
      return;
    }

    final session = supabaseClient.auth.currentSession;
    if (session == null) {
      if (!mounted) return;
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
        customerId: customerId,
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
      final message = AppException.messageOf(result.error!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $message')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tahsilat kaydedildi.')),
    );
    GoRouter.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final customerId = widget.customerId;

    if (customerId == null || customerId.isEmpty) {
      return const AppScaffold(
        title: 'Tahsilat Ekle',
        body: Center(
          child: Text('Geçersiz veya eksik müşteri bilgisi (customerId null/boş).'),
        ),
      );
    }

    return AppScaffold(
      title: 'Tahsilat Ekle',
      body: SingleChildScrollView(
        child: Card(
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TahsilatEklePage render edildi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.s8),
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
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              ],
            ),
          ),
        ),
      ),
      bottom: SafeArea(
        top: false,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: PrimaryButton(
              label: _saveState.isLoading ? 'Kaydediliyor...' : 'Kaydet',
              expand: true,
              onPressed: _saveState.isLoading ? null : _save,
            ),
          ),
        ),
      ),
    );
  }
}
