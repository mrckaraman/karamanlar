# 06 – UI Tema ve Tasarım Rehberi

## Genel Tasarım Prensipleri
- Her iki uygulamada da kart tabanlı, sade ve okunaklı bir arayüz hedeflenir.
- Büyük sayılar (toplam borç, toplam satış, limit gibi) tek tip ve okunaklı bir yazı tipiyle vurgulanır.
- Fazla çizgi ve karmaşadan kaçınılır; boşluk kullanımı ile hiyerarşi sağlanır.
- Renk paleti, yönetici ve müşteri tarafında tutarlı ancak rollere uygun ton farkları içerebilir.

---

## Ortak Bileşen Prensipleri
- **Kartlar:**
  - Özet bilgiler için kart yapısı kullanılır (örneğin borç/limit durumu, stok özeti).
  - Kart başlığı, ana metin ve ikincil bilgi alanları net olarak ayrılmalıdır.
- **Listeler:**
  - Satır aralıkları yeterli genişlikte olmalı, seçim yapılan satır net biçimde vurgulanmalıdır.
  - Önemli bilgiler (ad, tutar, tarih) ilk bakışta görülebilecek şekilde konumlandırılmalıdır.
- **Formlar:**
  - Giriş alanları gruplandırılarak adım adım doldurulabilir hale getirilmelidir (örneğin cari bilgileri, adres, finansal koşullar gibi gruplar).
  - Hata mesajları, ilgili alanın hemen altında kısa ve anlaşılır şekilde gösterilmelidir.
- **Durum Göstergeleri:**
  - Aktif/pasif durumları, renk ve ikon kombinasyonlarıyla belirtilebilir.
  - Kritik uyarılar (limit aşımı, vade gecikmesi) dikkat çeken fakat rahatsız etmeyen biçimde öne çıkarılmalıdır.

---

## Admin App Tasarım Rehberi

### Dashboard
- Ana ekran, yöneticinin günlük karar almasını kolaylaştıracak şekilde tasarlanmalıdır.
- Önerilen içerik:
  - Bugünkü satış ve tahsilat tutarlarını gösteren özet kartlar.
  - Kritik stokları ve vadesi geçen carileri listeleyen uyarı bölümü.
  - "Yeni Satış", "Yeni Tahsilat", "Yeni Stok", "Yeni Cari" gibi hızlı aksiyon butonları.

### Stok ve Cari Listeleri
- Arama ve filtre alanları ekranın üst kısmında, liste hemen altında konumlandırılmalıdır.
- Satırlarda temel bilgiler önceliklendirilmeli (örneğin stok için kod, ad, kategori; cari için kod, unvan, bakiye, vade durumu).
- Aktif/pasif durumları ve kritik seviyeler (örneğin stok seviyesi) görsel işaretlerle desteklenmelidir.

### Form Ekranları
- Stok ve cari formları, sekme veya bölüm başlıklarıyla daha küçük parçalara ayrılabilir.
- Zorunlu alanlar net bir işaretle belirtilmeli ve boş bırakıldığında kullanıcıya hemen bilgi verilmelidir.

### Satış ve Tahsilat Ekranları
- Satış ekranında cari seçimi, satır girişi ve özet bölümü net olarak ayrılmalıdır.
- Satır girişi alanları (ürün, birim, miktar) pratik kullanım için optimize edilmelidir.
- Tahsilat ekranında, ödeme yöntemi seçimi ve tutar alanı belirgin şekilde vurgulanmalıdır.

### Excel İçe Aktarma Ekranı
- Dosya seçimi, önizleme ve hata raporu bölümleri ayrı adımlar olarak sunulmalıdır.
- Hata listesi, satır numarası ve kısa hata açıklamalarını net şekilde göstermelidir.

---

## Customer App Tasarım Rehberi

### Anasayfa
- Müşteriye özel borç, limit ve vade durumu tek bakışta anlaşılacak şekilde sunulmalıdır.
- "Sana özel fiyat" vurgusu, uygun bir görsel öge veya kısa metinle belirtilmelidir.
- Ürünler, ekstre ve profil ekranlarına yönlendiren kısa yol kartları bulunmalıdır.

### Ürün Listesi ve Detay
- Ürün listesinde, her kartta ürün adı, görseli ve müşteriye özel fiyat gösterilmelidir.
- Fiyat bilgisi, diğer metinlere göre daha belirgin şekilde sunulmalıdır.
- Detay ekranında, birim yapısı (adet/paket/koli) açık ve anlaşılır bir metinle açıklanmalıdır.

### Ekstre Ekranı
- Hareket listesi, tarih ve tutar bazlı net bir düzenle sunulmalıdır.
- Borç ve alacak hareketleri görsel olarak ayırt edilebilir şekilde tasarlanmalıdır.

### Profil Ekranı
- Firma bilgileri ve iletişim alanları sade ve okunaklı bir düzende gösterilmelidir.
- Opsiyonel şifre değişiklik alanı, güvenlik vurgusuyla birlikte konumlandırılabilir.

### Sipariş (Opsiyonel)
- Sepet yapısı, ürün listesi ile tutarlı bir tasarım diline sahip olmalıdır.
- Sipariş özeti ekranında, ara toplam ve tahmini vergi bilgileri açıkça belirtilmelidir.

---

## Admin App ve Customer App Arasındaki Görsel Ayrım
- **Admin App:** Daha yoğun bilgi içeren ekranlar, daha nötr ve profesyonel bir renk paleti ile sunulmalıdır.
- **Customer App:** Son kullanıcı odaklı olduğu için daha sade, güven veren ve okunaklı bir tasarım önceliklidir.

Her iki uygulamada da tutarlı ikon setleri, buton stilleri ve geri bildirim desenleri kullanılmalı; kullanıcı, uygulamalar arasında geçiş yaptığında benzer bir deneyim hissetmelidir.