# Karamanlar Ticaret

## 1) Proje Özeti
Karamanlar Ticaret, toptan ticaret süreçlerini dijitalleştirmek için tasarlanmış, tamamen Supabase üzerinde çalışan iki mobil uygulamadan (Admin App ve Customer App) oluşan bir çözümdür. Stok, cari, satış, tahsilat ve ekstre yönetimi tek bir merkezi veri modeli üzerinden yürütülür; yöneticiler için gelişmiş raporlama ve Excel ile toplu veri işlemleri, müşteriler için ise kendi özel fiyatlarıyla ürün görüntüleme ve ekstre takibi sunar.

## 2) Uygulamalar ve Rolleri

### Admin App (Yönetici Uygulaması)
Yönetici ve ofis kullanıcıları için tasarlanmıştır. Ana yetenekler:
- Stok yönetimi: listeleme, filtreleme, arama, aktif/pasif, detay kartı
- Cari yönetimi: cari kart açma, güncelleme, limit/vade tanımı, aktif/pasif
- Satış işlemleri: cari seçimi, ürün satırları, birim dönüşümü, otomatik fiyat
- Tahsilat işlemleri: nakit/havale/eft/kart vb. yöntemlerle tahsilat kaydı
- Ekstre görüntüleme: müşteri bazlı detaylı hareket dökümü
- Raporlar: stok, cari borç, vade, fiyat tipi kullanımı vb.
- Excel import: stok ve ilgili birim/barkod bilgilerinin Excel üzerinden içe aktarımı

### Customer App (Müşteri Uygulaması)
Son müşteriler (bayi/müşteri) için tasarlanmıştır. Ana yetenekler:
- Giriş: Supabase Auth üzerinden güvenli müşteri girişi
- Ürünler: sadece aktif stokların listesi, müşteri özel fiyatlarıyla görüntüleme
- Ürün detay: fiyat ve birim yapısı (adet/paket/koli) gösterimi
- Ekstre: sadece ilgili müşterinin kendi hareketlerini görüntüleme
- Profil: firma bilgileri, iletişim, (opsiyonel) şifre değişimi vb.
- Sipariş (opsiyonel): sepet, sipariş gönderimi ve geçmiş siparişlerin görüntülenmesi

## 3) Kritik İş Kuralları

- **Fiyatlandırma (price_tier):**
  - Her cari kartında `price_tier` alanı (1..4) bulunur.
  - Stok kartında `sale_price_1..4` alanları bulunur.
  - Satış satırında bir ürün seçildiğinde, ilgili carinin `price_tier` değeri okunur ve stok kartındaki karşılık gelen `sale_price_{tier}` otomatik olarak birim fiyat olarak kullanılır.

- **Birim dönüşümü (adet/paket/koli → qty_in_pieces):**
  - Kullanıcı satış satırında birim (adet/paket/koli) ve miktar girer.
  - Sistem, stok birim tanımlarındaki `pack_contains_piece` ve `case_contains_piece` alanlarını kullanarak `qty_in_pieces` değerini otomatik hesaplar.
  - Örnek kurallar:
    - adet: `qty_in_pieces = qty_input`
    - paket: `qty_in_pieces = qty_input * pack_contains_piece`
    - koli: `qty_in_pieces = qty_input * case_contains_piece`

- **Satış kaydı etkileri:**
  - Satış kaydı oluşturulduğunda tek transaction içinde:
    - Stok bakiyesi (stock_balances) ilgili ürün için `qty_in_pieces` kadar düşer.
    - İlgili cari hesabın borcu artar.
    - Ekstre (ledger_entries) tablosuna satış için bir **debit** kaydı yazılır.

- **Tahsilat kaydı etkileri:**
  - Tahsilat girildiğinde:
    - İlgili cari hesabın borcu tahsilat tutarı kadar azalır.
    - Ekstre (ledger_entries) tablosuna tahsilat için bir **credit** kaydı yazılır.

- **Sipariş tamamlandığında otomatik fatura (auto-invoice):**
  - `orders.status` değeri `completed` olduğunda Supabase tarafında bir trigger çalışır.
  - İlgili `order_id` için `invoices` tablosunda kayıt yoksa yeni fatura oluşturur, varsa sadece `status`, `issued_at`, `invoice_date`, `total_amount`, `customer_id` alanlarını günceller.
  - Fatura numarası (`invoice_no`) yoksa `FYYMMDD-kısaOrderId` formatında otomatik üretilir.

- **Limit / vade kontrolü (patron modu):**
  - Satış kaydı öncesinde sistem, carinin tanımlı limit ve vade bilgilerini kontrol eder.
  - Konfigürasyona göre iki mod desteklenir:
    - **Uyar modu:** Limit/vade aşıldığında kullanıcıya uyarı gösterilir, satış isteğe bağlı olarak devam edebilir.
    - **Engelle modu:** Limit/vade aşıldığında sistem satış kaydını engeller.

## 4) Dokümantasyon
Detaylı analiz, veri modeli ve iş akışları için `docs` klasöründeki dosyalar kullanılır:

