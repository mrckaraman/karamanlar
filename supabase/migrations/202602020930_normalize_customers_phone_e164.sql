-- customers.phone alanını E.164 (+90XXXXXXXXXX) formatına normalize et ve constraint ekle.
-- Bu migration'ı çalıştırmadan önce mutlaka yedek al.

-- 1) Geçici olarak normalize edilmiş telefon tutmak için kolon ekle (opsiyonel)
-- alter table customers add column phone_e164_tmp text;

-- 2) Türkiye için basit normalize fonksiyon mantığı (örnek):
--    - Başında + yoksa +90 ekle
--    - 0 ile başlıyorsa 0'ı at ve +90 ekle
--    - Aradaki boşluk, tire vb. karakterleri kaldır
-- NOT: Üretim ortamında bu mantık, backend'deki normalizeTrPhone ile aynı olmalı.

update customers
set phone =
  case
    when phone is null or trim(phone) = '' then null
    else (
      -- tüm boşluk ve tireleri kaldır
      '+90' || right(regexp_replace(phone, '[^0-9]', '', 'g'), 10)
    )
  end;

-- 3) Boş olmayan telefonların gerçekten +90 ve 10 hane ile uyumlu olduğunu doğrula
--    Hatalı kayıtlar varsa önce düzelt, sonra constraint ekle.
-- select id, phone from customers where phone is not null and phone !~ '^\+90[0-9]{10}$';

-- 4) Gelecekte girilecek verileri güvenceye almak için check constraint ekle
alter table customers
  add constraint customers_phone_e164_ck
  check (phone is null or phone ~ '^\+90[0-9]{10}$');
