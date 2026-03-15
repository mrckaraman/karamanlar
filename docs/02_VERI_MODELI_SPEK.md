# 02 – Veri Modeli Spesifikasyonu

## Genel İlkeler
- Tüm veri modeli Supabase Postgres üzerinde tanımlanır.
- Admin App ve Customer App aynı veri modelini paylaşır; rol tabanlı erişim, tablo ve satır seviyesinde kısıtlarla yönetilir.
- Kimlik alanlarında tutarlılık için mümkün olduğunca tekil kimlikler kullanılır.
- Para ve miktar alanlarında, yuvarlama ve hassasiyet kuralları iş katmanında net biçimde tanımlanmalıdır.

---

## 2.1 Kategori Yapısı (Stok ve Cari için Ortak)

### Amaç
Stok ve cari kayıtlarının, çok seviyeli bir kategori ağacı altında gruplanmasını sağlamak.

### Kavramsal Alanlar
- Kimlik alanı (tür olarak evrensel benzersiz kimlik önerilir).
- Ad alanı (kategori adı).
- Üst kategori kimliği (isteğe bağlı; kategori kendi kendine referans verir).
- Seviye bilgisi (0, 1 veya 2):
  - Seviye 0: Grup
  - Seviye 1: Ara Grup
  - Seviye 2: Alt Grup
- Oluşturulma tarihi.

### İş Kuralları
- Kategori ağacı en fazla üç seviye derinliğe sahiptir.
- Her stok veya cari kaydı, isteğe bağlı olarak bir kategoriye bağlanabilir.
- Seviye bilgisi, üst kategori ilişkisiyle tutarlı olmalıdır (örneğin seviye 2 olan bir kategori, seviye 1 olan bir kategoriye bağlı olmalıdır).

---

## 2.2 Stok Kartı

### Amaç
Satılabilir ürünlerin temel ticari bilgilerini ve fiyatlandırma yapısını tanımlamak.

### Kavramsal Alanlar
- Temel bilgiler: Ad, kod (eşsiz), opsiyonel barkod.
- Kategori referansı: Ortak kategori tablosuna bağ.
- Özel kod alanları: Raporlama ve gruplama amaçlı.
- Vergi oranı.
- Marka bilgisi.
- Aktif/pasif durumu.
- Görsel yolu: Supabase Storage içindeki stok görseline işaret eder.
- Maliyet ve satış fiyatları:
  - Alış fiyatı.
  - Satış fiyatları: Birden fazla seviye (örneğin dört adet) fiyat alanı.

### İş Kuralları
- Stok kodu benzersiz olmalıdır.
- Bir stok pasif ise Customer App tarafında gösterilmez; Admin App tarafında sadece yönetim amaçlı listelenir.
- Stok kartı silinmek yerine pasife alınmalıdır; böylece geçmiş satış ve hareket kayıtları bozulmaz.

---

## 2.3 Stok Birim ve Barkod Yapısı

### Amaç
Aynı ürün için adet, paket ve koli bazında tanım yapılmasını ve buna bağlı birim dönüşümü kurallarını desteklemek.

### Kavramsal Alanlar
- Stok referansı: İlgili stok kartına bağ.
- Birim barkodları: Adet, paket ve koli bazında ayrı barkod alanları.
- Dönüşüm katsayıları:
  - Bir paketin kaç adet içerdiği.
  - Bir kolinin kaç adet içerdiği.

### Birim Dönüşüm Kuralları
- Adet biriminde satış yapıldığında, satır miktarı doğrudan parça adedi olarak yorumlanır.
- Paket biriminde satış yapıldığında, satır miktarı paket sayısıdır ve her paket için tanımlanan adet katsayısı ile çarpılır.
- Koli biriminde satış yapıldığında, satır miktarı koli sayısıdır ve her koli için tanımlanan adet katsayısı ile çarpılır.
- Tüm satış ve stok hareketlerinde, gerçek stok bakiyesi parça adedi üzerinden takip edilir.

---

## 2.4 Cari (Müşteri) Kartı

### Amaç
Müşterilerin kimlik, iletişim, ticari ve finansal koşullarını tanımlamak.

### Kavramsal Alanlar
- Kimlik ve kodlama: Cari kodu (benzersiz), tam ad, ticari unvan.
- Kategori referansı (isteğe bağlı).
- Özel kod alanı (raporlama amaçlı).
- Vergi bilgileri: Vergi dairesi, vergi numarası, kimlik numarası.
- Adres bilgileri: İl, ilçe ve detay adres.
- İletişim: Telefon, e-posta.
- Finansal koşullar:
  - Vade gün sayısı.
  - Kredi limiti.
  - Fiyat tipi: Belirli bir aralık içindeki seviye.
- Aktif/pasif durumu.

### İş Kuralları
- Fiyat tipi alanı yalnızca önceden tanımlanmış seviye değerlerinden birini alabilir.
- Pasif cariler yeni satış için listelenmez; ancak geçmiş kayıtlar görüntülenebilir.
- Cari kodu projede benzersiz olmalıdır.

---

## 2.5 Auth Eşleştirme (Müşteri Kullanıcıları)

