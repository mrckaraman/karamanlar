# 01 – Uygulama Kapsamı

## Genel Bakış
Karamanlar Ticaret çözümü, iki ayrı mobil uygulamadan oluşur:
- **Admin App (Yönetici Uygulaması):** Stok, cari, satış, tahsilat, ekstre, rapor ve Excel içe aktarma süreçlerini yönetir.
- **Customer App (Müşteri Uygulaması):** Müşterilerin kendi özel fiyatlarıyla ürünleri görüntülemesini, ekstre takibini ve opsiyonel sipariş oluşturmasını sağlar.

Her iki uygulama da tek bir Supabase projesi (Auth, Postgres, Storage, opsiyonel Edge Functions) üzerinde çalışır ve aynı veri modelini paylaşır.

---

## Admin App Kapsamı

### Hedef Kullanıcı Profili
- Firma sahibi / yönetici
- Muhasebe veya satış operasyon ekibi
- İç ofis kullanıcıları

### Ana Modüller
- **Login:**
  - Supabase Auth ile e-posta/şifre tabanlı giriş.
  - `app_metadata.role` değeri "admin" olan kullanıcıları kabul eder.

- **Dashboard:**
  - Özet kartlar: Bugün satış tutarı, bugün tahsilat tutarı, kritik stok adedi, vadesi geçen cari sayısı.
  - Hızlı aksiyonlar: Yeni satış, yeni tahsilat, yeni stok kartı, yeni cari kartı.
  - Uyarılar listesi: Limit aşımı olan cariler, vadesi geçen alacaklar, kritik stoklar.

- **Stok Yönetimi:**
  - Stok listesi: Arama (ad, kod, barkod), filtreleme (kategori, aktif/pasif), sıralama.
  - Stok kartı görüntüleme ve düzenleme: Temel bilgiler, kategori, vergi oranı, marka, fiyatlar, aktif/pasif durumu.
  - Stok resmi yönetimi: Supabase Storage üzerinden stok görseli ekleme, güncelleme veya kaldırma.
  - Birim ve barkod yönetimi: Adet/paket/koli yapısının ve barkodlarının tanımlanması.

- **Cari Yönetimi:**
  - Cari listesi: Arama, filtreleme (kategori, aktif/pasif), sıralama.
  - Cari kartı oluşturma ve güncelleme: Kimlik bilgileri, vergi bilgileri, adres, iletişim, vade, limit, fiyat tipi (price_tier), aktif/pasif.
  - Cari detay ekranı: Ekstre özeti, toplam borç, kullanılabilir limit, vade durumu.
  - Kısayollar: Cari üzerinden hızlı satış ve hızlı tahsilat başlatma.

- **Satış İşlemleri:**
  - Cari seçimi: Sadece aktif cariler listelenir; limit/vade durumu ekranda özetlenir.
  - Satır girişi: Ürün seçimi (ad/kod/barkod), birim (adet/paket/koli), miktar.
  - Fiyatlama: Carinin `price_tier` değerine göre stok kartından otomatik satış fiyatı seçimi.
  - Birim dönüşümü: Girilen birime göre `qty_in_pieces` otomatik hesaplanır.
  - Özet ve onay: Ara toplam, vergi toplamı, genel toplam, limit/vade uyarıları.
  - Kayıt: Satış kaydı oluşturulurken stok bakiyesi, cari borç ve ekstre girdileri eş zamanlı güncellenir.

- **Tahsilat İşlemleri:**
  - Cari seçimi: Sadece aktif cariler listelenir.
  - Tahsilat bilgileri: Tutar, tarih, yöntem (nakit, transfer, eft, kart vb.), açıklama.
  - Opsiyonel dekont yükleme: Supabase Storage üzerinden dekont veya belge saklama.
  - Kayıt: Tahsilat kaydı ile birlikte ilgili carinin borcu düşer ve ekstrede alacak (credit) hareketi oluşur.

