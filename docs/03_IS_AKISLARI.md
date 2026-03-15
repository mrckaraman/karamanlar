# 03 – İş Akışları

## Genel Bakış
Bu doküman, Karamanlar Ticaret projesinde Admin App ve Customer App tarafından kullanılan temel iş akışlarını tanımlar. Tüm akışlar, tek Supabase projesi üzerinde, ortak veri modeli ve rol tabanlı güvenlik kurallarıyla yürütülür.

---

## 3.1 Satış Akışı (Admin App)

### Amaç
Müşteriye yapılan bir satışın, stok bakiyesi, cari borç ve ekstre kayıtlarıyla birlikte tek seferde ve tutarlı şekilde oluşturulması.

### Adımlar
1. Kullanıcı Admin App üzerinden giriş yapar.
2. Satış oluşturma ekranında cari seçimi yapılır:
   - Sadece aktif cariler listelenir.
   - Carinin limit, vade ve mevcut borç bilgileri özet olarak gösterilir.
3. Satır ekleme aşamasında:
   - Ürün, ad/kod/barkod ile aranarak seçilir.
   - Birim türü (adet, paket, koli) seçilir.
   - Miktar girilir.
4. Sistem, seçili carinin fiyat tipi değerini okur.
5. Stok kartındaki fiyat alanlarından, carinin fiyat tipine karşılık gelen satış fiyatı birim fiyat olarak alınır.
6. Birim türüne göre parça adedi hesaplanır ve satıra yansıtılır.
7. Tüm satırlar için ara toplam ve vergi toplamı hesaplanır; belge toplamı hazırlanır.
8. Kayıt öncesi limit ve vade kontrolü yapılır:
   - Limit aşımı veya vade aşımı varsa, sistem yapılandırmaya göre uyarı verir veya işlemi engeller.
9. İşlem onaylandığında, tek bir bütün işlem kapsamında şu adımlar gerçekleşir:
   - Satış üst bilgisi (header) kaydedilir.
   - Satış satırları kaydedilir.
   - İlgili stokların bakiyesi düşürülür.
   - İlgili carinin borç bakiyesi artırılır.
   - Ekstre tablosuna satış için borç hareketi eklenir.
10. Kullanıcıya satışın başarıyla tamamlandığı bilgisi gösterilir ve gerekirse satış özeti ekranda sunulur.

---

## 3.2 Tahsilat Akışı (Admin App)

### Amaç
Müşteriden alınan bir ödemenin kaydedilmesi, cari bakiyesinin güncellenmesi ve ekstrede alacak hareketi oluşması.

### Adımlar
1. Kullanıcı Admin App üzerinden giriş yapar.
2. Tahsilat oluşturma ekranında cari seçimi yapılır.
3. Tahsilat bilgileri girilir:
   - Tarih.
   - Tutar.
   - Ödeme yöntemi (nakit, transfer, eft, kart vb.).
   - Açıklama.
4. Opsiyonel olarak dekont veya belge yüklenir ve Storage üzerinde ilgili alana kaydedilir.
5. İşlem onaylandığında:
   - Tahsilat kaydı oluşturulur.
   - İlgili carinin borç bakiyesi, tahsilat tutarı kadar azaltılır.
   - Ekstre tablosuna alacak hareketi olarak bir kayıt eklenir.
6. Kullanıcıya tahsilatın başarıyla tamamlandığı bilgisi gösterilir.

---

## 3.3 Cari ve Stok Yönetimi Akışları (Admin App)

### Cari Kart Oluşturma / Güncelleme
1. Kullanıcı Admin App üzerinden "Yeni Cari" veya mevcut cari üzerinde "Düzenle" aksiyonunu seçer.
2. Cari temel bilgiler, vergi bilgileri, adres ve iletişim bilgileri girilir veya güncellenir.
3. Finansal koşullar (vade, limit, fiyat tipi) tanımlanır.
4. Cari aktif/pasif durumu belirlenir.
5. Kayıt onaylandığında, cari kartı kaydedilir ve raporlarda kullanılabilir hale gelir.

### Stok Kart Oluşturma / Güncelleme
1. Kullanıcı Admin App üzerinden "Yeni Stok" veya mevcut stok üzerinde "Düzenle" aksiyonunu seçer.
2. Ürün adı, kodu, kategori, vergi oranı, marka ve fiyatlar girilir veya güncellenir.
3. Birim yapısı (adet/paket/koli) ve ilgili barkodlar tanımlanır.
4. Stok aktif/pasif durumu belirlenir.
5. Opsiyonel olarak ürün görseli Storage üzerine yüklenir ve stok kartına bağlanır.
6. Kayıt onaylandığında stok kartı kullanılabilir hale gelir; pasif stoklar sadece yönetim amaçlı listelenir.

---

## 3.4 Excel İçe Aktarma Akışı (Stok – Admin App)

### Amaç
Tedarikçi veya iç sistemlerden alınan stok listesinin, Excel dosyası üzerinden topluca içe aktarılması.

