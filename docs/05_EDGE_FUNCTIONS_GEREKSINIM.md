# 05 – Edge Functions Gereksinimleri

## Genel Bakış
Bu doküman, Karamanlar Ticaret projesinde kullanılacak sunucu tarafı fonksiyonların fonksiyonel gereksinimlerini tanımlar. Tüm fonksiyonlar, tek bir işlem kapsamında birden fazla tabloyu güncelleyerek veri tutarlılığını sağlar.

Hedeflenen ana fonksiyonlar:
- Satış oluşturma fonksiyonu.
- Tahsilat oluşturma fonksiyonu.
- Stok Excel içe aktarma fonksiyonu.

Admin App bu fonksiyonları yoğun biçimde kullanırken, Customer App doğrudan bu fonksiyonlara erişmez; ancak dolaylı olarak (örneğin sipariş taleplerinin satışa dönüşmesi gibi) çıktılarından etkilenir.

---

## 5.1 Satış Oluşturma Fonksiyonu

### Amaç
Tek bir istek ile satış belgesi, satış satırları, stok bakiyesi ve ekstre kayıtlarının tutarlı şekilde oluşturulmasını sağlamak.

### Girdi
- Müşteri kimliği.
- Satır listesi:
  - Stok kimliği.
  - Birim türü (adet, paket, koli gibi sınırlı kümeden bir değer).
  - Girilen miktar.

### Ana İş Adımları
1. Müşteri kartı okunur ve fiyat tipi değeri belirlenir.
2. Her satır için:
   - Seçilen stok kartı okunur.
   - Birim türüne göre parça adedi hesaplanır.
   - Müşterinin fiyat tipine göre ilgili satış fiyatı belirlenir.
   - Satır bazında vergi ve satır toplamı hesaplanır.
3. Tüm satırlar üzerinden ara toplam, vergi toplamı ve genel toplam elde edilir.
4. Limit ve vade kontrolü yapılır:
   - Müşterinin tanımlı limiti ve vade gün sayısı ile mevcut borç durumu değerlendirilir.
   - Sistem ayarlarına göre ya uyarı üretir (işleme izin vererek) ya da işlemi engeller.
5. İşlem devam edecekse, tek bir işlem kapsamında:
   - Satış üst bilgisi kaydedilir.
   - Satış satırları kaydedilir.
   - İlgili stokların bakiyesi, parça adedi üzerinden güncellenir.
   - Müşterinin borç bakiyesi artırılır.
   - Ekstre tablosuna borç hareketi eklenir.

### Çıktı
- Oluşan satışın kimliği.
- Varsa, limit ve vade ile ilgili uyarı listesi.

### Admin App ve Customer App Açısından
- **Admin App:** Satış oluşturma ekranı bu fonksiyonu doğrudan kullanır.
- **Customer App:** Doğrudan satış kaydı oluşturmaz; ancak opsiyonel sipariş modülü, yöneticilerin bu fonksiyonla satışa dönüştürebileceği sipariş talepleri üretir.

---

## 5.2 Tahsilat Oluşturma Fonksiyonu

### Amaç
Müşteriden alınan tahsilatın tek adımda kaydedilmesi, cari bakiyesinin güncellenmesi ve ekstrede alacak hareketi oluşturulması.

### Girdi
- Müşteri kimliği.
- Tutar.
- Ödeme yöntemi (nakit, transfer, eft, kart gibi sınırlı kümeden bir değer).
- Açıklama.
- Opsiyonel dekont yolu (varsa önceden yüklenmiş belge).

### Ana İş Adımları
1. Müşteri kartı okunur ve pasif durumda olup olmadığı kontrol edilir.
2. Gerekirse, tahsilat için belirlenmiş işletme kuralları (örneğin belirli müşteriler için kısıtlar) uygulanır.
3. Tek bir işlem kapsamında:
   - Tahsilat kaydı oluşturulur.
   - Müşterinin borç bakiyesi tahsilat tutarı kadar azaltılır.
   - Ekstre tablosuna alacak hareketi eklenir.

### Çıktı
- Oluşan tahsilatın kimliği.

### Admin App ve Customer App Açısından
- **Admin App:** Tahsilat oluşturma ekranı bu fonksiyonu doğrudan tetikler.
- **Customer App:** Müşteri tarafında doğrudan tahsilat kaydı yapılmaz; ancak ileride dekont görüntüleme veya tahsilat özetleri açısından bu fonksiyonun ürettiği verilerden faydalanılır.

---

## 5.3 Stok Excel İçe Aktarma Fonksiyonu

