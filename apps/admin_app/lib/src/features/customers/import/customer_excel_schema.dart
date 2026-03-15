/// Canonical alan anahtarları (DB / form ile uyumlu).
class CustomerExcelFields {
  static const customerType = 'customer_type';
  static const tradeTitle = 'trade_title';
  static const fullName = 'full_name';
  static const customerCode = 'customer_code';

  static const phone = 'phone';
  static const email = 'email';

  static const taxOffice = 'tax_office';
  static const taxNo = 'tax_no';

  static const address = 'address';
  static const city = 'city';
  static const district = 'district';

  static const limitAmount = 'limit_amount';
  static const warnOnLimitExceeded = 'warn_on_limit_exceeded';
  static const salesRepName = 'sales_rep_name';
  static const riskNote = 'risk_note';

  static const tagsCsv = 'tags_csv';
  static const isActive = 'is_active';

  static const priceListName = 'price_list_name';
  static const dueDays = 'due_days';

  static const openingBalanceAmount = 'opening_balance_amount';
  static const openingBalanceType = 'opening_balance_type';

  static const group = 'group';
  static const subGroup = 'sub_group';
  static const subSubGroup = 'sub_sub_group';
}

/// Excel başlıkları (Türkçe) -> canonical key eşleşmeleri.
const Map<String, String> customerExcelHeaderAliases = {
  // Kimlik
  'cari türü': CustomerExcelFields.customerType,
  'ticari ünvan': CustomerExcelFields.tradeTitle,
  'ticari unvan': CustomerExcelFields.tradeTitle,
  'yetkili kişi': CustomerExcelFields.fullName,
  'cari kodu': CustomerExcelFields.customerCode,

  // İletişim
  'telefon': CustomerExcelFields.phone,
  'e-posta': CustomerExcelFields.email,
  'eposta': CustomerExcelFields.email,

  // Vergi / Kimlik
  'vergi dairesi': CustomerExcelFields.taxOffice,
  'vergi no / tckn': CustomerExcelFields.taxNo,
  'vergi no': CustomerExcelFields.taxNo,

  // Adres
  'adres': CustomerExcelFields.address,
  'il': CustomerExcelFields.city,
  'ilçe': CustomerExcelFields.district,

  // Risk & Limit
  'kredi limiti (tl)': CustomerExcelFields.limitAmount,
  'limit aşıldığında uyar': CustomerExcelFields.warnOnLimitExceeded,
  'pazarlamacı adı soyadı': CustomerExcelFields.salesRepName,
  'risk notu': CustomerExcelFields.riskNote,

  // Diğer
  'etiketler': CustomerExcelFields.tagsCsv,
  'aktif': CustomerExcelFields.isActive,

  // Satış Ayarları
  'fiyat listesi': CustomerExcelFields.priceListName,
  'vade (gün)': CustomerExcelFields.dueDays,

  // Açılış Bakiyesi
  'açılış bakiyesi': CustomerExcelFields.openingBalanceAmount,
  'acilis bakiyesi': CustomerExcelFields.openingBalanceAmount,
  'açılış bakiyesi tür': CustomerExcelFields.openingBalanceType,
  'acilis bakiyesi tur': CustomerExcelFields.openingBalanceType,

  // Gruplama
  'grup': CustomerExcelFields.group,
  'ara grup': CustomerExcelFields.subGroup,
  'alt grup': CustomerExcelFields.subSubGroup,
};

/// Export sırasında kullanılacak kolon sırası.
const List<String> customerExcelExportOrder = [
  // Kimlik
  CustomerExcelFields.customerType,
  CustomerExcelFields.tradeTitle,
  CustomerExcelFields.fullName,
  CustomerExcelFields.customerCode,
  // İletişim
  CustomerExcelFields.phone,
  CustomerExcelFields.email,
  // Vergi / Kimlik
  CustomerExcelFields.taxOffice,
  CustomerExcelFields.taxNo,
  // Adres
  CustomerExcelFields.address,
  CustomerExcelFields.city,
  CustomerExcelFields.district,
  // Risk & Limit
  CustomerExcelFields.limitAmount,
  CustomerExcelFields.warnOnLimitExceeded,
  CustomerExcelFields.salesRepName,
  CustomerExcelFields.riskNote,
  // Diğer
  CustomerExcelFields.tagsCsv,
  CustomerExcelFields.isActive,
  // Satış Ayarları
  CustomerExcelFields.priceListName,
  CustomerExcelFields.dueDays,
  // Gruplama
  CustomerExcelFields.group,
  CustomerExcelFields.subGroup,
  CustomerExcelFields.subSubGroup,
];

/// Export için Türkçe başlıklar (Excel ilk satırında kullanılacak).
const Map<String, String> customerExcelHeaderTr = {
  CustomerExcelFields.customerType: 'Cari Türü',
  CustomerExcelFields.tradeTitle: 'Ticari Ünvan',
  CustomerExcelFields.fullName: 'Yetkili Kişi',
  CustomerExcelFields.customerCode: 'Cari Kodu',

  CustomerExcelFields.phone: 'Telefon',
  CustomerExcelFields.email: 'E-posta',

  CustomerExcelFields.taxOffice: 'Vergi Dairesi',
  CustomerExcelFields.taxNo: 'Vergi No / TCKN',

  CustomerExcelFields.address: 'Adres',
  CustomerExcelFields.city: 'İl',
  CustomerExcelFields.district: 'İlçe',

  CustomerExcelFields.limitAmount: 'Kredi Limiti (TL)',
  CustomerExcelFields.warnOnLimitExceeded: 'Limit Aşıldığında Uyar',
  CustomerExcelFields.salesRepName: 'Pazarlamacı Adı Soyadı',
  CustomerExcelFields.riskNote: 'Risk Notu',

  CustomerExcelFields.tagsCsv: 'Etiketler',
  CustomerExcelFields.isActive: 'Aktif',

  CustomerExcelFields.priceListName: 'Fiyat Listesi',
  CustomerExcelFields.dueDays: 'Vade (gün)',

  CustomerExcelFields.group: 'Grup',
  CustomerExcelFields.subGroup: 'Ara Grup',
  CustomerExcelFields.subSubGroup: 'Alt Grup',
};

String canonicalCustomerHeader(String header) {
  final key = header.trim().toLowerCase();
  return customerExcelHeaderAliases[key] ?? header;
}
