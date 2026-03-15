# 04 – Güvenlik ve RLS Modeli

## Genel Güvenlik Prensipleri
- Tüm erişim kontrolü Supabase Auth, rol bilgisi ve Row Level Security (RLS) politikaları üzerinden sağlanır.
- Admin App ve Customer App, aynı veri tabanını kullanır ancak farklı rol ve yetki seviyeleriyle kısıtlanır.
- Varsayılan yaklaşım "en az yetki" ilkesidir; kullanıcılar yalnızca işlerini yapmaları için gereken verilere erişebilir.

---

## Rol Modeli

### Roller
- **Admin:** Yönetici ve ofis kullanıcıları; tüm ticari verileri yönetebilir.
- **Customer:** Müşteri kullanıcıları; yalnızca kendi carilerine ait verileri görebilir ve sınırlı aksiyon alabilir.

### Rol Bilgisi
- Rol bilgisi, kimlik doğrulama sistemi üzerinde kullanıcı meta verisi olarak tutulur.
- Uygulamalar, bu rol bilgisine göre giriş sonrasında kullanıcıya uygun ekranları gösterir.

---

## Yetki Matrisi (Özet)

### Admin App
- Stok tablolarında tam okuma ve yazma yetkisi.
- Cari tablolarında tam okuma ve yazma yetkisi.
- Satış, tahsilat ve ekstre tablolarında tam okuma ve yazma yetkisi.
- Kategori ve yardımcı tablolarda tam yönetim yetkisi.
- Storage alanlarında, proje kurallarına uygun olarak okuma ve yazma yetkisi.

### Customer App
- Stok tablolarında yalnızca aktif stoklar için okuma yetkisi.
- Cari tablolarında yalnızca ilişkili olduğu cari kaydı için okuma yetkisi.
- Satış, tahsilat ve ekstre tablolarında yalnızca kendi carisine ait hareketler için okuma yetkisi.
- Depolama alanlarında, proje kapsamında belirlenen içeriklere sınırlı okuma yetkisi (örneğin stok görselleri).
- Yazma yetkisi, opsiyonel sipariş veya profil güncelleme gibi belirli senaryolarla sınırlandırılır.

---

## Müşteri Verisi Kısıtları

### Genel Kural
- Customer rolüne sahip bir kullanıcı, yalnızca ilişkili olduğu cari kimliğine ait verileri görebilir.

### Uygulama
- Müşteri kullanıcılarının carileri, kullanıcı-cari ilişki tablosu üzerinden belirlenir.
- Bu ilişki, ekstre, satış, tahsilat ve benzeri tablolarda filtreleyici bir kural olarak kullanılır.
- Müşteri kullanıcısı:
  - Cari kartında yalnızca kendi kaydını görüntüleyebilir.
  - Ekstre tablosunda yalnızca kendi carisine ait hareketleri görebilir.
  - Satış ve tahsilat tablolarında da yalnızca bu cariye ait özet veya detaylara erişebilir.

---

## Admin Yetkileri

### Yönetim Erişimi
- Admin rolüne sahip kullanıcılar, ticari verilerin tamamına erişebilir.
- Stok, cari, satış, tahsilat, ekstre ve diğer operasyonel tablolarda ekleme, güncelleme ve silme işlemleri yapabilir.
- Excel içe aktarma, kategori yönetimi gibi yüksek etkili operasyonlar yalnızca admin rolü ile yürütülür.

### Sorumluluklar
- Admin kullanıcıların, RLS politikalarını değiştirme veya yapılandırma yetkisi projeye göre sınırlandırılabilir.
- Üretim ortamında yapılan yetki değişiklikleri mutlaka test ortamında doğrulandıktan sonra uygulanmalıdır.

---

## Storage Erişim Kuralları

### Stok Görselleri
- Stok görselleri için ayrı bir depolama alanı kullanılır.
- Okuma yetkisi:
  - Admin App: Tüm stok görsellerine erişebilir.
  - Customer App: Sadece aktif stokların görsellerini görüntüleyebilir.
- Yazma yetkisi:
  - Yalnızca Admin App kullanıcıları stok görsellerini ekleyebilir, güncelleyebilir veya silebilir.

### Dekont ve Belgeler
- Tahsilat dekontları ve benzeri belgeler için ayrı bir depolama alanı kullanılır.
- Okuma ve yazma yetkisi:
  - Varsayılan olarak yalnızca Admin App tarafından kullanılır.
  - Müşteri tarafına açılmak istenirse, buna yönelik ek erişim kuralları tanımlanır.

### İçe Aktarma Dosyaları
- Excel içe aktarma için kullanılan dosyalar ayrı bir depolama alanında tutulur.
- Bu alana erişim yalnızca Admin App kullanıcılarıyla sınırlandırılır.

---

## RLS Politikalarının Testi ve Doğrulama

### Test Prensipleri
- Her tablo için, admin ve müşteri rolleriyle ayrı ayrı test yapılmalıdır.
- Test senaryoları en az aşağıdakileri kapsamalıdır:
  - Müşteri kullanıcısının başka bir cariye ait veriyi görüntüleyememesi.
  - Müşteri kullanıcısının pasif stokları görememesi.
  - Admin kullanıcısının beklenen tüm kayıtlara erişebilmesi.

### Ortam Ayrımı
- RLS ve erişim politikaları önce test ortamında kurgulanmalı ve gerçekçi veri senaryolarıyla doğrulanmalıdır.
- Üretim ortamında değişiklik yapılmadan önce, test sonuçları dokümante edilmelidir.

---

## Admin App ve Customer App Açısından Güvenlik Özeti
- **Admin App:** Geniş yetki alanına sahip olduğu için, rol atamaları, parola politikaları ve erişim loglarının takibi kritik önemdedir.
- **Customer App:** Veri sızıntısını engellemek için satır seviyesinde kısıtlar titizlikle uygulanmalı; özellikle ekstre, satış ve tahsilat tabloları üzerinde müşteri bazlı filtreleme her zaman etkin olmalıdır.

Bu güvenlik ve RLS modeli, veri modeli ve iş akışları dokümanlarıyla birlikte değerlendirilerek, tutarlı ve güvenli bir sistem tasarımının parçası olarak ele alınmalıdır.