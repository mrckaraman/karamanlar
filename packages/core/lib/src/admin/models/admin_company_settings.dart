enum AdminCompanyCurrency { tryTr, usd, eur }

extension AdminCompanyCurrencyX on AdminCompanyCurrency {
  String get code {
    switch (this) {
      case AdminCompanyCurrency.tryTr:
        return 'TRY';
      case AdminCompanyCurrency.usd:
        return 'USD';
      case AdminCompanyCurrency.eur:
        return 'EUR';
    }
  }

  static AdminCompanyCurrency fromCode(String? value) {
    switch (value?.toUpperCase()) {
      case 'USD':
        return AdminCompanyCurrency.usd;
      case 'EUR':
        return AdminCompanyCurrency.eur;
      case 'TRY':
      default:
        return AdminCompanyCurrency.tryTr;
    }
  }
}

class AdminCompanySettings {
  const AdminCompanySettings({
    required this.companyTitle,
    required this.taxOffice,
    required this.taxNo,
    required this.phone,
    required this.email,
    required this.website,
    required this.address,
    required this.pdfFooterNote,
    required this.currency,
    required this.showVatOnTotals,
    required this.showSignatureArea,
  });

  final String companyTitle;
  final String taxOffice;
  final String taxNo;
  final String phone;
  final String email;
  final String website;
  final String address;
  final String pdfFooterNote;
  final AdminCompanyCurrency currency;
  final bool showVatOnTotals;
  final bool showSignatureArea;

  factory AdminCompanySettings.defaults() {
    return const AdminCompanySettings(
      companyTitle: '',
      taxOffice: '',
      taxNo: '',
      phone: '',
      email: '',
      website: '',
      address: '',
      pdfFooterNote: '',
      currency: AdminCompanyCurrency.tryTr,
      showVatOnTotals: true,
      showSignatureArea: true,
    );
  }

  AdminCompanySettings copyWith({
    String? companyTitle,
    String? taxOffice,
    String? taxNo,
    String? phone,
    String? email,
    String? website,
    String? address,
    String? pdfFooterNote,
    AdminCompanyCurrency? currency,
    bool? showVatOnTotals,
    bool? showSignatureArea,
  }) {
    return AdminCompanySettings(
      companyTitle: companyTitle ?? this.companyTitle,
      taxOffice: taxOffice ?? this.taxOffice,
      taxNo: taxNo ?? this.taxNo,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      address: address ?? this.address,
      pdfFooterNote: pdfFooterNote ?? this.pdfFooterNote,
      currency: currency ?? this.currency,
      showVatOnTotals: showVatOnTotals ?? this.showVatOnTotals,
      showSignatureArea: showSignatureArea ?? this.showSignatureArea,
    );
  }

  factory AdminCompanySettings.fromMap(Map<String, dynamic> map) {
    return AdminCompanySettings(
      companyTitle: (map['company_title'] as String?) ?? '',
      taxOffice: (map['tax_office'] as String?) ?? '',
      taxNo: (map['tax_no'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      website: (map['website'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      pdfFooterNote: (map['pdf_footer_note'] as String?) ?? '',
      currency:
          AdminCompanyCurrencyX.fromCode(map['currency'] as String?),
      showVatOnTotals: (map['show_vat_on_totals'] as bool?) ?? true,
      showSignatureArea: (map['show_signature_area'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'company_title': companyTitle,
      'tax_office': taxOffice,
      'tax_no': taxNo,
      'phone': phone,
      'email': email,
      'website': website,
      'address': address,
      'pdf_footer_note': pdfFooterNote,
      'currency': currency.code,
      'show_vat_on_totals': showVatOnTotals,
      'show_signature_area': showSignatureArea,
    };
  }
}