- **Ekstre ve Raporlama:**
  - Cari ekstre ekranı: Seçili cari için tüm satış ve tahsilat hareketlerinin tarihsel listesi.
  - Filtreleme: Tarih aralığı, belge türü, tutar aralığı vb.
  - Raporlar:
    - Stok raporu: Stok bakiyesi ve değerleme odaklı.
    - Cari borç raporu: Toplam borç, alacak ve net bakiye.
    - Vade raporu: Vadesi yaklaşan veya geçen alacaklar.
    - Fiyat tipi kullanım raporu: Hangi carilerin hangi fiyat tiplerini kullandığı.

- **Excel İçe Aktarma (Stok):**
  - Excel dosyası yükleme: Supabase Storage "imports" alanına yükleme.
  - Önizleme: Dosyadaki satırların temel alanlarla birlikte listelenmesi.
  - Doğrulama: Zorunlu alanların (kod, ad) ve iş kurallarının kontrolü.
  - Hata raporu: Satır numarası, alan adı ve hata mesajı içeren liste.
  - İçe aktarma: Başarılı satırların stok ve birim/barkod tablolarına eklenmesi veya güncellenmesi.

---

## Customer App Kapsamı

### Hedef Kullanıcı Profili
- Firma müşterileri (bayiler)
- Saha satışları için kendi borç ve fiyat durumunu takip etmek isteyen kullanıcılar

### Ana Modüller
- **Login:**
  - Supabase Auth ile e-posta/şifre tabanlı müşteri girişi.
  - `app_metadata.role` değeri "customer" olan kullanıcıları kabul eder.
  - Kullanıcı ile eşleşen cari kaydı, `customer_users` üzerinden bağlanır.

- **Anasayfa:**
  - Borç özeti: Güncel borç tutarı ve kullanılabilir limit.
  - Vade durumu: En eski vadesi geçmiş alacak ve genel vade bilgisi.
  - Hızlı menü: Ürünler, ekstre, profil ve opsiyonel sipariş ekranlarına kısayollar.

- **Ürünler:**
  - Sadece aktif stokların listelenmesi.
  - Her ürün için müşteriye özel tek satış fiyatının gösterilmesi (price_tier’e göre).
  - Basit filtreler (kategori, marka) ve arama (ad, kod, barkod).

- **Ürün Detay:**
  - Ürünün adı, kodu, görseli, vergi oranı, marka bilgisi.
  - Müşteriye özel fiyatın net biçimde vurgulanması.
  - Birim yapısı (adet/paket/koli) ve bu birimlere ait açıklayıcı bilgiler.

- **Ekstre:**
  - Sadece oturum açmış müşterinin kendi hareketlerinin listesi.
  - Satış ve tahsilatların tarih, tutar, bakiye etkisi ile gösterimi.
  - Filtreleme: Tarih aralığı, işlem türü.

- **Profil:**
  - Firma ticari unvanı, vergi bilgileri, adres ve iletişim bilgileri.
  - Opsiyonel şifre değişikliği ve bildirim tercihleri.

- **Sipariş (Opsiyonel):**
  - Sepet mantığıyla ürün ekleme ve miktar belirleme.
  - Sipariş özeti: Ara toplam, tahmini vergi ve toplam.
  - Sipariş gönderme: Siparişin yönetici tarafında satışa dönüştürülebilmesi için kayıt altına alınması.
  - Geçmiş siparişler: Önceden verilen siparişlerin listesi ve detayları.

---

## Uygulama Sınırları ve Hariç Tutulanlar
- Harici bir backend katmanı yoktur; tüm iş kuralları Supabase Postgres, RLS ve opsiyonel Edge Functions üzerinden yönetilir.
- Detaylı muhasebe entegrasyonu, e-fatura ve benzeri yasal yükümlülükler bu kapsamın dışındadır.
- Gelişmiş kampanya, promosyon ve iskonto motorları ilk sürüm kapsamına dahil değildir; fiyatlandırma yalnızca `price_tier` ve stok satış fiyatları üzerinden yürütülür.

Bu kapsam dokümanı, diğer teknik dokümanlar (veri modeli, iş akışları, güvenlik ve UI rehberi) ile birlikte okunarak tam resme ulaşılmalıdır.