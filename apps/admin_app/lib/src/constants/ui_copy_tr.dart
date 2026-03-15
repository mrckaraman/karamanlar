class UiCopyTr {
  UiCopyTr._();

  // Admin dashboard
  static const dashboardOverviewSubtitle =
      'Bugünkü sipariş, fatura ve cari hareketlerinin özeti.';
  static const dashboardOrdersSubtitle =
      'Yeni siparişleri incele, onayla ve sevkiyatı başlat.';
  static const dashboardInvoicesSubtitle =
      'Kesilen faturaları ve irsaliyeleri izle, durumlarını takip et.';
  static const dashboardCustomersSubtitle =
      'Cari kartlar, limitler, tahsilatlar ve hesap hareketleri.';
  static const dashboardSettingsSubtitle =
      'Stok, fiyat, birim ve sistem tanımlarını yapılandır.';

  // Customer management menu
  static const customersManagementSubtitle =
      'Cari kartları, hesap hareketleri, tahsilatlar ve risk/limit kontrolü tek yerden.';

  static const customersMenuNewSubtitle =
      'Yeni müşteri kartı oluştur; istersen müşteri uygulaması girişini de tanımla.';
  static const customersMenuInfoSubtitle =
      'Kayıtlı carileri listele, güncelle ve aktiflik durumlarını yönet.';
  static const customersMenuLedgerSubtitle =
      'Borç–alacak hareketlerini incele, ekstreyi dışa aktar.';
  static const customersMenuPaymentsSubtitle =
      'Tahsilat kayıtlarını görüntüle ve ödeme geçmişini takip et.';
  static const customersMenuAgingSubtitle =
      'Vadeye göre borç dağılımını analiz et, gecikenleri tespit et.';
  static const customersMenuRiskSubtitle =
      'Cari riskini, kredi limitini ve açık hesap durumunu kontrol et.';
  static const customersMenuReportsSubtitle =
      'Cari performans ve tahsilat raporlarını al.';

  // Customer create tabs & headers
  static const customerTabsGeneral = 'Genel Bilgiler';
  static const customerTabsAccount = 'Hesap & Ekstre';
  static const customerTabsPayments = 'Tahsilatlar';
  static const customerTabsAging = 'Vade & Aging';
  static const customerTabsRisk = 'Risk & Limit';

  static const customerCreateHeaderTitle = 'Yeni Cari Ekle';
  static const customerCreateHeaderSubtitle =
      'Cari kimliğini ve temel iletişim bilgilerini tanımla.';

  static const customerGeneralIntro =
      'Cari kimliğini belirle; fatura ve ticari bilgiler bu seçime göre düzenlenir.';

  static const customerLockedSectionsInfo =
      'Bu bölüm, cari kaydedildikten sonra aktif olur.';

  // Form field copy
  static const customerFieldFullNameLabel =
      'Cari Adı Soyadı (Bireysel)';
  static const customerFieldFullNameHint = 'Ahmet Yılmaz';
  static const customerFieldFullNameHelper =
      'Bireysel müşteriler için zorunlu.';

  static const customerFieldTradeTitleLabel = 'Ticari Ünvan';
  static const customerFieldTradeTitleHint =
      'Karamanlar Gıda Tic. Ltd. Şti.';
  static const customerFieldTradeTitleHelper =
      'Fatura ve irsaliyelerde bu ünvan kullanılır.';

  static const customerFieldCodeLabel = 'Cari Kodu (opsiyonel)';
  static const customerFieldCodeHint = 'C000123';
  static const customerFieldCodeHelper =
      'Boş bırakırsan sistem otomatik oluşturur.';

  static const customerFieldPhoneLabel = 'Telefon *';
  static const customerFieldPhoneHint = '05xx xxx xx xx';
  static const customerFieldPhoneHelper =
      'Sipariş ve bilgilendirmeler için kullanılır.';

  static const customerFieldEmailLabel = 'E-posta';
  static const customerFieldEmailHint = 'musteri@firma.com';
  static const customerFieldEmailHelper =
      'Müşteri uygulaması girişi için kullanılır.';

  static const customerFieldInitialPasswordLabel =
      'Müşteri Uygulaması İlk Şifre';
  static const customerFieldInitialPasswordHint = 'En az 6 karakter';
  static const customerFieldInitialPasswordHelper =
      'Müşteri, ilk girişte şifreyi değiştirebilir.';

  static const customerFieldAddressLabel = 'Adres';
  static const customerFieldAddressHint =
      'Mahalle, cadde, sokak, no…';

  static const customerFieldTaxOfficeLabel = 'Vergi Dairesi';
  static const customerFieldTaxOfficeHint = 'Meram V.D.';

  static const customerFieldTaxNoLabel = 'Vergi No / TCKN';
  static const customerFieldTaxNoHint = '1234567890';
  static const customerFieldTaxNoHelper =
      'Ticari ise VKN, bireysel ise TCKN girin.';

  static const customerFieldContactLabel = 'Yetkili Kişi';
  static const customerFieldContactHint =
      'Muhasebe / Satınalma Yetkilisi';

  static const customerFieldPriceListLabel = 'Fiyat Listesi';
  static const customerFieldPriceListHelper =
      'Bu cari için uygulanacak fiyat listesini seç.';

  static const customerFieldOpeningBalanceLabel = 'Açılış Bakiyesi';
  static const customerFieldOpeningBalanceHint = '0';
  static const customerFieldOpeningBalanceHelper =
      'Cariyi başlangıçta borçlu veya alacaklı başlatır.';

  static const customerFieldBalanceTypeLabel = 'Tür';
  static const customerFieldBalanceTypeHelper =
      'Borç = bize borçlu, Alacak = bize alacaklı başlar.';

  static const customerFieldDueDaysLabel = 'Vade (gün)';
  static const customerFieldDueDaysHint = '15';
  static const customerFieldDueDaysHelper =
      'Varsayılan vade süresi; faturalar için öneri olarak kullanılır.';

  static const customerRequiredNote = '* işaretli alanlar zorunludur.';

  // Save button & status
  static const customerFormSaveDisabled = 'Zorunlu alanları doldurun';
  static const customerFormSavePrimary = 'Cari Oluştur';
  static const customerFormSaving = 'Kaydediliyor…';
  static const customerFormSaveSuccess = 'Cari oluşturuldu.';
  static const customerFormSaveError =
      'Cari oluşturulamadı. Lütfen bilgileri kontrol edin.';
}
