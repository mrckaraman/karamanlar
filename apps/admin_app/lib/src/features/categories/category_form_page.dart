import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CategoryFormPage extends ConsumerStatefulWidget {
  const CategoryFormPage({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _sortController = TextEditingController();

  bool _isActive = true;
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.categoryId != null) {
      _load();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final category = await categoryRepository.getCategory(widget.categoryId!);
      _nameController.text = category.name;
      _codeController.text = category.code ?? '';
      _sortController.text = (category.sort ?? 0).toString();
      _isActive = category.isActive ?? true;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kategori yüklenemedi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int? _parseInt(String text) {
    if (text.trim().isEmpty) return null;
    return int.tryParse(text.trim());
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori adı zorunludur.')),
      );
      return;
    }

    final sortText = _sortController.text;
    final sort = _parseInt(sortText) ?? 0;

    setState(() => _saving = true);
    try {
      if (widget.categoryId == null) {
        await categoryRepository.createCategory(
          name: name,
          code: _codeController.text.trim().isEmpty
              ? null
              : _codeController.text.trim(),
          isActive: _isActive,
          sort: sort,
        );
      } else {
        final category = Category(
          id: widget.categoryId!,
          name: name,
          code: _codeController.text.trim().isEmpty
              ? null
              : _codeController.text.trim(),
          parentId: null,
          level: null,
          isActive: _isActive,
          sort: sort,
        );
        await categoryRepository.updateCategory(category);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kategori kaydedildi.')),
      );
      GoRouter.of(context).go('/categories');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme hatası: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.categoryId != null;

    return AppScaffold(
      title: isEdit ? 'Kategori Düzenle' : 'Yeni Kategori',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Ad *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _codeController,
                    decoration:
                        const InputDecoration(labelText: 'Kod (opsiyonel)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sortController,
                    decoration: const InputDecoration(
                      labelText: 'Sıra (opsiyonel, sayı)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: false),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Aktif'),
                      Switch(
                        value: _isActive,
                        onChanged: (value) {
                          setState(() {
                            _isActive = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _saving ? 'Kaydediliyor...' : 'Kaydet',
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
    );
  }
}
