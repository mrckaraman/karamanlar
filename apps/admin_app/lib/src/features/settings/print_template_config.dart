import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A5 klasik Fatura / Sipariş şablonu için konfigürasyon.
class PrintTemplateConfig {
  const PrintTemplateConfig({
    required this.key,
    required this.addressLine,
    required this.marginMm,
    required this.fontSizeBase,
    required this.showPrevBalance,
    required this.showNewBalance,
    required this.colProductFlex,
    required this.colQtyFlex,
    required this.colUnitFlex,
    required this.colUnitPriceFlex,
    required this.colTotalFlex,
  });

  // Supabase / local storage config anahtarı
  // 
  // Örn:
  //  - print_template_config.invoice_a5
  //  - print_template_config.order_a5
  final String key;
  final String addressLine;
  final double marginMm;
  final double fontSizeBase;
  final bool showPrevBalance;
  final bool showNewBalance;
  final double colProductFlex;
  final double colQtyFlex;
  final double colUnitFlex;
  final double colUnitPriceFlex;
  final double colTotalFlex;

  factory PrintTemplateConfig.invoiceDefaults() => const PrintTemplateConfig(
        key: PrintTemplateConfigRepository.invoiceKey,
        addressLine: '',
        marginMm: 12,
        fontSizeBase: 8.5,
        showPrevBalance: true,
        showNewBalance: true,
        colProductFlex: 3,
        colQtyFlex: 1,
        colUnitFlex: 1.1,
        colUnitPriceFlex: 1.5,
        colTotalFlex: 1.5,
      );

  factory PrintTemplateConfig.orderDefaults() => const PrintTemplateConfig(
        key: PrintTemplateConfigRepository.orderKey,
        addressLine: '',
        marginMm: 12,
        fontSizeBase: 8.5,
        showPrevBalance: true,
        showNewBalance: true,
        colProductFlex: 3,
        colQtyFlex: 1,
        colUnitFlex: 1.1,
        colUnitPriceFlex: 1.5,
        colTotalFlex: 1.5,
      );

  PrintTemplateConfig copyWith({
    String? addressLine,
    double? marginMm,
    double? fontSizeBase,
    bool? showPrevBalance,
    bool? showNewBalance,
    double? colProductFlex,
    double? colQtyFlex,
    double? colUnitFlex,
    double? colUnitPriceFlex,
    double? colTotalFlex,
  }) {
    return PrintTemplateConfig(
      key: key,
      addressLine: addressLine ?? this.addressLine,
      marginMm: marginMm ?? this.marginMm,
      fontSizeBase: fontSizeBase ?? this.fontSizeBase,
      showPrevBalance: showPrevBalance ?? this.showPrevBalance,
      showNewBalance: showNewBalance ?? this.showNewBalance,
      colProductFlex: colProductFlex ?? this.colProductFlex,
      colQtyFlex: colQtyFlex ?? this.colQtyFlex,
      colUnitFlex: colUnitFlex ?? this.colUnitFlex,
      colUnitPriceFlex: colUnitPriceFlex ?? this.colUnitPriceFlex,
      colTotalFlex: colTotalFlex ?? this.colTotalFlex,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'addressLine': addressLine,
      'marginMm': marginMm,
      'fontSizeBase': fontSizeBase,
      'showPrevBalance': showPrevBalance,
      'showNewBalance': showNewBalance,
      'colProductFlex': colProductFlex,
      'colQtyFlex': colQtyFlex,
      'colUnitFlex': colUnitFlex,
      'colUnitPriceFlex': colUnitPriceFlex,
      'colTotalFlex': colTotalFlex,
    };
  }

  factory PrintTemplateConfig.fromMap(String key, Map<String, dynamic> map) {
    double toDouble(dynamic v, double fallback) {
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v.replaceAll(',', '.'));
        return parsed ?? fallback;
      }
      return fallback;
    }

    return PrintTemplateConfig(
      key: key,
      addressLine: (map['addressLine'] as String?) ?? '',
      marginMm: toDouble(map['marginMm'], 12),
      fontSizeBase: toDouble(map['fontSizeBase'], 8.5),
      showPrevBalance: (map['showPrevBalance'] as bool?) ?? true,
      showNewBalance: (map['showNewBalance'] as bool?) ?? true,
      colProductFlex: toDouble(map['colProductFlex'], 3),
      colQtyFlex: toDouble(map['colQtyFlex'], 1),
      colUnitFlex: toDouble(map['colUnitFlex'], 1.1),
      colUnitPriceFlex: toDouble(map['colUnitPriceFlex'], 1.5),
      colTotalFlex: toDouble(map['colTotalFlex'], 1.5),
    );
  }
}

/// Şablon konfigürasyonlarını JSON key-value olarak saklar.
///
/// Öncelik sırası:
/// 1) Supabase `app_settings` tablosu (varsa)
/// 2) Lokal shared_preferences
class PrintTemplateConfigRepository {
  const PrintTemplateConfigRepository();

  // NOT: Template seçimi için ayrı bir key kullanılmalıdır:
  //  - print_template.invoice_a5 = 'a5_classic' vb.
  // Bu repository yalnızca konfig JSON'unu saklar:
  //  - print_template_config.invoice_a5 = { ... }
  //  - print_template_config.order_a5   = { ... }
  static const invoiceKey = 'print_template_config.invoice_a5';
  static const orderKey = 'print_template_config.order_a5';

  SupabaseClient get _client => supabaseClient;

  Future<PrintTemplateConfig> fetch(String key) async {
    // 1) Supabase dene
    try {
      final data = await _client
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();

      if (data is Map<String, dynamic> && data['value'] != null) {
        final raw = data['value'];
        final map = _parseConfigMap(key, raw);
        if (map != null) {
          return PrintTemplateConfig.fromMap(key, map);
        }
      }
    } on PostgrestException {
      // Tablo / kolon yoksa sessizce local fallback'e geç.
    } catch (_) {
      // Diğer hatalarda da local fallback kullanılacak.
    }

    // 2) Lokal shared_preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final map = _parseConfigMap(key, jsonStr);
        if (map != null) {
          return PrintTemplateConfig.fromMap(key, map);
        }
      }
    } catch (_) {
      // ignore
    }

    // 3) Varsayılanlar
    return key == invoiceKey
        ? PrintTemplateConfig.invoiceDefaults()
        : PrintTemplateConfig.orderDefaults();
  }

  Future<void> save(PrintTemplateConfig config) async {
    final map = config.toMap();

    // 1) Lokal shared_preferences'e yaz
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(config.key, jsonEncode(map));
    } catch (_) {
      // ignore
    }

    // 2) Supabase app_settings tablosuna upsert (varsa)
    try {
      await _client.from('app_settings').upsert({
        'key': config.key,
        'value': map,
      });
    } catch (_) {
      // Tablo henüz yoksa uygulama defaultlarla çalışmaya devam eder.
    }
  }

  /// Çeşitli kaynaklardan (Supabase jsonb, text, shared_preferences string)
  /// gelen değeri güvenli şekilde Map'e çevirir.
  ///
  /// Hata durumunda null döner, çağıran taraf varsayılan konfige düşer.
  Map<String, dynamic>? _parseConfigMap(String key, dynamic raw) {
    try {
      if (raw is Map<String, dynamic>) {
        return raw;
      }
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
      if (raw is String) {
        if (raw.isEmpty) return null;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('print_template_config parse error for $key: $e');
        debugPrint('$st');
      }
    }
    return null;
  }
}

const printTemplateConfigRepository = PrintTemplateConfigRepository();
