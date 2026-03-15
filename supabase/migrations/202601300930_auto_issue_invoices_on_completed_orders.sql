-- Auto-issue invoices when orders become completed

-- Bu migration, orders.status degeri "completed" oldugunda
-- ilgili siparis icin faturanin otomatik olusturulmasini veya
-- guncellenmesini saglar.

create or replace function public.trg_orders_issue_invoice_on_completed()
returns trigger
language plpgsql
as $$
declare
  v_existing_invoice_id uuid;
  v_existing_invoice_no text;
  v_generated_invoice_no text;
begin
  -- Sadece UPDATE islemlerinde ve status degeri "completed"e
  -- degistiginde calis.
  if TG_OP <> 'UPDATE' then
    return NEW;
  end if;

  if NEW.status <> 'completed' or OLD.status = NEW.status then
    return NEW;
  end if;

  -- Aynı siparis icin daha once olusturulmus bir fatura var mi?
  select id, invoice_no
    into v_existing_invoice_id, v_existing_invoice_no
  from public.invoices
  where order_id = NEW.id
  limit 1;

  if v_existing_invoice_id is null then
    -- Yeni fatura: invoice_no yoksa otomatik olustur.
    v_generated_invoice_no :=
      'F' || to_char(current_date, 'YYMMDD') || '-' ||
      substring(replace(NEW.id::text, '-', '') from 1 for 8);

    insert into public.invoices (
      order_id,
      customer_id,
      status,
      issued_at,
      invoice_date,
      total_amount,
      invoice_no
    ) values (
      NEW.id,
      NEW.customer_id,
      'issued',
      now(),
      current_date,
      NEW.total_amount,
      v_generated_invoice_no
    );
  else
    -- Mevcut fatura var: idempotent davraniş icin sadece guncelle.
    if v_existing_invoice_no is null or btrim(v_existing_invoice_no) = '' then
      v_generated_invoice_no :=
        'F' || to_char(current_date, 'YYMMDD') || '-' ||
        substring(replace(NEW.id::text, '-', '') from 1 for 8);
    else
      v_generated_invoice_no := v_existing_invoice_no;
    end if;

    update public.invoices
    set
      status = 'issued',
      issued_at = coalesce(issued_at, now()),
      invoice_date = coalesce(invoice_date, current_date),
      total_amount = NEW.total_amount,
      customer_id = NEW.customer_id,
      invoice_no = v_generated_invoice_no
    where id = v_existing_invoice_id;
  end if;

  return NEW;
end;
$$;

-- Trigger: sadece status kolonu UPDATE edildiginde ve deger "completed"e
-- gectiginde tetiklenir.

drop trigger if exists trg_orders_issue_invoice_on_completed
  on public.orders;

create trigger trg_orders_issue_invoice_on_completed
after update of status on public.orders
for each row
when (NEW.status = 'completed' and (OLD.status is distinct from NEW.status))
execute function public.trg_orders_issue_invoice_on_completed();

-- Supabase / PostgREST icin şema yenileme bildirimi
NOTIFY pgrst, 'reload schema';
