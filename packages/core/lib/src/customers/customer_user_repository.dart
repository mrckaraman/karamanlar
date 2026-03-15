import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';

class AuthUserSummary {
  const AuthUserSummary({
    required this.id,
    required this.email,
  });

  final String id;
  final String email;

  factory AuthUserSummary.fromMap(Map<String, dynamic> map) {
    return AuthUserSummary(
      id: map['id'] as String,
      email: map['email'] as String,
    );
  }
}

class CustomerUserRepository {
  CustomerUserRepository(this._client);

  final SupabaseClient _client;

  /// auth.users tablosunda email ile arama için bir RPC bekler.
  ///
  /// Supabase tarafında sadece admin rolüne izin veren,
  /// id ve email dönen bir fonksiyon tanımlanmış olmalıdır.
  Future<List<AuthUserSummary>> searchUsersByEmail(String query) async {
    if (query.isEmpty) return [];

    final data = await _client.rpc(
      'admin_search_users_by_email',
      params: {'query': query},
    );

    return (data as List<dynamic>)
        .map((e) => AuthUserSummary.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> linkCustomerToUser({
    required String customerId,
    required String userId,
  }) async {
    // customer_users tablosu yerine doğrudan customers.auth_user_id alanını günceller.
    await _client
        .from('customers')
        .update(<String, dynamic>{'auth_user_id': userId})
        .eq('id', customerId);
  }

  /// Edge Function aracılığıyla yeni bir müşteri kullanıcısı oluşturur.
  ///
  /// Bu fonksiyon client tarafında service role kullanmadan, sadece
  /// `supabase.functions.invoke` ile `create_customer_user` edge
  /// fonksiyonunu tetikler ve varsa dönen payload'u map olarak iletir.
  Future<Map<String, dynamic>?> createCustomerUserViaEdgeFunction({
    required String customerId,
    required String email,
  }) async {
    final session = _client.auth.currentSession;
    final accessToken = session?.accessToken;

    if (accessToken == null) {
      // Admin oturumu yoksa, UI tarafında yakalanıp kullanıcıya
      // net bir mesaj gösterilmesi için anlamlı bir hata fırlat.
      throw Exception('Admin oturumu yok. Lütfen tekrar giriş yapın.');
    }

    final response = await _client.functions.invoke(
      'create_customer_user',
      body: <String, dynamic>{
        'customer_id': customerId,
        'email': email,
      },
      headers: <String, String>{
        'Authorization': 'Bearer $accessToken',
      },
    );

    // 401 durumunda yetkilendirme hatasını daha okunaklı hale getir.
    if (response.status == 401) {
      throw Exception(
        'Yetkilendirme hatası (401). Admin oturumu süresi dolmuş olabilir.',
      );
    }

    final data = response.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  /// Aktif oturumdaki kullanıcı için backend'de tanımlı
  /// `link_customer_to_auth_user` RPC'sini çağırır.
  ///
  /// Artık doğrudan customers tablosundaki auth_user_id alanını kullanarak
  /// eşleşen cari kaydını döner.
  Future<String?> linkCustomerToAuthUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Oturum bulunamadı.');
    }

    final authUserId = user.id;

    final mapping = await _client
        .from('customers')
        .select('id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    if (mapping == null || mapping['id'] == null) {
      return null;
    }

    return mapping['id'] as String;
  }

  /// Aktif oturum açmış kullanıcının bağlı olduğu customer id değerini döner.
  ///
  /// Eşleşme, customers tablosundaki auth_user_id alanı üzerinden yapılır.
  Future<String> getCurrentCustomerId() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception('Oturum bulunamadı.');
    }
    final authUserId = user.id;

    final mapping = await _client
        .from('customers')
        .select('id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    if (mapping == null || mapping['id'] == null) {
      // Hiçbir eşleşme yoksa net bir mesaj ver.
      throw Exception('Cari eşleşmesi yok: customers.auth_user_id set et.');
    }

    return mapping['id'] as String;
  }
}

final customerUserRepository = CustomerUserRepository(supabaseClient);

/// current user -> customer_id state provider
///
/// Müşteri uygulamasında login / OTP akışları sonrasında
/// customerId değeri buraya yazılır ve diğer ekranlar tarafından
/// okunur.
final customerIdProvider = StateProvider<String?>((ref) => null);