### Amaç
Stok kartlarının ve ilgili birim/barkod bilgilerinin, Excel dosyasından topluca içe aktarılması.

### Girdi
- Depolama alanında bulunan Excel dosyasının yolu.

### Ana İş Adımları
1. Dosya okunur ve satırlar ayrıştırılır.
2. Her satır için zorunlu alanlar kontrol edilir (stok kodu, stok adı gibi).
3. Alan bazlı iş kuralları uygulanır (örneğin fiyatların pozitif olması, vergi oranı aralığı gibi).
4. Hatalı satırlar için hata detayları hazırlanır:
   - Satır numarası.
   - Hatalı alan veya alanlar.
   - Hata açıklaması.
5. Hatasız ve kabul edilen satırlar için, tek bir işlem kapsamında:
   - Yeni stok kartları eklenir.
   - Mevcut stok kartları güncellenir.
   - İlgili birim ve barkod bilgileri de güncellenir veya eklenir.
6. Sonuç özeti hazırlanır:
   - Eklenen kayıt sayısı.
   - Güncellenen kayıt sayısı.
   - Hatalı satır sayısı ve hata listesi.

### Çıktı
- Eklenen stok sayısı.
- Güncellenen stok sayısı.
- Hata listesi (satır numarası ve mesaj içeren).

### Admin App ve Customer App Açısından
- **Admin App:** Excel içe aktarma ekranı bu fonksiyonu doğrudan kullanır ve sonuç raporunu kullanıcıya gösterir.
- **Customer App:** Bu fonksiyonun çıktılarından dolaylı olarak faydalanır; güncellenen stok ve fiyatlar, müşteri tarafındaki ürün listelerinde yansır.

---

## Ortak Gereksinimler ve Hata Yönetimi

### İşlem Bütünlüğü
- Her fonksiyon, ilgili tüm tablo güncellemelerini tek bir bütün işlem altında yürütmelidir.
- Kısmi güncellemeler engellenmeli; hata durumunda tüm değişiklikler geri alınmalıdır.

### Hata ve Uyarı Mesajları
- Fonksiyonlar, iş kuralı ihlallerinde açık ve son kullanıcıya dönüştürülebilir hata mesajları üretmelidir.
- Özellikle limit ve vade kontrollerinde, satışın devam edip etmeyeceği net bir şekilde belirtilmelidir.

### Kayıt ve İzlenebilirlik
- Kritik fonksiyon çağrıları, izleme ve sorun giderme amacıyla kayıt altına alınmalıdır.
- Gerekirse, kim tarafından ne zaman hangi müşteri için işlem yapıldığı bilgisi saklanmalıdır.

Bu gereksinimler, veri modeli ve güvenlik dokümanlarıyla birlikte değerlendirilerek, tutarlı bir sunucu tarafı işlem modeli oluşturur.

---

## 5.4 Müşteri Kullanıcısı Oluşturma Fonksiyonu (`create_customer_user`)

### Amaç
Admin panelinden, service role anahtarını client tarafına sızdırmadan, belirli bir cari kaydı için müşteri uygulaması kullanıcısı oluşturmaktır.

Fonksiyon:
- Supabase Auth üzerinde kullanıcıyı oluşturur.
- `app_metadata` içine rol ve `customer_id` bilgisini yazar.
- `public.customer_users` tablosunda eşleştirme kaydını oluşturur.
- Hata durumlarında anlamlı ve makine tarafından ayırt edilebilir bir cevap döner.

### HTTP Endpoint

- Yöntem: `POST`
- Yol: `/functions/v1/create_customer_user`
- İçerik tipi: `application/json`

### İstek (Request) Body Sözleşmesi

```jsonc
{
   "customer_id": "<uuid>",        // Zorunlu, public.customers.id
   "email": "user@example.com",   // Zorunlu, Supabase Auth email
   "initial_password": "..."      // Opsiyonel veya projeye göre zorunlu
}
```

Alanlar:
- `customer_id` (uuid, zorunlu)
   - İlgili cari kaydının `customers.id` değeri.
- `email` (string, zorunlu)
   - Supabase Auth kullanıcı email'i.
   - Temel format kontrolü yapılmalı (en azından `@` içermeli).
- `initial_password` (string, opsiyonel/zorunlu)
   - Eğer fonksiyon şifreyi kendisi üretmeyecekse zorunlu; aksi halde boş bırakılabilir ve fonksiyon random bir şifre üretebilir.

### Başarılı Yanıt (Response) Sözleşmesi

```jsonc
{
   "ok": true,
   "auth_user_id": "<uuid>",      // Oluşturulan auth.users.id
   "customer_id": "<uuid>",       // Gelen customer_id ile aynı
   "email": "user@example.com",   // Oluşturulan kullanıcının email'i
   "initial_password": "..."      // Opsiyonel; sadece test/dev ortamında dönebilir
}
```

