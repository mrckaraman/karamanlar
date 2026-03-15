# Supabase / Customers Telefon Testleri

Müşteri girişindeki telefon OTP akışını test ederken `customers.phone` alanındaki formatı doğrulamak için aşağıdaki sorguları Supabase SQL Editor üzerinden çalıştır.

```sql
-- Belirli bir E.164 telefon numarası için bire bir kontrol
select id, phone
from customers
where phone = '+90XXXXXXXXXX';

-- Son 10 haneye göre (ülke kodu farklı veya boş kayıtları yakalamak için)
select id, phone
from customers
where phone ilike '%XXXXXXXXXX%';
```

Burada `+90XXXXXXXXXX` ve `XXXXXXXXXX` yerlerine uygulamada `normalizeTrPhone` sonrasında loglanan `phoneE164` ve son 10 hanesini koyarak kayıtların gerçekten E.164 formatında tutulup tutulmadığını kontrol edebilirsin.

## check_customer_email / check_customer_phone Fonksiyon Testleri

Aşağıdaki sorgular, doğru fonksiyon gövdesinin yüklendiğini ve her zaman tek satır ("exists", is_active) döndüğünü doğrulamak için kullanılabilir.

```sql
-- Fonksiyon tanımını kontrol et
select pg_get_functiondef('public.check_customer_email(text)'::regproc);

-- Var olan bir e-posta için exists/is_active değerlerini kontrol et
select *
from public.check_customer_email('mirac-karaman-1998@outlook.com'::text);
```
