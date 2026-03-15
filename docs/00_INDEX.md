# Karamanlar Ticaret Dokümantasyon Index

## Amaç
Bu dokümantasyon seti, Karamanlar Ticaret projesinin kapsamını, veri modelini, iş akışlarını ve güvenlik modelini net ve tutarlı şekilde tanımlamak için hazırlanmıştır. Tüm içerik, yalnızca Supabase altyapısı kullanılan iki mobil uygulamanın (Admin App ve Customer App) gereksinimlerini açıklamaya odaklanır.

## Mimari Genel Bakış
- **Tek arka uç:** Supabase (Auth, Postgres, Storage ve gerekirse Edge Functions)
- **Admin App:** Yönetici ve ofis kullanıcıları için; stok, cari, satış, tahsilat, ekstre, rapor ve Excel içe aktarma süreçlerini yönetir.
- **Customer App:** Müşteriler için; giriş, kendi fiyatlarıyla ürün görüntüleme, ekstre inceleme, opsiyonel sipariş oluşturma ve profil yönetimini sağlar.

Her doküman, hem Admin App hem de Customer App perspektifini açık biçimde ayırarak ele alır.

## Doküman Listesi
- **00_INDEX:** Bu index dokümanı; genel bakış, mimari özet ve diğer dokümanlara yönlendirme sağlar.
- **01_UYGULAMA_KAPSAMI:** Admin App ve Customer App için ekran bazlı fonksiyonel kapsamı ve kullanım senaryolarını tanımlar.
- **02_VERI_MODELI_SPEK:** Supabase Postgres üzerinde kurgulanan kategoriler, stoklar, cariler, satış, tahsilat ve ekstre tablolarının konsept modelini ve alan seviyesindeki iş kurallarını açıklar.
- **03_IS_AKISLARI:** Satış, tahsilat, ürün görüntüleme, ekstre görüntüleme ve Excel içe aktarma gibi kritik süreçlerin uçtan uca iş akışlarını tarif eder.
- **04_GUVENLIK_RLS:** Rol modeli, yetki matrisi, müşteri verisi kısıtları ve Storage erişim kuralları dahil olmak üzere tüm güvenlik ve RLS prensiplerini özetler.
- **05_EDGE_FUNCTIONS_GEREKSINIM:** Satış, tahsilat ve stok Excel içe aktarma için kullanılacak Edge Functions fonksiyonel gereksinimlerini tanımlar.
- **06_UI_TEMA_GUIDE:** Admin App ve Customer App için tutarlı bir kullanıcı deneyimi sunmak amacıyla tema, bileşen ve ekran düzeyinde UI prensiplerini açıklar.

## Hedef Kitle
- **Ürün sahibi / iş analisti:** Kapsam, iş kuralları ve yol haritasını anlamak için özellikle 01, 03 ve 06 numaralı dokümanları kullanır.
- **Backend / Supabase uzmanı:** Veri modeli, güvenlik ve Edge Functions gereksinimleri için 02, 04 ve 05 numaralı dokümanları referans alır.
- **Mobil geliştiriciler (Flutter):** Ekran kapsamı, iş akışları ve UI kılavuzu için 01, 03 ve 06 numaralı dokümanları takip eder.

## Kullanım Önerisi
1. Önce bu index dokümanını okuyarak genel resme hakim olun.
2. Uygulama kapsamı ve veri modeli için sırasıyla 01 ve 02 numaralı dokümanlara geçin.
3. Akabinde 03 ve 04 numaralı dokümanlarla iş akışları ve güvenlik kısıtlarını netleştirin.
4. Edge Functions veya benzeri sunucu tarafı mantık planlanıyorsa 05 numaralı dokümanı ayrıntılı inceleyin.
5. Son olarak, ekran tasarımı ve uygulama görünümü için 06 numaralı UI tema rehberini kullanın.

## Bozuk Stoklar Özelliği (Özet)
- Admin uygulamasında "Bozuk Stoklar" ekranı, public.v_invalid_stocks view'inden beslenerek barkodu olup paket/koli katsayısı eksik stokları raporlar.
- stock_units.pack_qty / box_qty alanları NULL veya >= 1 olacak şekilde tasarlanmış, bozuk kayıtlar bu view üzerinden hızlıca tespit edilir.
- Detaylı kurallar ve RLS davranışı için veri modeli (02) ve güvenlik (04) dokümanlarına bakılmalıdır.