Notlar:
- `initial_password` alanı prod ortamında **dönmeyebilir**. Bu nedenle client tarafı bu alanı opsiyonel kabul etmelidir.
- Admin paneli, test ortamında dönen şifreyi sadece tek seferlik olarak gösterecek şekilde tasarlanmalıdır.

### Hata Yanıtı Sözleşmesi

Tüm hata durumlarında fonksiyon şu yapıda bir yanıt döner:

```jsonc
{
   "ok": false,
   "error": "Anlamlı hata mesajı",
   "code": "SOME_ERROR_CODE"      // Opsiyonel ama tavsiye edilir
}
```

Önerilen hata kodları:
- `INVALID_PAYLOAD`
   - Eksik/zorunlu alanlar (customer_id, email, initial_password) veya geçersiz format.
- `EMAIL_ALREADY_EXISTS`
   - Aynı email ile zaten bir Auth kullanıcısı varsa ve bu durum iş kuralı gereği engelleniyorsa.
- `CUSTOMER_ALREADY_LINKED`
   - Aynı `customer_id` zaten `customer_users` tablosunda bir kullanıcıya bağlı ise.
- `AUTH_CREATE_FAILED`
   - `auth.admin.createUser` çağrısı başarısız olduğunda.
- `DB_INSERT_FAILED`
   - `customer_users` insert/transaction kısmında hata olduğunda.
- `UNEXPECTED_ERROR`
   - Diğer beklenmeyen hatalar.

### İş Kuralları ve Akış

1. **Girdi doğrulama**
    - `customer_id` boş veya geçersiz uuid ise → `ok:false`, `code: "INVALID_PAYLOAD"`.
    - `email` boş veya format olarak bariz hatalı ise → `ok:false`, `code: "INVALID_PAYLOAD"`.
    - Proje kararına göre `initial_password` zorunlu ise ve boş ise → `ok:false`, `code: "INVALID_PAYLOAD"`.

2. **Tekillik kontrolleri**
    - `auth.users` üzerinde aynı `email` ile kayıt varsa ve yeniden kullanmak istenmiyorsa:
       - `ok:false`, `code: "EMAIL_ALREADY_EXISTS"`.
    - `public.customer_users` tablosunda aynı `customer_id` için zaten bir satır varsa:
       - `ok:false`, `code: "CUSTOMER_ALREADY_LINKED"`.

3. **Auth kullanıcısının oluşturulması**
    - `auth.admin.createUser({...})` çağrısı ile kullanıcı oluşturulur:
       - `email`
       - `password` (gelen `initial_password` veya fonksiyon içinde üretilen değer)
       - `email_confirm: true`
       - `app_metadata: { "role": "customer", "customer_id": "<customer_id>" }`
    - Başarısız olursa:
       - `ok:false`, `code: "AUTH_CREATE_FAILED"`, `error` alanında Supabase mesajı özetlenir.

4. **customer_users kaydının oluşturulması**
    - Tek bir transaction içinde:
       - `public.customer_users` tablosuna satır eklenir:
          - `customer_id`: istekten gelen değer
          - `auth_user_id`: `auth.admin.createUser` sonucundaki `user.id`
          - `email`: istekten gelen email
    - Hata durumunda, auth kullanıcısı ile customer_users ilişkisinin yarım kalmaması için gerekli rollback/temizlik stratejisi belirlenmelidir.

5. **Başarılı yanıt**
    - İşlemlerin tamamı başarılı ise:
       - `ok:true`
       - `auth_user_id`, `customer_id`, `email` alanları doldurulur.
       - Test/dev ortamlarında (veya feature flag ile) `initial_password` alanı da yanıt içinde dönebilir.

### Admin ve Customer App Açısından

- **Admin App**
   - `CustomerFormPage` içinde "Müşteri Kullanıcısı Oluştur" butonu bu fonksiyona `customer_id`, `email` ve gerekirse `initial_password` ile istek yapar.
   - Başarılı yanıtta:
      - Snackbar ile "Müşteri kullanıcısı oluşturuldu." mesajı gösterilir.
      - Test ortamında dönen `initial_password` değeri tek seferlik bir dialog ile admin'e gösterilebilir.

- **Customer App**
   - Kayıt ekranı yoktur; sadece `signInWithPassword(email, password)` ile giriş yapar.
   - Sipariş ve diğer işlemlerde RLS, JWT içindeki `app_metadata.customer_id` bilgisine göre çalışır.