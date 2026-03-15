class Customer {
  const Customer({
    required this.id,
    this.fullName,
    this.tradeTitle,
    required this.code,
    this.customerType,
    this.taxOffice,
    this.taxNo,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.addressDetail,
    this.city,
    this.district,
    this.notes,
    this.tags = const <String>[],
    this.limitAmount,
    this.priceListNo,
    this.dueDays,
    this.riskNote,
    this.groupName,
    this.subGroupName,
    this.subSubGroupName,
    this.openingBalance,
    this.openingBalanceType,
    this.warnOnLimitExceeded,
    this.marketerName,
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String? fullName;
  final String? tradeTitle;
  final String code;
  final String? customerType;
  final String? taxOffice;
  final String? taxNo;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? addressDetail;
  final String? city;
  final String? district;
  final String? notes;
  final List<String> tags;
  final double? limitAmount;
  final int? priceListNo;
  final int? dueDays;
  final String? riskNote;
  final String? groupName;
  final String? subGroupName;
  final String? subSubGroupName;
  final double? openingBalance;
  final String? openingBalanceType;
  final bool? warnOnLimitExceeded;
  final String? marketerName;
  final bool isActive;
  final DateTime? createdAt;

  /// Kullanım kolaylığı için görüntü adını üretir.
  /// Öncelik sırası: ticari unvan > tam ad > kod.
  String get displayName {
    final trade = tradeTitle?.trim();
    if (trade != null && trade.isNotEmpty) return trade;
    final full = fullName?.trim();
    if (full != null && full.isNotEmpty) return full;
    return code;
  }

  /// Geriye dönük uyumluluk için `name` alanı gibi davranır.
  String get name => displayName;

  factory Customer.fromMap(Map<String, dynamic> map) {
    final fullName = map['full_name'] as String?;
    final tradeTitle = (map['trade_title'] as String?) ??
      (map['trade_name'] as String?);
    final code = (map['customer_code'] as String?) ??
      (map['code'] as String?) ??
      '';

    final city = (map['city'] as String?) ??
      (map['address_city'] as String?);
    final district = (map['district'] as String?) ??
      (map['address_district'] as String?);
    final addressDetail = (map['address_detail'] as String?) ??
      (map['address_line'] as String?);
    final address = (map['address'] as String?) ??
      addressDetail;
    final priceListNo = (map['price_tier'] as int?) ??
      (map['price_list_no'] as int?) ??
      (map['priceListNo'] as int?);

    return Customer(
      id: (map['customer_id'] ?? map['id']) as String,
      fullName: fullName,
      tradeTitle: tradeTitle,
      code: code,
      customerType: map['customer_type'] as String?,
      taxOffice: map['tax_office'] as String?,
      taxNo: map['tax_no'] as String?,
      contactName: map['contact_name'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      address: address,
        addressDetail: addressDetail,
      city: city,
      district: district,
      notes: map['notes'] as String?,
      tags: _parseTags(map['tags']),
        limitAmount: (map['limit_amount'] as num?)?.toDouble() ??
          double.tryParse('${map['limit_amount']}'),
      priceListNo: priceListNo,
      dueDays: map['due_days'] as int?,
      riskNote: map['risk_note'] as String?,
      groupName: map['group_name'] as String?,
      subGroupName: map['sub_group'] as String?,
      subSubGroupName: map['alt_group'] as String?,
        openingBalance: (map['opening_balance'] as num?)?.toDouble() ??
          double.tryParse('${map['opening_balance']}'),
      openingBalanceType: map['opening_balance_type'] as String?,
      warnOnLimitExceeded: map['warn_on_limit_exceeded'] as bool?,
      marketerName: map['marketer_name'] as String?,
      isActive: (map['is_active'] as bool?) ?? true,
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

/// Ortak müşteri sorguları için kullanılan kolon listesi.
/// Tüm SELECT ifadeleri bu sabiti kullanmalıdır ve v_customers görünümü ile
/// birebir uyumludur.
const String customerSelectColumns =
  'id, customer_code, full_name, trade_title, '
  'phone, email, address, is_active';

List<String> _parseTags(dynamic raw) {
  if (raw == null) return const <String>[];
  if (raw is List) {
    return raw
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  // Fallback: comma-separated string
  return raw
      .toString()
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

DateTime? _parseDateTime(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  return null;
}