- Genel amaç ve kapsam: [docs/00_README.md](docs/00_README.md)
- Uygulama kapsamı ve ekranlar: [docs/01_UYGULAMA_KAPSAMI.md](docs/01_UYGULAMA_KAPSAMI.md)
- Veri modeli ve şema tasarımı: [docs/02_VERI_MODELI_SPEK.md](docs/02_VERI_MODELI_SPEK.md)
- İş akışları (satış, tahsilat, ekstre vb.): [docs/03_IS_AKISLARI.md](docs/03_IS_AKISLARI.md)
- Güvenlik ve RLS politikaları: [docs/04_GUVENLIK_RLS.md](docs/04_GUVENLIK_RLS.md)
- Edge Functions gereksinimleri: [docs/05_EDGE_FUNCTIONS_GEREKSINIM.md](docs/05_EDGE_FUNCTIONS_GEREKSINIM.md)
- UI tema ve tasarım rehberi: [docs/06_UI_TEMA_GUIDE.md](docs/06_UI_TEMA_GUIDE.md)

## 5) Kurulum / Çalıştırma (Yüksek Seviye)

Bu bölüm, teknik uygulama adımlarını kod seviyesine inmeden yüksek seviye olarak özetler.

### 5.1 Supabase altyapısı
- Yeni bir Supabase projesi oluştur.
- Postgres tarafında veri modeli dokümanına göre tabloları tanımla (`categories`, `stocks`, `stock_units`, `customers`, `customer_users`, `sales`, `sale_lines`, `payments`, `ledger_entries`, `stock_balances` vb.).
- RLS (Row Level Security) politikalarını `docs/04_GUVENLIK_RLS.md` içindeki rol modeline göre uygula:
  - `app_metadata.role = "admin" | "customer"` olacak şekilde rol modelini kur.
  - Müşteri rolü için sadece kendi `customer_id` verilerini görecek kısıtları tanımla.
  - Admin rolü için ilgili tablolarda tam yetki (full CRUD) ver.
- Storage bucket yapılarını oluştur:
  - `stock-images`: stok resimleri için, herkes read; sadece admin write.
  - `receipts`: dekont/dosya yüklemeleri için; varsayılan olarak sadece admin erişimi.
  - `imports`: Excel import dosyaları için; sadece admin erişimi.
- (Opsiyonel) Edge Functions kur:
  - `create_sale`, `create_payment`, `import_stocks_excel` fonksiyonlarını `docs/05_EDGE_FUNCTIONS_GEREKSINIM.md`’ye göre tasarla.
  - İşlemleri tek transaction içinde çalışacak şekilde kurgula.

### 5.2 Mobil uygulamalar (Flutter)
- Repo yapısında iki ayrı Flutter projesi öngörülür:
  - `admin_app/` (yönetici uygulaması)
  - `customer_app/` (müşteri uygulaması)
- Her iki proje için de:
  - Supabase istemcisini projeye ekle ve environment yapılarını hazırla.
  - Auth akışını Supabase ile entegre et (login, session yönetimi vb.).
  - İlgili ekranları ve veri çağrılarını `docs` altındaki kapsam ve iş akışlarına göre uygula.
- Admin App tarafında ek olarak:
  - Excel import ekranı ve Supabase storage + edge function entegrasyonlarını kurgula.

### 5.3 Flutter Web için cache temizliği ve eski bundle sorunları

Supabase/PostgREST sorgularında daha önce kullanılan ama artık şemada olmayan kolonlar (ör. `customers.customer_id`) Flutter web tarafında **eski derlenmiş JS bundle** üzerinden çalışmaya devam edebilir. Bu durumda kodu düzeltsen bile tarayıcı cache’inde kalan eski bundle, PostgREST’e yanlış `select=` parametreleri göndermeye devam eder.

Flutter web çalışırken aşağıdaki adımları izlemen önerilir:

- Proje kökünde `flutter clean` çalıştır.
- İlgili uygulama klasörüne geç:
  - Admin için: `cd apps/admin_app`
  - Customer için: `cd apps/customer_app`
- Uygulamayı yeniden başlat:
  - Örneğin: `flutter run -d chrome --web-port 5555`
- Chrome/Edge DevTools’u aç:
  - Network sekmesinde **Disable cache** kutusunu işaretle.
  - Ardından **Hard Reload (Ctrl+Shift+R)** yap.
- Hata veren istekleri Network sekmesinde seçip URL içindeki `select=` parametresini kontrol et; burada `customers.customer_id` gibi alanlar görüyorsan bu kodda değil, hala eski bundle’ın çalıştığını veya backend tarafındaki view/policy tanımlarında yanlış kolon referansı olduğunu gösterir.

Bu adımlar sonrasında hem Admin hem Customer web uygulamalarında `column customers.customer_id does not exist` ve `PGRST116` hatalarının, Dart tarafındaki eski sorgulardan kaynaklanma ihtimali ortadan kalkar.

## 6) Yol Haritası

- **RC-1:** Temel veri modeli, Supabase şeması, RLS politikaları ve storage bucket’ların tamamlanması.
- **RC-2:** Admin App için temel ekranlar: login, dashboard, stok listesi/formu, cari listesi/formu, satış ve tahsilat oluşturma.
- **RC-3:** Customer App için temel ekranlar: login, ürün listesi/detayı, ekstre, profil.
- **RC-4:** Excel import akışı (stoklar) ve hata raporlama ekranlarının tamamlanması.
- **RC-5:** Limit/vade kontrolü (uyar/engelle modları), raporlama ekranları ve performans/güvenlik iyileştirmeleri.
- **RC-6:** Edge Functions ile tam entegre satış/tahsilat transaction akışları ve son kullanıcı testleri.

## 7) Lisans / İletişim

Bu proje için lisans modeli proje sahibi tarafından belirlenecektir. Ticari kullanım, yeniden dağıtım veya katkı süreçleriyle ilgili detaylar henüz netleştirilmemiştir.

İletişim ve iş birliği talepleri için proje sahibi ile doğrudan iletişime geçebilirsiniz.
