00_README.md
Amaç

İki ayrı mobil uygulama (Admin + Müşteri) yalnızca Supabase kullanarak çalışacak:

Supabase Auth (rol yönetimi)

Supabase Postgres (veri)

Supabase Storage (stok resmi / dekont / excel)

(Opsiyon) Supabase Edge Functions (Excel import + satış/tahsilat transaction)

Uygulamalar

Admin App

Stok, cari, satış, tahsilat, ekstre, rapor, excel import

Müşteri App

Giriş, ürünler (kendi fiyatı), ekstre, sipariş (opsiyon), profil

Kritik Kurallar

Fiyatlandırma: cari kartındaki price_tier (1..4) → stok kartındaki sale_price_1..4’ten otomatik seçilir.

Birim dönüşümü: satış satırında adet/paket/koli girilir → otomatik qty_in_pieces hesaplanır.

Satış kaydı oluşunca otomatik:

stok düşer

cari borçlanır

ekstre (ledger) oluşur

Tahsilat girilince:

cari borç düşer

ekstre güncellenir

Limit/vade kontrolü: “uyar” veya “engelle” modu (patron modu).

01_UYGULAMA_KAPSAMI.md
Admin App Ekranları

Login

Dashboard (özet kartlar + hızlı aksiyonlar + uyarılar)

Stoklar: liste/filtre/arama (ad, kod, barkod), aktif/pasif

Stok formu: full stok kartı alanları + resim yükleme

Excel içe aktarma: önizleme + hata raporu + upsert

Cariler: liste/arama, aktif/pasif

Cari formu: full cari kart alanları

Cari detay: ekstre + limit/vade + satış/tahsilat kısayolları

Satış oluştur: cari seç → ürün satırları → birim dönüşümü → fiyat otomatik → kaydet

Tahsilat oluştur: cari seç → ödeme tipi → tutar → kaydet

Raporlar:

stok raporu

cari borç raporu

vade raporu

fiyat tipi kullanım raporu

Müşteri App Ekranları

Login

Anasayfa: borç/limit/vade durumu + hızlı menü

Ürünler: sadece aktif stoklar, müşteri fiyatına göre gösterim

Ürün detay: fiyat + birimler (adet/paket/koli bilgisi)

Ekstre: sadece kendi hareketleri

Profil: firma bilgisi, iletişim, şifre değişimi (opsiyon)

Sipariş (opsiyon): sepet + sipariş gönder + geçmiş

02_VERI_MODELI_SPEK.md
2.1 Kategori (Grup/Ara/Alt)

Amaç: stok ve cari için ortak kategori ağacı (tree).

Alanlar:

id (uuid, pk)

name (text)

parent_id (uuid, nullable, self-fk)

level (int, 0/1/2 opsiyon)

created_at (timestamptz)

Kural:

level=0 → Grup

level=1 → Ara Grup

level=2 → Alt Grup

2.2 Stok

Alanlar (full paket):

name

code (unique)

barcode (opsiyon)

category_id (fk categories)

special_code_1

tax_rate

brand

is_active

image_path (storage)

purchase_price

sale_price_1

sale_price_2

sale_price_3

sale_price_4

Birim & Barkod Yapısı

Ayrı tablo: stock_units

stock_id (pk, fk stocks)

unit_piece_barcode

unit_pack_barcode

unit_case_barcode

pack_contains_piece (int)

case_contains_piece (int)

Kural:

qty_in_pieces hesaplama:

piece: qty_in_pieces = qty_input

pack: qty_in_pieces = qty_input * pack_contains_piece

case: qty_in_pieces = qty_input * case_contains_piece

2.3 Cari (Müşteri)

Alanlar:

customer_code (unique)

full_name

trade_name

category_id (opsiyon)

special_code

tax_office

tax_no

tc_no

address (il/ilçe/detay)

phone

email

due_days (vade)

limit_amount

price_tier (1..4)

is_active

Not:

Login için supabase auth user ile eşleştirme gerekir.

2.4 Auth Eşleştirme

Tablo: customer_users

user_id (auth.users.id)

customer_id (customers.id)

Kural:

role=customer olan kullanıcılar yalnızca kendi customer_id verisini görebilir.

2.5 Satış

sales (header)

customer_id

sale_date

sale_type: cash/credit/partial

subtotal, tax_total, total

created_by

sale_lines (lines)

sale_id

stock_id

unit_type: piece/pack/case

qty_input

qty_in_pieces

unit_price

tax_rate

line_total

Fiyat Kuralı:

unit_price = stocks.sale_price_{customers.price_tier}

2.6 Tahsilat

payments

customer_id

pay_date

method: cash/transfer/eft/card

