import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _categorySearchProvider = StateProvider<String>((ref) => '');
final _categoryActiveOnlyProvider = StateProvider<bool>((ref) => true);

final categoriesFutureProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final search = ref.watch(_categorySearchProvider);
  final activeOnly = ref.watch(_categoryActiveOnlyProvider);

  return categoryRepository.fetchCategoriesForAdmin(
    search: search.trim().isEmpty ? null : search.trim(),
    isActive: activeOnly ? true : null,
  );
});

class CategoryListPage extends ConsumerWidget {
  const CategoryListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesFutureProvider);
    final activeOnly = ref.watch(_categoryActiveOnlyProvider);

    return AppScaffold(
      title: 'Kategoriler',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Kategori adı / kod ara',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      ref.read(_categorySearchProvider.notifier).state = value;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: [
                    const Text('Sadece aktif'),
                    Switch(
                      value: activeOnly,
                      onChanged: (value) {
                        ref
                            .read(_categoryActiveOnlyProvider.notifier)
                            .state = value;
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {
                  GoRouter.of(context).go('/categories/new');
                },
                icon: const Icon(Icons.add),
                label: const Text('Yeni Kategori'),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: categoriesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Kategoriler yüklenemedi: $e'),
                ),
                data: (categories) {
                  if (categories.isEmpty) {
                    return const Center(child: Text('Kayıt bulunamadı.'));
                  }

                  return ListView.separated(
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return ListTile(
                        title: Text(category.name),
                        subtitle: category.code != null && category.code!.isNotEmpty
                            ? Text('Kod: ${category.code}')
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (category.isActive ?? true)
                              const Chip(
                                label: Text('Aktif'),
                                visualDensity: VisualDensity.compact,
                              )
                            else
                              const Chip(
                                label: Text('Pasif'),
                                visualDensity: VisualDensity.compact,
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                GoRouter.of(context)
                                    .go('/categories/${category.id}/edit');
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
