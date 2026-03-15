import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import 'stock_movement.dart';

class StockMovementRepository {
  StockMovementRepository(this._client);

  final SupabaseClient _client;

  Future<List<StockMovement>> fetchMovements({
    required String stockId,
    int page = 0,
    int pageSize = 20,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;

    final data = await _client
        .from('stock_movements')
        .select(
          'id, stock_id, movement_type, qty, note, created_at, created_by',
        )
        .eq('stock_id', stockId)
        .order('created_at', ascending: false)
        .range(from, to);

    final list = data as List<dynamic>;

    // Debug log: movements fetch detayları
    // Network tabında hangi endpoint çağrıldığına ek olarak,
    // burada tablo adı, stok id ve dönen satır sayısı da console'a yazılır.
    // Bu, Excel import sonrasında fiyat geçmişi neden boş görünüyor
    // sorusunu debug ederken yardımcı olur.
    //
    // Örnek log:
    // [StockMovementRepository.fetchMovements] table=stock_movements stockId=... page=0 size=50 rawCount=3
    print(
      '[StockMovementRepository.fetchMovements] table=stock_movements '
      'stockId=$stockId page=$page size=$pageSize from=$from to=$to rawCount=${list.length}',
    );

    return list
        .map((e) => StockMovement.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<num> createMovement({
    required String stockId,
    required String type,
    required num qty,
    String? note,
  }) async {
    if (qty <= 0) {
      throw ArgumentError('Miktar 0 veya negatif olamaz.');
    }

    if (type != 'in' && type != 'out' && type != 'adjust') {
      throw ArgumentError('Gecersiz hareket tipi: $type');
    }

    try {
      final result = await _client.rpc(
        'rpc_apply_stock_movement',
        params: <String, dynamic>{
          'p_stock_id': stockId,
          'p_type': type,
          'p_qty': qty,
          'p_note': note,
        },
      );

      // Beklenen donus: { movement_id: uuid, new_quantity: numeric }
      final map = result as Map<String, dynamic>;
      final newQtyDynamic = map['new_quantity'];
      if (newQtyDynamic == null) {
        throw Exception('RPC sonucu beklenen new_quantity alanini icermiyor.');
      }
      if (newQtyDynamic is num) {
        return newQtyDynamic;
      }
      return num.parse(newQtyDynamic.toString());
    } on PostgrestException catch (e) {
      // Supabase/Postgres hatalarini yukari anlamli bir sekilde gonder
      throw Exception(e.message);
    }
  }
}

final stockMovementRepository = StockMovementRepository(supabaseClient);
