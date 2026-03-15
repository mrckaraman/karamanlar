class ReturnStrings {
  ReturnStrings._();

  // Durations
  static const snackSuccessDuration = Duration(milliseconds: 800);

  // Page header
  static const pageTitle = 'İade Oluştur';
  static const pageSubtitle =
      'Müşteri seçin, ürünleri ekleyin, tutarları kontrol edip kaydedin.';

  static const actionClearAll = 'Temizle';
  static const actionResetDraft = 'Taslağı Sıfırla';

  // List / detail placeholders
  static const returnsListTitle = 'İade & Düzeltme';
  static const returnsListComingSoon = 'İade & düzeltme listesi - Yakında';
  static const returnsDetailTitle = 'İade / Düzeltme Detayı';
  static const returnsDetailInvalidId = 'Geçersiz iade/düzeltme ID bilgisi.';
  static const returnsDetailComingSoon = 'İade / düzeltme detayı - Yakında';

  // Step labels
  static const step1Badge = '1. Cari';
  static const step2Badge = '2. Ürünler';
  static const step3Badge = '3. Satırlar';
  static const step4Badge = '4. Onay';

  static const step1Title = 'Cari / Müşteri Seçimi';
  static const step2Title = 'Ürün Ekleme';
  static const step3Title = 'İade Satırları';
  static const step4Title = 'Özet ve Kaydet';

  // Customer picker
  static const step1Help = 'Önce müşteri seçin, ardından ürünleri ekleyin.';
  static const customerCodeLabel = 'Kod';
  static const customerPhoneLabel = 'Telefon';
  static const customerSearchLabel = 'Cari arama';
  static const customerSearchHint = 'Cari ara: ad, kod, telefon, vergi no...';
  static const customerSelectedTitle = 'Seçilen Cari';
  static const customerChange = 'Cari değiştir';

  static const loadFailedTitle = 'Liste yüklenemedi';
  static String loadFailedSubtitle(String details) =>
      'Liste yüklenemedi: $details';
  static const actionRefresh = 'Yenile';

  static const customerEmptyTitle = 'Cari seçilmedi';
  static const customerEmptySubtitle =
      'Önce bir müşteri seçin, ardından ürünleri ekleyin.';

  static const customerNoResultTitle = 'Sonuç bulunamadı';
  static const customerNoResultSubtitle =
      'Arama kriterlerinize uygun cari kaydı yok.';

  // Product picker
  static const groupFilterLabel = 'Kategori / Grup';
  static const groupFilterAll = 'Tümü';
  static const groupUngrouped = 'Grupsuz';
  static const productSearchHint = 'Ürün ara: ad, kod veya barkod...';
  static const productSearchLabel = 'Ürün arama';
  static const productSelected = 'Seçili ürün';
  static const productPickHelp = 'Bir ürün seçin ve satıra ekleyin.';

  static const actionUnselect = 'Seçimi kaldır';

  static const groupNamesLoadFailedTitle = 'Ürün grupları yüklenemedi';
  static const productsLoadFailedTitle = 'Ürünler yüklenemedi';

  static const actionClear = 'Temizle';
  static const actionScanBarcode = 'Barkod okut';

  static const productEmptyTitle = 'Ürün bulunamadı';
  static const productEmptySubtitle = 'Filtrelere uygun ürün bulunamadı.';

  static const productDisabledTitle = 'Önce cari seçin';
  static const productDisabledSubtitle =
      'Ürün listesi, seçtiğiniz cariye göre hazırlanır.';

  // Line form
  static const unitPiece = 'Adet';
  static const unitPack = 'Paket';
  static const unitBox = 'Koli';
  static const units = <String>[unitPiece, unitPack, unitBox];

  static const fieldQtyLabel = 'Miktar';
  static const fieldQtyHint = 'Örn. 5';
  static const fieldUnitLabel = 'Birim';
  static const fieldUnitPriceLabel = 'Birim Fiyat';
  static const fieldUnitPriceHint = 'Örn. 12,50';
  static const fieldNoteLabel = 'Not (opsiyonel)';
  static const fieldAmountLabel = 'Tutar (otomatik)';
  static const addLineCta = 'Satıra ekle';

  // Lines
  static const linesEmptyTitle = 'Henüz satır eklenmedi';
  static const linesEmptySubtitle =
      'Ürün seçip miktar/fiyat girerek iade satırı ekleyin.';

  static const linesHelp = 'Eklenen ürünler aşağıda listelenir.';

  static const linesFooterHint = 'Kaydetmeden önce toplamları kontrol edin.';

  static const groupingLabel = 'Grupla';

  static const groupingNone = 'Gruplama yok';
  static const groupingByProduct = 'Ürüne göre grupla';
  static const groupingByCategory = 'Kategoriye göre grupla';
  static const groupingByCustomer = 'Cariye göre grupla';

  static const groupCustomerFallback = 'Cari';

  static const linesTotalsLineCount = 'Satır';
  static const linesTotalsUniqueProducts = 'Ürün çeşidi';
  static const linesTotalsQty = 'Toplam miktar';
  static const linesTotalsAmount = 'Genel toplam';

  static const lineActionEdit = 'Düzenle';
  static const lineActionDelete = 'Sil';
  static const lineNoteChip = 'Not';

  static const editLineDialogTitle = 'Satırı Düzenle';
  static const editLineQtyLabel = 'Miktar';
  static const editLineUnitLabel = 'Birim';
  static const editLineUnitPriceLabel = 'Birim fiyat';
  static const editLineNoteLabel = 'Not';
  static const editLineCancel = 'Vazgeç';
  static const editLineSave = 'Kaydet';

  static const tableHeaderProduct = 'Ürün';
  static const tableHeaderQty = 'Miktar';
  static const tableHeaderUnitPrice = 'Birim fiyat';
  static const tableHeaderTotal = 'Toplam';
  static const tableHeaderAction = 'Aksiyon';

  static String unitPriceLabel(String formattedMoney) =>
      'Birim: $formattedMoney';
  static String groupLineCount(int count) => '$count satır';

  // Summary
  static const summaryTitle = 'İade Özeti';
  static const summaryCustomer = 'Cari';
  static const summaryLineCount = 'Toplam satır';
  static const summaryQty = 'Toplam miktar';
  static const summaryAmount = 'Genel toplam';
  static const summaryNotes = 'Not sayısı';
  static const summaryWarnings = 'Son kontrol';

  static const summaryHelp = 'Kaydetmeden önce toplamları kontrol edin.';

  static const savePrimary = 'Kaydet';
  static const saveLoading = 'Kaydediliyor...';
  static const saveSuccess = 'Kaydedildi';

  static const warningMissingCustomer = 'Müşteri seçilmedi.';
  static const warningNoLines = 'İade satırı eklenmedi.';
  static const warningZeroPrice = '0 fiyatlı satır var (kontrol edin).';

  static const snackSaved = 'İade kaydedildi.';
  static const snackSaveFailed = 'İade kaydedilemedi';

  static const snackSelectCustomerFirst = 'Önce cari seçin.';
  static const snackBarcodeNotFound = 'Bu barkoda ait ürün bulunamadı.';
  static const snackProductAdded = 'Ürün satıra eklendi.';

  static String noteFromBarcode(String barcode) => 'Barkod: $barcode';
  static String saveProgressLabel(int saved, int total) =>
      'Kaydedilen satır: $saved / $total';
}
