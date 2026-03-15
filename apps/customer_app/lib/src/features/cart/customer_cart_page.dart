import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import 'package:go_router/go_router.dart';

import 'cart_controller.dart';

class CustomerCartPage extends ConsumerStatefulWidget {
  const CustomerCartPage({super.key});

  @override
  ConsumerState<CustomerCartPage> createState() => _CustomerCartPageState();
}

class _CustomerCartPageState extends ConsumerState<CustomerCartPage> {
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    return AppScaffold(
      title: 'Sepet',
      actions: const [],
      body: cart.isEmpty
          ? AppEmptyState(
              title: 'Sepetiniz boş',
              subtitle: 'Yeni sipariş oluşturmak için ürün ekleyin.',
              action: PrimaryButton(
                label: 'Ürün ekle',
                icon: Icons.add,
                onPressed: () {},
              ),
            )
          : ListView.separated(
              itemCount: cart.items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = cart.items[index];
                return _CartItemRow(item: item);
              },
            ),
      bottom: cart.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
              'Genel Toplam',
              style: TextStyle(fontWeight: FontWeight.bold),
              ),
            Text(formatMoney(cart.total)),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s12),
                      PrimaryButton(
                        label:
                            _isSubmitting ? 'Gönderiliyor...' : 'Siparişi Onayla',
                        icon:
                            _isSubmitting ? Icons.hourglass_top : Icons.send,
                        expand: true,
                        onPressed: _isSubmitting
                            ? null
                            : () async {
                                // Basit not girişi için dialog; daha sonra
                                // tam ekran form ile genişletilebilir.
                                final note = await showDialog<String>(
                                  context: context,
                                  builder: (dialogContext) {
                                    final controller = TextEditingController();
                                    return AlertDialog(
                                      title:
                                          const Text('Sipariş Notu (opsiyonel)'),
                                      content: TextField(
                                        controller: controller,
                                        maxLines: 3,
                                        decoration: const InputDecoration(
                                          hintText: 'Teslimat notu vb.',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(null),
                                          child: const Text('Vazgeç'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext)
                                                  .pop(controller.text),
                                          child: const Text('Gönder'),
                                        ),
                                      ],
                                    );
                                  },
                                );

                                if (!context.mounted) return;

                                final currentCart =
                                    ref.read(cartControllerProvider);

                                if (currentCart.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Sepetiniz boş'),
                                    ),
                                  );
                                  return;
                                }

                                try {
                                  setState(() {
                                    _isSubmitting = true;
                                  });

                                  await ref
                                      .read(cartControllerProvider.notifier)
                                      .submitOrder(note: note);

                                    if (!context.mounted) return;

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Siparişiniz başarıyla oluşturuldu.',
                                      ),
                                    ),
                                  );
                                  context.go('/orders/success');
                                } catch (e, st) {
                                  debugPrint(
                                    '[CustomerCart] submitOrder failed: $e',
                                  );
                                  debugPrintStack(stackTrace: st);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'İşlem başarısız. Lütfen tekrar deneyin.',
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _isSubmitting = false;
                                    });
                                  }
                                }
                              },
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      TextButton(
                        onPressed: () {
                          ref
                              .read(cartControllerProvider.notifier)
                              .clear();
                        },
                        child: const Text('Sepeti Temizle'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _CartItemRow extends ConsumerWidget {
  const _CartItemRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppListTile(
      title: item.product.name,
      subtitle: item.product.code,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () {
              ref
                  .read(cartControllerProvider.notifier)
                  .decrementProduct(item.product.stockId);
            },
          ),
          Text('${item.quantity}'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              ref
                  .read(cartControllerProvider.notifier)
                  .addProduct(item.product);
            },
          ),
          const SizedBox(width: 8),
          Text(formatMoney(item.lineTotal)),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              ref
                  .read(cartControllerProvider.notifier)
                  .removeProduct(item.product.stockId);
            },
          ),
        ],
      ),
    );
  }
}