amount

note

receipt_path

created_by

2.7 Ekstre (Ledger)

ledger_entries

customer_id

entry_date

entry_type: sale/payment/adjustment

ref_table (sales/payments)

ref_id

debit

credit

note

Kural:

Satış → debit artar

Tahsilat → credit artar

2.8 Stok Bakiyesi (önerilir)

stock_balances

stock_id (pk)

qty_in_pieces

updated_at

03_IS_AKISLARI.md
3.1 Satış Akışı (Admin)

Cari seçilir

Sistem cari.price_tier okur

Ürün satırları eklenir:

ürün seç (ad/kod/barkod)

birim seç (adet/paket/koli)

miktar gir

qty_in_pieces otomatik

fiyat otomatik (tier)

Limit/vade kontrol:

limit aşımı → uyar veya engelle

vade geçmiş → uyar veya engelle

Kaydet:

sales + sale_lines yaz

stock_balances düş

ledger_entries debit yaz

3.2 Tahsilat Akışı (Admin)

Cari seç

ödeme yöntemi seç

tutar gir

Kaydet:

payments yaz

ledger_entries credit yaz

3.3 Müşteri Ürün Görüntüleme

sadece is_active=true olan stoklar gösterilir

fiyat: customer.price_tier’a göre tek fiyat olarak sunulur

3.4 Ekstre Görüntüleme

admin: tüm cariler

müşteri: sadece kendi carisi

3.5 Excel İçe Aktarma (Stok)

excel upload → parse/validate → upsert

zorunlu: code, name

opsiyon: fiyatlar, barkodlar, birim dönüşümleri, kategori, marka, aktif/pasif

Hata raporu:

satır no + alan + hata mesajı

04_GUVENLIK_RLS.md
Rol modeli

Supabase Auth kullanıcılarında:

app_metadata.role = "admin" | "customer"

Customer veri kısıtı

Customer kullanıcı:

customer_users üzerinden bağlı olduğu customer_id’yi görür

customers: yalnız kendi kaydı

ledger_entries: yalnız kendi hareketleri

sales/sale_lines/payments: yalnız kendi kayıtları (opsiyon; ister sadece özet)

Admin yetkileri

Admin:

tüm tablolarda full CRUD

Storage erişimi

stock-images: herkes read, sadece admin write

receipts: sadece admin write/read (müşteriye açmak istersen policy eklenir)

imports: sadece admin

Not

RLS yanlış yapılırsa veri sızıntısı olur. Policy’ler test edilmeden yayın yapılmaz.

05_EDGE_FUNCTIONS_GEREKSINIM.md

Kod yazılmayacak; Copilot ile üretilecek.

Fonksiyon: create_sale

Girdi:

customer_id

lines[]: { stock_id, unit_type, qty_input }

İş:

customer.price_tier oku

her line için:

unit conversion → qty_in_pieces

price selection → sale_price_{tier}

tax/total hesapla

tek transaction:

sales insert

sale_lines insert

stock_balances update (düş)

ledger_entries insert (debit)

limit/vade kontrol:

app_settings’e göre warn/block

Çıktı:

sale_id

warning[] (varsa)

Fonksiyon: create_payment

Girdi:

customer_id, amount, method, note, receipt_path?
İş:

payments insert

ledger_entries credit insert
Çıktı:

payment_id

Fonksiyon: import_stocks_excel

Girdi:

storage path (excel dosyası)
İş:

dosya parse

validate

upsert stocks + stock_units + category match/create opsiyon
Çıktı:

inserted_count, updated_count

errors[] (row, message)

06_UI_TEMA_GUIDE.md
Genel

Kart tabanlı tasarım

Büyük sayılar (₺, borç, toplam) için monospace

Minimal çizgi, bol boşluk

Admin Dashboard

KPI kartları: Bugün satış / Tahsilat / Kritik stok / Vade geçen cari

Hızlı aksiyonlar: Satış, Tahsilat, Stok ekle, Cari ekle

Uyarılar listesi

Müşteri Anasayfa

Borç / Limit / Vade durumu kartı

“Sana özel fiyat” vurgusu

Ürünler → hızlı erişim

Dosya yapısı önerisi (repo)

docs/00_README.md

docs/01_UYGULAMA_KAPSAMI.md

docs/02_VERI_MODELI_SPEK.md

docs/03_IS_AKISLARI.md

docs/04_GUVENLIK_RLS.md

docs/05_EDGE_FUNCTIONS_GEREKSINIM.md

docs/06_UI_TEMA_GUIDE.md

Bu seti Copilot’a verdiğinde çok temiz üretim alırsın: hem Supabase şema/policy, hem Flutter ekranları.