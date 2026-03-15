-- Otomatik cari kodu uretimi icin sekanslar, fonksiyon ve trigger

create sequence if not exists customer_code_commercial_seq;
create sequence if not exists customer_code_individual_seq;

create or replace function public.fn_generate_customer_code(p_type text)
returns text
language plpgsql
as $$
declare
  v_seq bigint;
  v_prefix text;
begin
  if p_type = 'individual' then
    v_prefix := 'BR-';
    v_seq := nextval('customer_code_individual_seq');
  else
    -- Varsayilan: ticari
    v_prefix := 'CR-';
    v_seq := nextval('customer_code_commercial_seq');
  end if;

  return format('%s%06s', v_prefix, v_seq);
end;
$$;

create or replace function public.trg_customers_set_code()
returns trigger
language plpgsql
as $$
begin
  if new.customer_code is null or btrim(new.customer_code) = '' then
    new.customer_code := public.fn_generate_customer_code(new.customer_type);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_customers_set_code on public.customers;
create trigger trg_customers_set_code
before insert on public.customers
for each row
execute function public.trg_customers_set_code();
