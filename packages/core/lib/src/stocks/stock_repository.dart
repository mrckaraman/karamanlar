import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import '../storage/storage_buckets.dart';
import 'stock.dart';
import 'stock_unit.dart';
import 'invalid_stock.dart';
import 'import_export/import_result.dart';
import 'import_export/stock_csv.dart';

class StockRepository {
  StockRepository(this._client);

  final SupabaseClient _client;

  Future<Stock> getStock(String id) async {
    final data = await _client
    .from('stocks')
    .select()
    .eq('id', id)
    .single();

    return Stock.fromMap(data);
  }

  /// ID'ye gore stok kaydini dondurur; satir yoksa null dondurur.
  ///
  /// RLS veya gercekten silinmis kayit nedeniyle 0 satir gelirse null,
  /// ag/hizmet hatalarinda ise istisna firlatir.
  Future<Stock?> maybeGetStock(String id) async {
    final dynamic data = await guardPostgrest(
      'stocks.maybeGetStock id=$id',
      () => _client
          .from('stocks')
          .select()
          .eq('id', id)
          .maybeSingle(),
    );

    if (data == null) {
      return null;
    }

    return Stock.fromMap(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Stock>> fetchStocks({
    int page = 0,
    int pageSize = 20,
    String? search,
    bool? isActive,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    var query = _client.from('stocks').select();

    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim();
      final pattern = '%${q.toLowerCase()}%';
      query = query.or(
        'name.ilike.$pattern,code.ilike.$pattern,barcode.ilike.$pattern,'
        'pack_barcode.ilike.$pattern,box_barcode.ilike.$pattern',
      );
    }

    if (isActive != null) {
      query = query.eq('is_active', isActive);
    }

    final data = await query
      .order('name')
      .range(from, to);

    return (data as List<dynamic>)
        .map((e) => Stock.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<(Stock, StockUnit?)> getStockWithUnit(String id) async {
    final session = Supabase.instance.client.auth.currentSession;
    debugPrint('[AUTH] session=${session != null} uid=${session?.user.id}');
    debugPrint('[AUTH] roleHint=${session == null ? "anon" : "authenticated"}');

    final stockRes = await guardPostgrest(
      'stocks.getStockWithUnit id=$id select=* session=${session != null ? "present" : "null"}',
      () => _client
      .from('stocks')
      .select()
      .eq('id', id)
      .maybeSingle(),
    );

    if (stockRes == null) {
      // 0 satır: RLS ile filtrelenmiş veya gerçekten bulunamayan stok.
      // Eski .single() davranışında bu durumda PGRST116/406 dönüyordu.
      // Artık burada yakalayıp daha anlamlı bir hata fırlatıyoruz.
      print('getStockWithUnit: stocks(id=$id) returned 0 rows. '
          'Possible RLS filter or missing record.');
      throw Exception('Stok bulunamadı veya görüntüleme yetkiniz yok.');
    }

    Map<String, dynamic>? unitRes = await _client
        .from('stock_units')
        .select('stock_id, pack_qty, box_qty, carton_qty')
        .eq('stock_id', id)
        .maybeSingle();

    // Eğer stock_units satırı yoksa, null değerlerle bir satır oluşturmayı dene
    // ve ardından tekrar oku. RLS/policy engellerse sadece logla, ekran yine de
    // stok bilgisini gösterebilsin.
    if (unitRes == null) {
      try {
        await upsertStockUnitValues(
          stockId: id,
          packContainsPiece: null,
          caseContainsPiece: null,
        );

        unitRes = await _client
            .from('stock_units')
            .select('stock_id, pack_qty, box_qty, carton_qty')
            .eq('stock_id', id)
            .maybeSingle();
      } on PostgrestException catch (e) {
        // Örn. RLS 403 durumunda sadece logla; unit null kalabilir.
        print('getStockWithUnit: auto-create stock_units row failed: '
            '${e.code} ${e.message}');
      }
    }

    assert(() {
      // Debugging helper to inspect raw stock_units row during development.
      print('getStockWithUnit: id=$id, unitRes=$unitRes');
      return true;
    }());

    final stock = Stock.fromMap(
			Map<String, dynamic>.from(stockRes as Map),
		);
    final unit = unitRes == null ? const StockUnit() : StockUnit.fromMap(unitRes);

    return (stock, unit);
  }

  /// Barkoddan stok ve birim bilgisini bulur.
  ///
  /// Sadece stocks tablosundaki barcode/pack_barcode/box_barcode alanlarına bakar.
  Future<(Stock, StockUnit?)?> findStockByBarcode(String barcode) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    // 1) Ana stok tablolarındaki barkod alanları ile eşleşme dene.
    final stockRow = await guardPostgrest(
      'stocks.findStockByBarcode code=$code',
      () => _client
        .from('stocks')
        .select()
        .or('barcode.eq.$code,pack_barcode.eq.$code,box_barcode.eq.$code')
        .maybeSingle(),
    );

    if (stockRow != null) {
      final stock = Stock.fromMap(stockRow);
      final (_, unit) = await getStockWithUnit(stock.id!);
      return (stock, unit);
    }

    // stock_units tablosunda barkod kolonları artık bulunmadığı için
    // ek bir arama yapılmaz.
    return null;
  }

  Future<List<StockUnit>> fetchStockUnits(String stockId) async {
    final data = await _client
        .from('stock_units')
        .select()
        .eq('stock_id', stockId);

    return (data as List<dynamic>)
        .map((e) => StockUnit.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Admin için, barkod ile katsayıları tutarsız olan stokları döndürür.
  ///
  /// Kaynak: public.v_invalid_stocks view'i.
  Future<List<InvalidStock>> fetchInvalidStocks() async {
    final data = await guardPostgrest(
      'v_invalid_stocks.fetch',
      () => _client
          .from('v_invalid_stocks')
          .select(
            'id, code, name, barcode, pack_barcode, box_barcode, pack_qty, box_qty, invalid_reason',
          )
          .order('name'),
    );

    return (data as List<dynamic>)
        .map((e) => InvalidStock.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Stock> createStock({
    required Stock stock,
    StockUnit? unit,
  }) async {
    final inserted = await _client
        .from('stocks')
        .insert(stock.toInsertMap())
        .select()
        .single();

    final created = Stock.fromMap(inserted);

    if (unit != null) {
      await _client
          .from('stock_units')
          .upsert(unit.toUpsertMap(stockId: created.id!));
    }

    return created;
  }

  Future<Stock> updateStock({
    required Stock stock,
    StockUnit? unit,
  }) async {
    if (stock.id == null) {
      throw ArgumentError('updateStock requires stock.id');
    }

    final updated = await _client
      .from('stocks')
      .update(stock.toUpdateMap())
      .eq('id', stock.id!)
      .select()
      .single();

    if (unit != null) {
      await _client
          .from('stock_units')
          .upsert(unit.toUpsertMap(stockId: stock.id!));
    }

    return Stock.fromMap(updated);
  }

  Future<Stock> upsertStock({
    required Stock stock,
    StockUnit? unit,
  }) {
    if (stock.id == null) {
      return createStock(stock: stock, unit: unit);
    }

    return updateStock(stock: stock, unit: unit);
  }

  Future<void> updateStockImage({
    required Object stockId,
    required String imageUrl,
  }) async {
    await _client
        .from('stocks')
      .update({'image_path': imageUrl})
      .eq('id', stockId);
  }

  Future<void> deleteStock(String id) async {
    await _client
        .from('stocks')
      .update({'is_active': false})
      .eq('id', id);
  }

  /// Kalıcı stok silme (hard delete).
  Future<void> deleteStockPermanently(String id) async {
    await _client
        .from('stocks')
        .delete()
        .eq('id', id);
  }

  Future<void> upsertStockUnit({
    required String stockId,
    required StockUnit unit,
  }) async {
    final payload = unit.toUpsertMap(stockId: stockId);
    print('STOCK_UNITS PAYLOAD => $payload');

    await _client
        .from('stock_units')
        .upsert(payload, onConflict: 'stock_id');
  }

  /// Upsert stock unit quantities for a single stock.
  ///
  /// - [packContainsPiece] ve [caseContainsPiece] UI tarafında girilen adet
  ///   değerleridir ve veritabanında `pack_qty` / `box_qty` alanlarına
  ///   yazılır.
  /// - Eğer değerler null veya 0/negatif ise NULL gönderilir.
  /// - Her stok için en fazla bir `stock_units` satırı olacak şekilde
  ///   `stock_id` üzerinde upsert yapılır.
  Future<void> upsertStockUnitValues({
    required String stockId,
    int? packContainsPiece,
    int? caseContainsPiece,
  }) async {
    // UI'dan gelen adetler, veri modeli gereği `pack_qty` / `box_qty`
    // alanlarına INT olarak yazılır.
    //
    // pack_qty: 1 paket = pack_qty * temel birim (ör. adet)
    // box_qty: 1 koli  = box_qty * temel birim (ör. adet)
    // carton_qty: ileride ek seviye için ayrılmıştır, şimdilik her zaman NULL.
    //
    // *_contains_piece eski şema alanları bu akışta hiç gönderilmez.
    final payload = <String, dynamic>{
      'stock_id': stockId,
      'pack_qty': packContainsPiece,
      'box_qty': caseContainsPiece,
      'carton_qty': null,
    };
    print('STOCK_UNITS PAYLOAD => $payload');

    await _client.from('stock_units').upsert(
      payload,
      onConflict: 'stock_id',
    );
  }

  /// Uploads stock image to `stock-images` bucket and returns the stored path.
  Future<String> uploadStockImage({
    required String stockId,
    required List<int> bytes,
    required String fileExt,
  }) async {
    final safeExt = fileExt.isEmpty ? 'jpg' : fileExt.toLowerCase();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = 'stocks/$stockId/$timestamp.$safeExt';

    final data = Uint8List.fromList(bytes);

    await _client.storage.from(kStockImagesBucketId).uploadBinary(
          path,
          data,
        );

    return path;
  }

  Future<void> updateStockImagePath({
    required String stockId,
    required String imagePath,
  }) async {
    await _client
        .from('stocks')
      .update({'image_path': imagePath})
      .eq('id', stockId);
  }

  /// Fetch stocks by their `code` values using a single IN query.
  ///
  /// Incoming codes are trimmed and empty codes are ignored. The result
  /// may contain fewer items than requested if some codes do not exist.
  Future<List<Stock>> fetchStocksByCodes(List<String> codes) async {
    if (codes.isEmpty) {
      return const [];
    }

    final cleaned = codes
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList(growable: false);

    if (cleaned.isEmpty) {
      return const [];
    }

    final q = _client.from('stocks').select();
    final q2 = _applyInList(q, 'code', cleaned);
    final data = await q2;

    return (data as List<dynamic>)
        .map((e) => Stock.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetch all stocks for CSV export.
  Future<List<StockExportRow>> fetchAllStocksForExport() async {
    // Fetch all stocks first.
    final data = await _client.from('stocks').select().order('name');

    final stocks = (data as List<dynamic>)
        .map((e) => Stock.fromMap(e as Map<String, dynamic>))
        .toList();

    // Collect stock IDs for unit lookup.
    final ids = stocks
        .map((s) => s.id)
        .whereType<String>()
        .toList(growable: false);

    final Map<String, (int?, int?)> unitsByStockId = {};

    if (ids.isNotEmpty) {
    final q = _client
        .from('stock_units')
      .select('stock_id, pack_qty, box_qty');
    final q2 = _applyInList(q, 'stock_id', ids);
    final unitData = await q2;

      for (final row in unitData as List<dynamic>) {
        final map = row as Map<String, dynamic>;
        final stockId = map['stock_id'] as String?;
        if (stockId == null) continue;
        final pack = map['pack_qty'] as int?;
        final kase = map['box_qty'] as int?;
        unitsByStockId[stockId] = (pack, kase);
      }
    }

    return stocks
        .map((stock) {
          final id = stock.id;
          final unit = id != null ? unitsByStockId[id] : null;
          final packQty = unit?.$1;
          final boxQty = unit?.$2;
          return StockExportRow(
            stock: stock,
            packQty: packQty,
            boxQty: boxQty,
          );
        })
        .toList(growable: false);
  }

  /// Import stocks from pre-parsed CSV rows.
  ///
  /// Each row is expected to contain the columns defined in [stockCsvHeaders].
  /// Validation is applied before any database writes. Only valid rows are
  /// upserted based on the `code` column. After upserts, stocks that are not
  /// present in the CSV are deleted (master sync by `code`).
  Future<ImportResult> importStocksFromCsvRows(
    List<Map<String, String>> rows,
  ) async {
    if (rows.isEmpty) {
      return const ImportResult(
        insertedCount: 0,
        updatedCount: 0,
        deletedCount: 0,
        notDeletedCount: 0,
        skippedCount: 0,
        errorRows: [],
      );
    }

    final List<ImportErrorRow> errorRows = [];
    final Map<String, _ImportCandidate> candidatesByCode = {};
    var skipped = 0;

    int csvRowNumber = 2; // assume header is line 1
    for (final raw in rows) {
      // Eşleştirme anahtarı: kod (trim + uppercase normalize).
      final rawCode =
          nullIfEmpty(raw['code'] ?? raw['kod'])?.trim().toUpperCase();
      final rawName = nullIfEmpty(raw['name'] ?? raw['ad']);
      final code = rawCode;
      final name = rawName;

      if (code == null || name == null) {
        errorRows.add(
          ImportErrorRow(
            rowNumber: csvRowNumber,
            message: 'code ve name zorunludur.',
            values: raw,
          ),
        );
        skipped++;
        csvRowNumber++;
        continue;
      }

      if (candidatesByCode.containsKey(code)) {
        errorRows.add(
          ImportErrorRow(
            rowNumber: csvRowNumber,
            message: 'Aynı code değeri CSV içinde birden fazla satırda bulunuyor.',
            values: raw,
          ),
        );
        skipped++;
        csvRowNumber++;
        continue;
      }

        // Optional fields; only touch a column if it exists in the CSV header.
        final bool hasBrand = raw.containsKey('brand') || raw.containsKey('marka');
        final bool hasTaxRate = raw.containsKey('tax_rate') || raw.containsKey('kdv_oran');
        final bool hasSalePrice1 =
          raw.containsKey('sale_price_1') || raw.containsKey('satis_fiyat1');
        final bool hasSalePrice2 =
          raw.containsKey('sale_price_2') || raw.containsKey('satis_fiyat2');
        final bool hasSalePrice3 =
          raw.containsKey('sale_price_3') || raw.containsKey('satis_fiyat3');
        final bool hasSalePrice4 =
          raw.containsKey('sale_price_4') || raw.containsKey('satis_fiyat4');
        final bool hasBarcode = raw.containsKey('barcode') || raw.containsKey('barkod');
        final bool hasPackBarcode =
          raw.containsKey('pack_barcode') || raw.containsKey('paket_barkod');
        final bool hasBoxBarcode =
          raw.containsKey('box_barcode') || raw.containsKey('koli_barkod');
        final bool hasIsActive = raw.containsKey('is_active') || raw.containsKey('aktif');
        final bool hasImagePath =
          raw.containsKey('image_path') || raw.containsKey('resim_yolu');
          final bool hasGroupName =
            raw.containsKey('group_name') || raw.containsKey('grup_ad');
          final bool hasSubgroupName =
            raw.containsKey('subgroup_name') || raw.containsKey('ara_grup_ad');
          final bool hasSubsubgroupName =
            raw.containsKey('subsubgroup_name') || raw.containsKey('alt_grup_ad');

      // pack_qty / box_qty are optional ints
      int? packQty;
      int? boxQty;
        final packQtyStr =
          nullIfEmpty(raw['pack_qty'] ?? raw['paket_ici_adet']);
        final boxQtyStr = nullIfEmpty(raw['box_qty'] ?? raw['koli_ici_adet']);
      if (packQtyStr != null) {
        packQty = int.tryParse(packQtyStr);
        if (packQty == null || packQty < 1) {
          errorRows.add(
            ImportErrorRow(
              rowNumber: csvRowNumber,
              message: 'pack_qty (paket_ici_adet) >= 1 olmalıdır veya boş bırakılmalıdır.',
              values: raw,
            ),
          );
          skipped++;
          csvRowNumber++;
          continue;
        }
      }
      if (boxQtyStr != null) {
        boxQty = int.tryParse(boxQtyStr);
        if (boxQty == null || boxQty < 1) {
          errorRows.add(
            ImportErrorRow(
              rowNumber: csvRowNumber,
              message: 'box_qty (koli_ici_adet) >= 1 olmalıdır veya boş bırakılmalıdır.',
              values: raw,
            ),
          );
          skipped++;
          csvRowNumber++;
          continue;
        }
      }

      final stockPayload = <String, dynamic>{
        'code': code,
        'name': name,
      };

      if (hasBrand) {
        stockPayload['brand'] =
            nullIfEmpty(raw['brand'] ?? raw['marka']);
      }
      if (hasTaxRate) {
        final taxRateParsed = parseNum(raw['tax_rate'] ?? raw['kdv_oran']);
        stockPayload['tax_rate'] = taxRateParsed.value;
      }
      if (hasSalePrice1) {
        final salePrice1Parsed =
            parseNum(raw['sale_price_1'] ?? raw['satis_fiyat1']);
        stockPayload['sale_price_1'] = salePrice1Parsed.value;
      }
      if (hasSalePrice2) {
        final salePrice2Parsed =
            parseNum(raw['sale_price_2'] ?? raw['satis_fiyat2']);
        stockPayload['sale_price_2'] = salePrice2Parsed.value;
      }
      if (hasSalePrice3) {
        final salePrice3Parsed =
            parseNum(raw['sale_price_3'] ?? raw['satis_fiyat3']);
        stockPayload['sale_price_3'] = salePrice3Parsed.value;
      }
      if (hasSalePrice4) {
        final salePrice4Parsed =
            parseNum(raw['sale_price_4'] ?? raw['satis_fiyat4']);
        stockPayload['sale_price_4'] = salePrice4Parsed.value;
      }
      if (hasBarcode) {
        stockPayload['barcode'] =
            nullIfEmpty(raw['barcode'] ?? raw['barkod']);
      }
      if (hasPackBarcode) {
        stockPayload['pack_barcode'] =
            nullIfEmpty(raw['pack_barcode'] ?? raw['paket_barkod']);
      }
      if (hasBoxBarcode) {
        stockPayload['box_barcode'] =
            nullIfEmpty(raw['box_barcode'] ?? raw['koli_barkod']);
      }
      if (hasIsActive) {
        final isActiveParsed =
            parseBoolFlexible(raw['is_active'] ?? raw['aktif']);
        stockPayload['is_active'] = isActiveParsed ?? true;
      }
      if (hasImagePath) {
        stockPayload['image_path'] =
            nullIfEmpty(raw['image_path'] ?? raw['resim_yolu']);
      }

      String? normalizeGroup(String? value) {
        if (value == null) return null;
        final trimmed = value.trim();
        if (trimmed.isEmpty) return null;
        return trimmed.replaceAll(RegExp(r'\s+'), ' ');
      }

      if (hasGroupName) {
        final rawGroup = raw['group_name'] ?? raw['grup_ad'];
        stockPayload['group_name'] = normalizeGroup(rawGroup);
      }
      if (hasSubgroupName) {
        final rawSub = raw['subgroup_name'] ?? raw['ara_grup_ad'];
        stockPayload['subgroup_name'] = normalizeGroup(rawSub);
      }
      if (hasSubsubgroupName) {
        final rawSubsub = raw['subsubgroup_name'] ?? raw['alt_grup_ad'];
        stockPayload['subsubgroup_name'] = normalizeGroup(rawSubsub);
      }

      candidatesByCode[code] = _ImportCandidate(
        code: code,
        stockPayload: stockPayload,
        packQty: packQty,
        boxQty: boxQty,
      );

      csvRowNumber++;
    }

    if (candidatesByCode.isEmpty) {
      return ImportResult(
        insertedCount: 0,
        updatedCount: 0,
        deletedCount: 0,
        notDeletedCount: 0,
        skippedCount: skipped,
        errorRows: errorRows,
      );
    }

    final codes = candidatesByCode.keys.toList();

    // Determine which codes already exist (for insert/update counts) and also
    // load all existing stock codes for delete (master sync).
    final existingForCandidatesQuery = _client
        .from('stocks')
        .select('code')
        .inFilter('code', codes);
    final existingForCandidatesData = await existingForCandidatesQuery;

    final existingCodesForCandidates = <String>{};
    for (final row in existingForCandidatesData as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      final c = map['code'] as String?;
      if (c != null) existingCodesForCandidates.add(c);
    }

    final existingCount = existingCodesForCandidates.length;
    final totalValid = candidatesByCode.length;
    final insertedCount = totalValid - existingCount;
    final updatedCount = existingCount;

    // Insert / update one by one so that we only touch columns that are
    // actually present in the CSV header (patch semantics for existing rows).
    final unitsToUpsert = <Map<String, dynamic>>[];

    for (final candidate in candidatesByCode.values) {
      final code = candidate.code;
      final payload = candidate.stockPayload;

      dynamic upsertResponse;
      if (existingCodesForCandidates.contains(code)) {
        upsertResponse = await _client
            .from('stocks')
            .update(payload)
            .eq('code', code)
            .select('id, code');
      } else {
        upsertResponse = await _client
            .from('stocks')
            .insert(payload)
            .select('id, code');
      }

      final rowsData = upsertResponse is List<dynamic>
          ? upsertResponse
          : (upsertResponse as dynamic).data as List<dynamic>?;
      if (rowsData == null || rowsData.isEmpty) {
        continue;
      }
      final map = rowsData.first as Map<String, dynamic>;
      final id = map['id'] as String?;
      if (id == null) {
        continue;
      }

      final hasPack = (candidate.packQty ?? 0) > 0;
      final hasBox = (candidate.boxQty ?? 0) > 0;
      if (!hasPack && !hasBox) {
        continue;
      }

      unitsToUpsert.add({
        'stock_id': id,
        'pack_qty': hasPack ? candidate.packQty : null,
        'box_qty': hasBox ? candidate.boxQty : null,
      });
    }

    if (unitsToUpsert.isNotEmpty) {
      await _client
          .from('stock_units')
          .upsert(unitsToUpsert, onConflict: 'stock_id');
    }

    // Determine which existing stocks are not present in the CSV and should
    // be deleted as part of the master sync.
    final allExistingQuery = _client.from('stocks').select('id, code, name');
    final allExistingData = await allExistingQuery;

    final allExistingCodes = <String>{};
    final existingByCode = <String, Map<String, dynamic>>{};
    for (final row in allExistingData as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      final c = map['code'] as String?;
      if (c != null) {
        allExistingCodes.add(c);
        existingByCode[c] = map;
      }
    }

    final csvCodes = codes.toSet();
    final codesToDelete = allExistingCodes.difference(csvCodes).toList();

    var deletedCount = 0;
    var notDeletedCount = 0;
    final notDeletedStocks = <NotDeletedStock>[];

    for (final code in codesToDelete) {
      final existing = existingByCode[code];
      final name = existing != null ? existing['name'] as String? : null;
      try {
        await _client.from('stocks').delete().eq('code', code);
        deletedCount++;
      } catch (e) {
        notDeletedCount++;
        notDeletedStocks.add(
          NotDeletedStock(
            code: code,
            name: name,
            reason: e.toString(),
          ),
        );
      }
    }

    return ImportResult(
      insertedCount: insertedCount,
      updatedCount: updatedCount,
      deletedCount: deletedCount,
      notDeletedCount: notDeletedCount,
      skippedCount: skipped,
      errorRows: errorRows,
      notDeletedStocks: notDeletedStocks,
    );
  }
}

final stockRepository = StockRepository(supabaseClient);

class _ImportCandidate {
  _ImportCandidate({
    required this.code,
    required this.stockPayload,
    required this.packQty,
    required this.boxQty,
  });

  final String code;
  final Map<String, dynamic> stockPayload;
  final int? packQty;
  final int? boxQty;
}

/// Helper to apply an IN filter using Supabase's `inFilter` helper.
PostgrestFilterBuilder<T> _applyInList<T>(
  PostgrestFilterBuilder<T> query,
  String column,
  List<String> values,
) {
  if (values.isEmpty) {
    return query;
  }

  final cleaned = values
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList(growable: false);
  if (cleaned.isEmpty) {
    return query;
  }

	return query.inFilter(column, cleaned);
}
