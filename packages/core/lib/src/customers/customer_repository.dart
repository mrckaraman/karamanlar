import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import 'customer.dart';

class CustomerRepository {
  CustomerRepository(this._client);

  final SupabaseClient _client;

  Future<Customer?> fetchCustomerById(String id) async {
    final dynamic data = await _client
        .from('customers')
        .select(customerSelectColumns)
        .eq('id', id)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return Customer.fromMap(data as Map<String, dynamic>);
  }

  /// Aktif oturumdaki kullanıcının bağlı olduğu müşteri kaydını döner.
  ///
  /// Eşleşme, customers.auth_user_id = auth.currentUser.id kuralına göre
  /// yapılır. Hiç kayıt yoksa `null` döner.
  Future<Customer?> fetchCurrentCustomer() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) {
      return null;
    }

    final currentUserId = currentUser.id;
    print('[CUSTOMER] fetchCurrentCustomer authUserId=$currentUserId');

    final dynamic data = await _client
        .from('customers')
        .select(customerSelectColumns)
        .eq('auth_user_id', currentUserId)
        .maybeSingle();

    print('[CUSTOMER] fetchCurrentCustomer raw=$data');

    if (data == null) {
      return null;
    }

    return Customer.fromMap(data as Map<String, dynamic>);
  }

  Future<List<Customer>> fetchCustomers({
    String? search,
    bool? isActive,
    int limit = 50,
  }) async {
    var query = _client
        .from('customers')
        .select(customerSelectColumns);

    if (search != null && search.isNotEmpty) {
      final pattern = '%${search.toLowerCase()}%';
      query = query.or(
        'full_name.ilike.$pattern,'
        'trade_title.ilike.$pattern,'
        'customer_code.ilike.$pattern,'
        'email.ilike.$pattern,'
        'phone.ilike.$pattern',
      );
    }

    if (isActive != null) {
      query = query.eq('is_active', isActive);
    }

    final data = await query.order('trade_title').limit(limit);

    return (data as List<dynamic>)
        .map((e) => Customer.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}

final customerRepository = CustomerRepository(supabaseClient);
