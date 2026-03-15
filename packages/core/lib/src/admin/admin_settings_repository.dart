import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_client.dart';
import 'models/admin_numbering_settings.dart';
import 'models/admin_company_settings.dart';
import 'models/admin_system_settings.dart';

class AdminSettingsRepository {
  AdminSettingsRepository(this._client);

  final SupabaseClient _client;

  Future<AdminNumberingSettings> fetchNumberingSettings() async {
    try {
      final dynamic data = await _client
          .from('settings_numbering')
          .select(
            'key,prefix,padding,next_number,include_year,separator,reset_policy',
          );

      final rows = (data as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (rows.isEmpty) {
        return AdminNumberingSettings.defaults();
      }

      AdminNumberingConfig? orderConfig;
      AdminNumberingConfig? invoiceConfig;

      for (final row in rows) {
        final key = row['key'] as String?;
        if (key == null) continue;
        final config = AdminNumberingConfig.fromMap(row);
        if (key == 'order') {
          orderConfig = config;
        } else if (key == 'invoice') {
          invoiceConfig = config;
        }
      }

      final defaults = AdminNumberingSettings.defaults();

      return AdminNumberingSettings(
        order: orderConfig ?? defaults.order,
        invoice: invoiceConfig ?? defaults.invoice,
      );
    } on PostgrestException {
      // Örneğin tablo henüz yoksa (PGRST205) default ayarlara düş.
      return AdminNumberingSettings.defaults();
    } catch (_) {
      // Diğer hatalarda da ilk aşamada default ayarlara dön.
      return AdminNumberingSettings.defaults();
    }
  }

  Future<void> updateNumberingConfig(AdminNumberingConfig config) async {
    // Supabase tablo yapısı: settings_numbering (key, prefix, padding, next_number, include_year, separator, reset_policy)
    await _client.from('settings_numbering').upsert(
          config.toMap(),
        );
  }

  Future<AdminCompanySettings> fetchCompanySettings() async {
    try {
      final dynamic data = await _client
          .from('settings_company')
          .select(
            'company_title,tax_office,tax_no,phone,email,website,address,pdf_footer_note,currency,show_vat_on_totals,show_signature_area',
          )
          .maybeSingle();

      if (data is Map<String, dynamic>) {
        return AdminCompanySettings.fromMap(data);
      }

      return AdminCompanySettings.defaults();
    } on PostgrestException {
      return AdminCompanySettings.defaults();
    } catch (_) {
      return AdminCompanySettings.defaults();
    }
  }

  Future<void> updateCompanySettings(AdminCompanySettings settings) async {
    try {
      await _client.from('settings_company').upsert(
            settings.toMap(),
          );
    } catch (_) {
      // İlk aşamada hata detayını yut, UI defaultlarla çalışmaya devam etsin.
    }
  }

  Future<AdminSystemSettings> fetchSystemSettings() async {
    try {
      final dynamic data = await _client
          .from('settings_system')
          .select('maintenance_mode')
          .maybeSingle();

      if (data is Map<String, dynamic>) {
        return AdminSystemSettings.fromMap(data);
      }

      return AdminSystemSettings.defaults();
    } on PostgrestException {
      return AdminSystemSettings.defaults();
    } catch (_) {
      return AdminSystemSettings.defaults();
    }
  }

  Future<void> updateSystemSettings(AdminSystemSettings settings) async {
    try {
      await _client.from('settings_system').upsert(
            settings.toMap(),
          );
    } catch (_) {
      // Şimdilik Supabase hazır olmasa da ekran çalışsın.
    }
  }
}

final adminSettingsRepository = AdminSettingsRepository(supabaseClient);