### Adımlar
1. Kullanıcı Admin App’te Excel içe aktarma ekranını açar.
2. Excel dosyası seçilir ve Storage üzerinde ilgili alana yüklenir.
3. Sistem dosyayı okur ve satırları önizleme ekranında gösterir.
4. Zorunlu alanlar (stok kodu, stok adı) ve temel iş kuralları kontrol edilir.
5. Hata tespiti durumunda:
   - Her hatalı satır için satır numarası, ilgili alan ve hata mesajı listelenir.
   - Kullanıcı hata raporunu inceleyip dosyayı düzelterek tekrar yükleyebilir.
6. Hatasız veya kabul edilebilir seviyede hataya sahip satırlar için içe aktarma onayı alınır.
7. Onay sonrasında:
   - Yeni stoklar eklenir.
   - Mevcut stoklar güncellenir.
   - Birim ve barkod bilgileri de aynı süreçte yönetilir.
8. Özet sonuç (eklenen ve güncellenen kayıt sayıları, hatalı satır sayısı) kullanıcıya gösterilir.

---

## 3.5 Ürün Görüntüleme Akışı (Customer App)

### Amaç
Müşterinin sadece aktif stokları, kendi fiyat tipi üzerinden hesaplanan fiyatlarla görebilmesini sağlamak.

### Adımlar
1. Kullanıcı Customer App üzerinden giriş yapar.
2. Sistem, kullanıcının ilişkili olduğu cari kaydını belirler.
3. Ürünler ekranı açıldığında:
   - Sadece aktif stoklar listelenir.
   - Her stok için müşteriye özel tek satış fiyatı hesaplanır ve gösterilir.
4. Kullanıcı arama veya filtreler ile listeyi daraltabilir.
5. Bir ürün seçildiğinde ürün detay ekranı açılır:
   - Ürün bilgileri, görseli ve birim yapısı gösterilir.
   - Müşteriye özel fiyat net biçimde vurgulanır.

---

## 3.6 Ekstre Görüntüleme Akışı (Admin ve Customer)

### Admin App
1. Kullanıcı Admin App üzerinden giriş yapar.
2. Cari listesi ekranında bir cari seçilir.
3. Cari detay ekranında ekstre sekmesi açılır.
4. Seçili cari için tüm borç ve alacak hareketleri tarihsel olarak listelenir.
5. Filtreler ve sıralama ile detay analiz yapılabilir.

### Customer App
1. Kullanıcı Customer App üzerinden giriş yapar.
2. Ekstre ekranı açıldığında sistem, kullanıcının ilişkili olduğu cari kimliğini kullanır.
3. Sadece bu cariye ait satış ve tahsilat hareketleri gösterilir.
4. Kullanıcı tarih aralığı veya işlem türüne göre filtreleme yapabilir.

---

## 3.7 Sipariş Akışı (Opsiyonel – Customer App)

### Amaç
Müşterinin, ürünlerden sepet oluşturarak sipariş talebinde bulunmasını sağlamak.

### Adımlar
1. Kullanıcı Customer App üzerinden ürünler ekranına girer.
2. İlgili ürünleri sepetine ekler ve miktarları belirler.
3. Sepet ekranında sipariş özeti görüntülenir (ara toplam, tahmini vergi ve toplam tutar bilgileri).
4. Kullanıcı siparişi onaylar.
5. Sistem siparişi kaydeder ve yönetici tarafında işlenmek üzere uygun bir yapıya yönlendirir.
6. Admin App tarafında bu siparişler, satışa dönüştürülebilir veya onay/red süreçlerinden geçirilebilir.

---

## 3.8 Giriş ve Oturum Yönetimi Akışları

### Admin App
1. Kullanıcı e-posta ve şifre ile giriş formunu doldurur.
2. Supabase Auth üzerinden kimlik doğrulama yapılır.
3. Kullanıcının rol bilgisi kontrol edilir; admin rolüne sahip değilse Admin App erişimi reddedilir.
4. Başarılı giriş sonrası, dashboard ekranı açılır.

### Customer App
1. Kullanıcı e-posta ve şifre ile giriş formunu doldurur.
2. Supabase Auth üzerinden kimlik doğrulama yapılır.
3. Kullanıcının rol bilgisi ve ilişkili cari kaydı kontrol edilir.
4. Başarılı giriş sonrası, anasayfa ekranı açılır; borç, limit ve vade bilgileri özet olarak gösterilir.

---

## Admin App ve Customer App Açısından İş Akışlarının Ayrımı
- **Admin App:** İş akışları, veri oluşturma, güncelleme ve raporlama ağırlıklıdır; stok, cari, satış, tahsilat ve raporlar üzerinde tam kontrol sağlar.
- **Customer App:** İş akışları, ağırlıklı olarak veri görüntüleme ve sınırlı aksiyon (sipariş talebi, profil güncelleme gibi) odaklıdır; müşteri yalnızca kendi verileri üzerinde işlem yapabilir.

Bu iş akışları, veri modeli ve güvenlik kurallarıyla birlikte uygulandığında, projenin iş kurallarına uygun ve tutarlı bir çalışma modeli sağlar.