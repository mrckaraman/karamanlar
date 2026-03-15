import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/formatters_tr.dart';
import '../../utils/supabase_storage.dart';
import 'cart_controller.dart';

final _cartAddSearchProvider = StateProvider<String>((ref) => '');

final _cartAddProductsProvider =
    FutureProvider.autoDispose<List<CustomerProduct>>((ref) async {
  final search = ref.watch(_cartAddSearchProvider).trim();
  final repo = customerProductRepository;

  final customerId = ref.watch(customerIdProvider);
  if (customerId == null || customerId.isEmpty) {
    return <CustomerProduct>[];
  }

  final items = await repo.fetchProducts(
    customerId: customerId,
    page: 0,
    pageSize: 50,
    search: search.isEmpty ? null : search,
  );
  return items;
});

class CustomerCartAddProductsPage extends ConsumerStatefulWidget {
  const CustomerCartAddProductsPage({super.key});

  @override
  ConsumerState<CustomerCartAddProductsPage> createState() =>
      _CustomerCartAddProductsPageState();
}

class _CustomerCartAddProductsPageState
    extends ConsumerState<CustomerCartAddProductsPage> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(_cartAddSearchProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    ref.read(_cartAddSearchProvider.notifier).state = value;
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_cartAddProductsProvider);
    final cart = ref.watch(cartControllerProvider);

    return AppScaffold(
      title: 'Ürün Ekle',
      body: Column(
        children: [
          if (!cart.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PrimaryButton(
                label: 'Sepete git',
                icon: Icons.shopping_cart_outlined,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          AppSearchField(
            hintText: 'Ara (ad / kod / barkod)',
            initialValue: ref.read(_cartAddSearchProvider),
            padded: false,
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: AppSpacing.s8),
          Expanded(
            child: productsAsync.when(
              loading: () => const AppLoadingState(),
              error: (error, _) => AppErrorState(
                message: 'Ürünler yüklenemedi: $error',
                onRetry: () =>
                    ref.refresh(_cartAddProductsProvider.future),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const AppEmptyState(
                    title: 'Uygun ürün bulunamadı',
                    subtitle:
                        'Arama kriterlerini değiştirerek tekrar deneyebilirsiniz.',
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = items[index];
                    return AppListTile(
                      leading:
                          _ProductImage(imagePath: product.imagePath),
                      title: product.name,
                      subtitle: product.code,
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          ref
                              .read(cartControllerProvider.notifier)
                              .addProduct(product);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${product.name} sepete eklendi',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (!cart.isEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Seçilen ürünler',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.s4),
                          Text(
              '${cart.items.length} kalem, toplam ${formatMoney(cart.total)}',
              style: Theme.of(context).textTheme.bodySmall,
              ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s12),
                    PrimaryButton(
                      label: 'Sepete git',
                      icon: Icons.shopping_cart_outlined,
                      expand: false,
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({this.imagePath});

  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final url = mapStockImagePathToPublicUrl(imagePath);

    if (url == null) {
      return const CircleAvatar(child: Icon(Icons.image_not_supported));
    }

    return CircleAvatar(
      child: ClipOval(
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(Icons.image_not_supported);
          },
        ),
      ),
    );
  }
}
