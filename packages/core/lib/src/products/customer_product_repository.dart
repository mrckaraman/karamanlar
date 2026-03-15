import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import 'customer_product.dart';

class CustomerProductRepository {
  CustomerProductRepository(this._client);

  final SupabaseClient _client;

  static const String ungroupedGroupName = '__UNGROUPED__';

  /// Müşteri ürün listesini döndürür.
  Future<List<CustomerProduct>> fetchProducts({
    required String customerId,
    int page = 0,
    int pageSize = 20,
    String? search,
    String? groupName,
  }) async {
    final fromIndex = page * pageSize;
    final toIndex = fromIndex + pageSize - 1;

    // Temel seçim: müşteri tarafından görülebilecek stok alanları.
    // Not: view içinde stok ID'si `id` kolonunda tutuluyor.
    var query = _client
        .from('v_customer_stock_prices')
        .select(
          'stock_id, id, name, code, barcode, brand, image_path, '
          'unit, unit_price, base_unit_price, '
          'tax_rate, base_unit_name, pack_unit_name, pack_multiplier, '
          'box_unit_name, box_multiplier, '
          'barcode_text, group_name, subgroup_name, subsubgroup_name, is_active',
        )
        .eq('is_active', true)
        .eq('customer_id', customerId);

    // Arama: ad, kod ve barkod alanları üzerinde filtre.
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim();
      query = query.or(
        'name.ilike.%$q%,code.ilike.%$q%,barcode.ilike.%$q%,'
        'pack_barcode.ilike.%$q%,box_barcode.ilike.%$q%,barcode_text.ilike.%$q%',
      );
    }

    // Basit grup filtresi: group_name eşitliği.
    // Not: groupName = ungroupedGroupName => group_name IS NULL olanlar.
    if (groupName != null && groupName.trim().isNotEmpty) {
      final g = groupName.trim();
      if (g == ungroupedGroupName) {
        query = query.isFilter('group_name', null);
      } else {
        query = query.eq('group_name', g);
      }
    }

    final data = await guardPostgrest(
      'v_customer_stock_prices.fetchProducts page=$page pageSize=$pageSize search="$search" groupName="$groupName"',
      () => query.order('name').range(fromIndex, toIndex),
    );

    final rows = (data as List).cast<Map<String, dynamic>>();
    return rows.map(CustomerProduct.fromMap).toList();
  }

  /// Müşterinin aktif ürün gruplarını döndürür.
  ///
  /// - Gruplar view'deki `group_name` alanından okunur.
  /// - group_name NULL olan ürünler varsa listeye [ungroupedGroupName]
  ///   sentinel değeri eklenir.
  Future<List<String>> fetchGroupNames({
    required String customerId,
    int limit = 5000,
  }) async {
    final data = await guardPostgrest(
      'v_customer_stock_prices.fetchGroupNames limit=$limit',
      () => _client
          .from('v_customer_stock_prices')
          .select('group_name')
          .eq('is_active', true)
          .eq('customer_id', customerId)
          .order('group_name')
          .range(0, limit - 1),
    );

    final rows = (data as List).cast<Map<String, dynamic>>();
    final names = <String>{};
    var hasUngrouped = false;

    for (final row in rows) {
      final raw = row['group_name'] as String?;
      final name = raw?.trim();
      if (name == null || name.isEmpty) {
        hasUngrouped = true;
      } else {
        names.add(name);
      }
    }

    final result = names.toList()..sort();
    if (hasUngrouped) {
      result.add(ungroupedGroupName);
    }
    return result;
  }
}

final customerProductRepository = CustomerProductRepository(supabaseClient);
