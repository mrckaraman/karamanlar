import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import 'category.dart';

class CategoryRepository {
  CategoryRepository(this._client);

  final SupabaseClient _client;

  Future<Category> getCategory(String id) async {
    final data = await _client
        .from('categories')
        .select('id, name, code, parent_id, level, is_active')
        .eq('id', id)
        .single();

    return Category.fromMap(Map<String, dynamic>.from(data));
  }

  /// Admin listeleri için düz kategori listesi (root filtresi olmadan).
  Future<List<Category>> fetchCategoriesForAdmin({
    String? search,
    bool? isActive,
  }) async {
    var query = _client
        .from('categories')
        .select('id, name, code, parent_id, level, is_active');

    if (isActive != null) {
      query = query.eq('is_active', isActive);
    }

    if (search != null && search.trim().isNotEmpty) {
      final pattern = '%${search.trim().toLowerCase()}%';
      query = query.or('name.ilike.$pattern,code.ilike.$pattern');
    }

    final data = await query
      .order('level')
      .order('name');

    return (data as List<dynamic>)
        .map((e) => Category.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<Category>> fetchCategories({
    String? parentId,
    String? search,
    bool activeOnly = true,
  }) async {
    var query = _client
      .from('categories')
      .select('id, name, code, parent_id, level, is_active');

    if (activeOnly) {
      query = query.eq('is_active', true);
    }

    if (parentId != null) {
      query = query.eq('parent_id', parentId);
    }

    if (search != null && search.trim().isNotEmpty) {
      final pattern = '%${search.trim().toLowerCase()}%';
      query = query.or('name.ilike.$pattern,code.ilike.$pattern');
    }

    final data = await query
      .order('level')
      .order('name');

    final list = (data as List<dynamic>)
      .map((e) => Category.fromMap(Map<String, dynamic>.from(e)))
      .toList();

    // parentId belirtilmemişse, kök (root) kategorileri dön.
    if (parentId == null) {
      return list.where((c) => c.parentId == null).toList();
    }

    return list;
  }

  Future<List<Category>> fetchChildren(String? parentId,
      {bool activeOnly = true}) {
    return fetchCategories(parentId: parentId, activeOnly: activeOnly);
  }

  /// Verilen kategori için kökten başlayarak ata zincirini döner (root → leaf).
  Future<List<Category>> fetchAncestors(String categoryId) async {
    final List<Category> chain = [];
    String? currentId = categoryId;

    // 3 seviye varsayımı, yine de güvenli olsun diye 5 ile sınırla.
    for (var i = 0; i < 5 && currentId != null; i++) {
      final data = await _client
          .from('categories')
      .select('id, name, code, parent_id, level, is_active')
      .eq('id', currentId)
      .maybeSingle();

      if (data == null) break;

      final cat = Category.fromMap(Map<String, dynamic>.from(data));
      chain.insert(0, cat);
      currentId = cat.parentId;
    }

    return chain;
  }

  /// Verilen kategori altında (onu da dahil ederek) tüm leaf kategori ID'lerini döner.
  /// 3 seviye hiyerarşi varsayımı ile tüm kategorileri memory'de gezerek çözer.
  Future<List<String>> fetchLeafIdsUnder(String categoryId) async {
    final data = await _client
      .from('categories')
      .select('id, name, code, parent_id, level, is_active')
      .eq('is_active', true)
      .order('level')
      .order('name');

    final all = (data as List<dynamic>)
      .map((e) => Category.fromMap(Map<String, dynamic>.from(e)))
      .toList();

    final Set<String> subtreeIds = <String>{};
    final List<String> queue = <String>[categoryId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (!subtreeIds.add(current)) continue;

      final children =
          all.where((c) => c.parentId == current).map((c) => c.id).toList();
      queue.addAll(children);
    }

    final leafIds = subtreeIds.where((id) {
      final hasChild = all.any((c) => c.parentId == id);
      return !hasChild;
    }).toList();

    return leafIds;
  }

  Future<Category> createCategory({
    required String name,
    String? code,
    String? parentId,
    bool isActive = true,
    int sort = 0,
  }) async {
    final inserted = await _client
        .from('categories')
        .insert({
          'name': name,
          'code': code,
          'parent_id': parentId,
          'is_active': isActive,
          'sort': sort,
        })
        .select('id, name, code, parent_id, level, is_active')
        .single();

    return Category.fromMap(Map<String, dynamic>.from(inserted));
  }

  Future<Category> updateCategory(Category category) async {
    final updated = await _client
        .from('categories')
        .update({
          'name': category.name,
          'code': category.code,
          'parent_id': category.parentId,
          'is_active': category.isActive,
          'sort': category.sort,
        })
        .eq('id', category.id)
        .select('id, name, code, parent_id, level, is_active')
        .single();

    return Category.fromMap(Map<String, dynamic>.from(updated));
  }

  Future<void> toggleActive(String id, bool isActive) async {
    await _client
        .from('categories')
	  .update({'is_active': isActive})
	  .eq('id', id);
  }
}

final categoryRepository = CategoryRepository(supabaseClient);
