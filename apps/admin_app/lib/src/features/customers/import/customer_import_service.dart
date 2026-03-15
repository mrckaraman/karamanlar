import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_import_models.dart';
import 'customer_excel_schema.dart';

class CustomerImportService {
  CustomerImportService(this._client);

  final SupabaseClient _client;

  Map<String, dynamic> _buildRowPayload(CustomerImportRow row) {
    final v = row.values;
    final payload = <String, dynamic>{};

    void put(String key, String fieldKey) {
      final raw = (v[fieldKey] ?? '').toString().trim();
      if (raw.isEmpty) return;
      payload[key] = raw;
    }

    put('trade_title', CustomerExcelFields.tradeTitle);
    put('full_name', CustomerExcelFields.fullName);
    put('customer_code', CustomerExcelFields.customerCode);
    put('customer_type', CustomerExcelFields.customerType);
    put('phone', CustomerExcelFields.phone);
    put('email', CustomerExcelFields.email);
    put('tax_office', CustomerExcelFields.taxOffice);
    put('tax_no', CustomerExcelFields.taxNo);
    // Adres hem customers.address hem de customer_details.address_detail icin kullaniliyor.
    put('address', CustomerExcelFields.address);
    put('city', CustomerExcelFields.city);
    put('district', CustomerExcelFields.district);
    put('limit_amount', CustomerExcelFields.limitAmount);
    put('warn_on_limit_exceeded', CustomerExcelFields.warnOnLimitExceeded);
    put('risk_note', CustomerExcelFields.riskNote);
    // Pazarlamaci adi soyadi -> marketer_name
    put('marketer_name', CustomerExcelFields.salesRepName);
    // Gruplama alanlari
    put('group_name', CustomerExcelFields.group);
    put('sub_group', CustomerExcelFields.subGroup);
    put('alt_group', CustomerExcelFields.subSubGroup);
    // Vade ve fiyat listesi (price_list_name -> price_tier)
    put('due_days', CustomerExcelFields.dueDays);
    put('price_tier', CustomerExcelFields.priceListName);
    // Aktiflik ve etiketler
    put('is_active', CustomerExcelFields.isActive);
    put('tags_csv', CustomerExcelFields.tagsCsv);

    // Cari kodu bos ise deterministic bir sekilde uret.
    final existingCode = (payload['customer_code'] ?? '').toString().trim();
    if (existingCode.isEmpty) {
      String? generated;

      // 1) Vergi numarasindan turet: C-<tax_no_digits>
      final taxRaw = (payload['tax_no'] ?? '').toString();
      final taxDigits = taxRaw.replaceAll(RegExp(r'[^0-9]'), '');
      if (taxDigits.isNotEmpty) {
        generated = 'C-$taxDigits';
      } else {
        // 2) Telefon numarasindan turet: C-<son10_hane>
        final phoneRaw = (payload['phone'] ?? '').toString();
        final phoneDigits = phoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
        if (phoneDigits.isNotEmpty) {
          final last10 = phoneDigits.length > 10
              ? phoneDigits.substring(phoneDigits.length - 10)
              : phoneDigits;
          generated = 'C-$last10';
        } else {
          // 3) Satir index'inden turet: C-000001 gibi
          final indexPadded = row.index.toString().padLeft(6, '0');
          generated = 'C-$indexPadded';
        }
      }

      payload['customer_code'] = generated;
    }

    return payload;
  }

  Future<Map<String, dynamic>> validate(
    List<CustomerImportRow> rows,
    String fileName,
    DuplicateStrategy strategy,
  ) async {
    final strategyKey = switch (strategy) {
      DuplicateStrategy.byCustomerCode => 'by_customer_code',
      DuplicateStrategy.byTaxNo => 'by_taxno',
      DuplicateStrategy.insertOnly => 'insert_only',
    };

    final payload = <String, dynamic>{
      'file_name': fileName,
      'rows': rows.map(_buildRowPayload).toList(),
      'strategy': strategyKey,
    };
    if (kDebugMode) {
      debugPrint(
        '[import] validate mode=validate strategy=$strategyKey rows=${rows.length}',
      );
    }
    if (rows.isNotEmpty) {
      final sample = _buildRowPayload(rows.first);
      final maskedSample = Map<String, dynamic>.from(sample);
      if (maskedSample['phone'] is String &&
          (maskedSample['phone'] as String).isNotEmpty) {
        maskedSample['phone'] = '***';
      }
      if (maskedSample['email'] is String &&
          (maskedSample['email'] as String).isNotEmpty) {
        maskedSample['email'] = '***';
      }
      if (kDebugMode) {
        debugPrint(
          '[import] validate firstRow keys=${sample.keys.toList()} sample=$maskedSample',
        );
      }
    }

    final dynamic result = await _client.rpc(
      'rpc_import_customers',
      params: <String, dynamic>{
        'payload': payload,
        'mode': 'validate',
      },
    );

    final map = (result as Map).cast<String, dynamic>();
    if (kDebugMode) {
      debugPrint('[import] validate result keys=${map.keys.toList()}');
    }
    return map;
  }

  Future<Map<String, dynamic>> apply(
    List<CustomerImportRow> rows,
    String fileName,
    DuplicateStrategy strategy,
  ) async {
    final mode = switch (strategy) {
      DuplicateStrategy.byCustomerCode => 'upsert_by_customer_code',
      DuplicateStrategy.byTaxNo => 'upsert_by_taxno',
      DuplicateStrategy.insertOnly => 'insert_only',
    };

    final payload = <String, dynamic>{
      'file_name': fileName,
      'rows': rows.map(_buildRowPayload).toList(),
    };

    if (kDebugMode) {
      debugPrint('[import] apply mode=$mode rows=${rows.length}');
    }
    if (rows.isNotEmpty) {
      final sample = _buildRowPayload(rows.first);
      final maskedSample = Map<String, dynamic>.from(sample);
      if (maskedSample['phone'] is String &&
          (maskedSample['phone'] as String).isNotEmpty) {
        maskedSample['phone'] = '***';
      }
      if (maskedSample['email'] is String &&
          (maskedSample['email'] as String).isNotEmpty) {
        maskedSample['email'] = '***';
      }
      if (kDebugMode) {
        debugPrint(
          '[import] apply firstRow keys=${sample.keys.toList()} sample=$maskedSample',
        );
      }
    }

    final dynamic result = await _client.rpc(
      'rpc_import_customers',
      params: <String, dynamic>{
        'payload': payload,
        'mode': mode,
      },
    );

    final map = (result as Map).cast<String, dynamic>();
    if (kDebugMode) {
      debugPrint(
        '[import] apply rpc response keys=${map.keys.toList()}',
      );
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> fetchErrorItems(String batchId) async {
    final dynamic data = await _client
        .from('customer_import_items')
        .select('row_index,status,message,raw')
        .eq('batch_id', batchId)
        .order('row_index');

    return (data as List)
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }
}

CustomerImportService createCustomerImportService() {
  return CustomerImportService(supabaseClient);
}