### Amaç
Supabase Auth kullanıcılarını ilgili cari kayıtlarıyla ilişkilendirerek Customer App erişimini sınırlandırmak.

### Kavramsal Alanlar
- Kullanıcı kimliği (Auth kullanıcı kaydına referans).
- Cari kimliği (müşteri kartına referans).

### İş Kuralları
- Her müşteri kullanıcısının, en az bir cari kaydı ile ilişkisi olmalıdır.
- Customer App’te oturum açan kullanıcı, yalnızca ilişkili olduğu carinin verilerini görür.
- Admin App kullanıcıları için bu eşleştirme zorunlu değildir; admin rolü, tüm carilere erişebilir.

---

## 2.6 Satış (Header ve Satırlar)

### Amaç
Müşteri satış işlemlerini, üst seviye belge ve satır detayları olarak kaydetmek.

### Header Seviyesi Alanlar
- Cari referansı.
- Satış tarihi.
- Satış türü (peşin, vadeli, kısmi gibi sınırlı kümeden bir değer).
- Ara toplam, vergi toplamı ve genel toplam.
- Oluşturan kullanıcı bilgisi.

### Satır Seviyesi Alanlar
- Satış belgesine referans.
- Stok referansı.
- Birim türü (adet, paket, koli gibi sınırlı kümeden bir değer).
- Girilen miktar (satırda beyan edilen miktar).
- Parça adedi cinsinden miktar.
- Birim fiyat.
- Vergi oranı.
- Satır toplamı (vergiler dahil veya hariç net kurala göre yorumlanır).

### Fiyatlandırma Kuralı
- Bir satış satırında bir stok seçildiğinde, ilgili carinin fiyat tipi değeri okunur.
- Stok kartındaki seviye bazlı satış fiyatlarından, carinin fiyat tipine karşılık gelen alan birim fiyat olarak kullanılır.

---

## 2.7 Tahsilat

### Amaç
Müşterilerden alınan ödemeleri kaydetmek ve cari bakiyesini güncellemek.

### Kavramsal Alanlar
- Cari referansı.
- Tahsilat tarihi.
- Ödeme yöntemi (nakit, transfer, eft, kart gibi sınırlı kümeden bir değer).
- Tutar.
- Açıklama notu.
- Opsiyonel dekont yolu (Supabase Storage içindeki kayıt).
- Oluşturan kullanıcı bilgisi.

### İş Kuralları
- Tahsilat kaydı eklendiğinde, ilgili carinin borç bakiyesi tahsilat tutarı kadar azaltılır.
- Muhasebe bakiyesinin tutarlılığı için, her tahsilat hareketi ekstre tablosunda alacak hareketi olarak izlenir.

---

## 2.8 Ekstre (Ledger) Yapısı

### Amaç
Her cari için, tarihsel bazda tüm borç ve alacak hareketlerinin tek bir tabloda izlenmesini sağlamak.

### Kavramsal Alanlar
- Cari referansı.
- Kayıt tarihi.
- Kayıt türü (satış, tahsilat, düzeltme gibi sınırlı kümeden bir değer).
- Referans tablo adı (satış veya tahsilat tablosu gibi).
- Referans kayıt kimliği.
- Borç tutarı.
- Alacak tutarı.
- Not alanı.

### İş Kuralları
- Satış işlemleri ekstrede borç hanesini artırır.
- Tahsilat işlemleri ekstrede alacak hanesini artırır.
- Düzeltme veya manuel hareketler, belirlenmiş kurallara göre borç veya alacak hanesinde gösterilir.

---

## 2.9 Stok Bakiyesi

### Amaç
Her stok için anlık toplam parça adedi bakiyesini pratik biçimde tutmak ve raporlamayı hızlandırmak.

### Kavramsal Alanlar
- Stok referansı.
- Parça adedi cinsinden mevcut stok miktarı.
- Son güncelleme tarihi.

### İş Kuralları
- Yeni bir satış veya stok hareketi gerçekleştiğinde, ilgili stok için bakiye güncellenir.
- Kritik stok seviyesi gibi iş kuralları, bu alan üzerinden değerlendirilir.

---

## Admin App ve Customer App Açısından Veri Modeli
- **Admin App:** Tüm yukarıdaki tablolar üzerinde tam yetkili okuma ve yazma işlemlerine ihtiyaç duyar; limit ve vade kontrolleri, stok yönetimi ve Excel içe aktarma süreçleri için bu model temel alınır.
- **Customer App:**
  - Carinin kendi kartı ve yalnızca kendisine ait satış, tahsilat ve ekstre kayıtlarını okuyabilir.
  - Sadece aktif stokları görebilir ve stok fiyatlarına, kendi fiyat tipi üzerinden erişir.
  - Veri modeli üzerinde doğrudan yazma işlemleri sınırlıdır; sipariş gibi opsiyonel modüller, kontrollü ekleme işlemleri yapabilir.

Bu veri modeli spesifikasyonu, güvenlik ve RLS kuralları ile birlikte ele alınmalı ve ilgili dokümanlarla (özellikle güvenlik ve iş akışları) uyumlu biçimde uygulanmalıdır.