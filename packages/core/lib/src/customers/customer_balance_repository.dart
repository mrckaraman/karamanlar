import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class CustomerBalanceRepository {
  CustomerBalanceRepository(this._client);

  final SupabaseClient _client;

  /// Returns the current customer balance from `v_customer_balance.net`.
  ///
  /// - If the customer has no row in the view, returns 0.
  /// - Uses `.single()` to enforce a 1-row contract.
  Future<double> getCustomerBalance(String customerId) async {
    if (customerId.trim().isEmpty) return 0;

    try {
      final dynamic row = await guardPostgrest(
        'customer_balance(net)',
        () => _client
            .from('v_customer_balance')
            .select('net')
            .eq('customer_id', customerId)
            .single(),
      );

      final map = Map<String, dynamic>.from(row as Map);
      return (map['net'] as num?)?.toDouble() ?? 0;
    } on PostgrestException catch (e) {
      // `.single()` throws if 0 rows (or multiple rows). The view is expected
      // to be 1-row-per-customer; treat 0 rows as empty balance.
      final msg = e.message.toLowerCase();
      final details = (e.details ?? '').toString().toLowerCase();
      final code = (e.code ?? '').toString();

      final isNoRow =
          msg.contains('0 rows') ||
          msg.contains('no rows') ||
          details.contains('0 rows') ||
          details.contains('no rows') ||
          msg.contains('json object requested') ||
          details.contains('json object requested') ||
          code == 'PGRST116';

      if (isNoRow) return 0;
      rethrow;
    }
  }
}

final customerBalanceRepository = CustomerBalanceRepository(supabaseClient);
