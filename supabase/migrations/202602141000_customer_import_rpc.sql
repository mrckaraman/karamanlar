-- Customer import RPC and logging tables
-- Date: 2026-02-14

set search_path to public;

-- Batch table to track customer import operations
create table if not exists public.customer_import_batches (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  admin_user_id uuid not null,
  file_name text,
  mode text not null,
  total_count integer not null default 0,
  inserted_count integer not null default 0,
  updated_count integer not null default 0,
  skipped_count integer not null default 0,
  error_count integer not null default 0
);

-- Optional per-row log table (mainly for errors and audit)
create table if not exists public.customer_import_items (
  id bigserial primary key,
  batch_id uuid not null references public.customer_import_batches(id) on delete cascade,
  row_index integer not null,
  status text not null,
  message text,
  raw jsonb
);

-- Main RPC: import customers from JSON payload
-- Signature is aligned with app expectations:
--   payload: {
--     file_name?: text,
--     rows: [
--       {
--         trade_title?: text,
--         full_name?: text,
--         tax_no?: text,
--         phone?: text,
--         email?: text,
--         address?: text,
--         city?: text,
--         district?: text,
--         limit_amount?: numeric,
--         is_active?: boolean
--       }
--     ]
--   }
--   mode: 'validate' | 'insert_only' | 'upsert_by_taxno'
--
-- Behaviour:
-- - mode = 'validate': no writes, returns per-row classification + summary
-- - mode = 'insert_only': insert only, existing tax_no rows are skipped
-- - mode = 'upsert_by_taxno': insert new, update existing by tax_no

create or replace function public.rpc_import_customers(payload jsonb, mode text)
returns jsonb
language plpgsql
security definer
as
$$
declare
  v_mode text := lower(coalesce(mode, 'validate'));
  v_is_validate boolean := (v_mode = 'validate');
  v_rows jsonb := coalesce(payload -> 'rows', '[]'::jsonb);
  v_file_name text := coalesce(payload ->> 'file_name', null);

  v_row jsonb;
  v_rows_iter refcursor;
  v_index integer := 0;

  v_trade_title text;
  v_full_name text;
  v_tax_no text;
  v_phone text;
  v_email text;
  v_address text;
  v_city text;
  v_district text;
  v_limit_amount numeric;
  v_is_active boolean;

  v_tax_office text;
  v_customer_code text;
  v_warn_on_limit_exceeded_raw text;
  v_warn_on_limit_exceeded boolean;
  v_risk_note text;
  v_marketer_name text;
  v_group_name text;
  v_sub_group text;
  v_alt_group text;
  v_opening_balance numeric;
  v_opening_balance_type text;
  v_due_days integer;
  v_price_tier integer;
  v_tags_csv text;
  v_tags text[];
  v_address_detail text;
  v_customer_id public.customers.id%TYPE;
  v_existing_customer_id public.customers.id%TYPE;

  v_has_error boolean;
  v_error_msg text;

  v_existing_by_tax record;
  v_existing_by_name record;
  v_existing_by_code record;

  v_total integer := 0;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_skipped integer := 0;
  v_errors integer := 0;
  v_suspicious integer := 0;
  v_update_candidates integer := 0;

  v_rows_report jsonb := '[]'::jsonb;
  v_error_samples jsonb := '[]'::jsonb;

  v_batch_id uuid;
  v_admin_user_id uuid;
  v_status text;
  v_issue_list text[];
  v_strategy text;
  v_effective_strategy text;

begin
  -- Admin guard. Assumes public.is_admin() is defined and checks auth.role/claims.
  if not public.is_admin() then
    raise exception 'Only admin users can import customers';
  end if;

  v_total := jsonb_array_length(v_rows);

  if v_total = 0 then
    return jsonb_build_object(
      'mode', v_mode,
      'batch_id', null,
      'summary', jsonb_build_object(
        'total', 0,
        'inserted', 0,
        'updated', 0,
        'skipped', 0,
        'errors', 0,
        'suspicious', 0,
        'updateCandidates', 0
      ),
      'rows', '[]'::jsonb,
      'errorSamples', '[]'::jsonb
    );
  end if;

  -- Resolve admin user id from auth context if available
  begin
    select auth.uid() into v_admin_user_id;
  exception when others then
    v_admin_user_id := null;
  end;

  -- Optional strategy hint from payload (for validate mode)
  v_strategy := lower(nullif(payload ->> 'strategy', ''));

  if not v_is_validate then
    insert into public.customer_import_batches (
      admin_user_id,
      file_name,
      mode,
      total_count
    ) values (
      coalesce(v_admin_user_id, gen_random_uuid()),
      v_file_name,
      v_mode,
      v_total
    )
    returning id into v_batch_id;
  end if;

  -- Iterate rows
  for v_index in 0 .. v_total - 1 loop
    v_row := v_rows -> v_index;

    v_trade_title := nullif(trim(v_row ->> 'trade_title'), '');
    v_full_name   := nullif(trim(v_row ->> 'full_name'), '');
    v_phone       := nullif(trim(v_row ->> 'phone'), '');
    v_email       := nullif(trim(v_row ->> 'email'), '');
    v_tax_office  := nullif(trim(v_row ->> 'tax_office'), '');
    v_address     := nullif(trim(v_row ->> 'address'), '');
    v_city        := nullif(trim(v_row ->> 'city'), '');
    v_district    := nullif(trim(v_row ->> 'district'), '');
    v_limit_amount := nullif(v_row ->> 'limit_amount', '')::numeric;
    v_is_active   := coalesce((v_row ->> 'is_active')::boolean, true);
    v_tax_no      := nullif(trim(v_row ->> 'tax_no'), '');

    v_risk_note   := nullif(trim(v_row ->> 'risk_note'), '');
    v_marketer_name := coalesce(
      nullif(trim(v_row ->> 'marketer_name'), ''),
      nullif(trim(v_row ->> 'pazarlamaci_name'), '')
    );
    v_group_name  := nullif(trim(v_row ->> 'group_name'), '');
    v_sub_group   := nullif(trim(v_row ->> 'sub_group'), '');
    v_alt_group   := nullif(trim(v_row ->> 'alt_group'), '');
    v_opening_balance := nullif(v_row ->> 'opening_balance', '')::numeric;
    v_opening_balance_type := lower(nullif(trim(v_row ->> 'opening_balance_type'), ''));
    if v_opening_balance_type in ('borç', 'borc', 'debit') then
      v_opening_balance_type := 'debit';
    elsif v_opening_balance_type in ('alacak', 'credit') then
      v_opening_balance_type := 'credit';
    else
      v_opening_balance_type := null;
    end if;

    v_due_days := nullif(trim(v_row ->> 'due_days'), '')::integer;
    v_price_tier := nullif(trim(v_row ->> 'price_tier'), '')::integer;

    v_tags_csv := nullif(trim(v_row ->> 'tags_csv'), '');
    if v_tags_csv is not null then
      v_tags := regexp_split_to_array(v_tags_csv, '\s*,\s*');
      v_tags := array_remove(v_tags, '');
    else
      v_tags := null;
    end if;

    v_address_detail := v_address;

    v_warn_on_limit_exceeded_raw := lower(coalesce(trim(v_row ->> 'warn_on_limit_exceeded'), ''));
    if v_warn_on_limit_exceeded_raw in ('evet', 'true', '1', 'yes') then
      v_warn_on_limit_exceeded := true;
    elsif v_warn_on_limit_exceeded_raw in ('hayır', 'hayir', 'false', '0', 'no') then
      v_warn_on_limit_exceeded := false;
    else
      v_warn_on_limit_exceeded := null;
    end if;

    -- Customer code for upsert_by_customer_code mode
    v_customer_code := nullif(trim(v_row ->> 'customer_code'), '');
    v_tax_no      := nullif(trim(v_row ->> 'tax_no'), '');
    v_phone       := nullif(trim(v_row ->> 'phone'), '');
    v_email       := nullif(trim(v_row ->> 'email'), '');
    v_address     := nullif(trim(v_row ->> 'address'), '');
    v_city        := nullif(trim(v_row ->> 'city'), '');
    v_district    := nullif(trim(v_row ->> 'district'), '');
    v_limit_amount := nullif(v_row ->> 'limit_amount', '')::numeric;
    v_is_active   := coalesce((v_row ->> 'is_active')::boolean, true);

    v_total := v_total; -- keep compiler happy
    v_has_error := false;
    v_error_msg := null;
    v_status := null;
    v_issue_list := array[]::text[];

    -- Required identity: at least trade_title or full_name or tax_no
    if v_trade_title is null and v_full_name is null and v_tax_no is null then
      v_has_error := true;
      v_error_msg := 'ticari_unvan veya ad_soyad veya vergi_no zorunlu';
      v_issue_list := array_append(v_issue_list, v_error_msg);
    end if;

    -- Basic email format
    if v_email is not null and position('@' in v_email) = 0 then
      v_has_error := true;
      v_issue_list := array_append(v_issue_list, 'email formatı geçersiz');
    end if;

    -- Check existing by tax_no
    v_existing_by_tax := null;
    if v_tax_no is not null then
      select c.id, c.tax_no, c.trade_title, c.full_name
        into v_existing_by_tax
      from public.customers c
      where c.tax_no = v_tax_no
      limit 1;
    end if;

    -- Check existing by customer_code for upsert_by_customer_code
    v_existing_by_code := null;
    if v_customer_code is not null then
      select c.id, c.customer_code
        into v_existing_by_code
      from public.customers c
      where c.customer_code = v_customer_code
      limit 1;
    end if;

    -- Suspicious: same trade_title/full_name but different tax_no
    v_existing_by_name := null;
    if v_trade_title is not null or v_full_name is not null then
      select c.id, c.tax_no, c.trade_title, c.full_name
        into v_existing_by_name
      from public.customers c
      where (
        (v_trade_title is not null and lower(coalesce(c.trade_title, '')) = lower(v_trade_title))
        or (v_full_name is not null and lower(coalesce(c.full_name, '')) = lower(v_full_name))
      )
      limit 1;
    end if;

    if not v_has_error and v_existing_by_name is not null and (
      (v_tax_no is not null and v_existing_by_name.tax_no is not null and v_existing_by_name.tax_no <> v_tax_no)
      or (v_tax_no is null and v_existing_by_name.tax_no is not null)
    ) then
      v_status := 'suspicious';
      v_has_error := true; -- treat as blocking in apply phase
      v_suspicious := v_suspicious + 1;
      v_issue_list := array_append(v_issue_list, 'Aynı ünvan için farklı vergi_no tespit edildi (şüpheli eşleşme)');
    end if;

    if v_has_error then
      v_status := coalesce(v_status, 'error');
      v_errors := v_errors + 1;
    else
      if v_is_validate then
        -- Classification for validate mode depends on import strategy
        v_effective_strategy := v_strategy;

        -- Fallback: if no explicit strategy, prefer taxno, then customer_code
        if v_effective_strategy is null then
          if v_tax_no is not null then
            v_effective_strategy := 'by_taxno';
          elsif v_customer_code is not null then
            v_effective_strategy := 'by_customer_code';
          else
            v_effective_strategy := 'insert_only';
          end if;
        end if;

        if v_effective_strategy = 'by_customer_code' then
          if v_existing_by_code is null then
            v_status := 'insert';
            v_inserted := v_inserted + 1;
          else
            v_status := 'update';
            v_updated := v_updated + 1;
            v_update_candidates := v_update_candidates + 1;
          end if;
        elsif v_effective_strategy = 'by_taxno' then
          if v_tax_no is not null and v_existing_by_tax is not null then
            v_status := 'update';
            v_updated := v_updated + 1;
            v_update_candidates := v_update_candidates + 1;
          else
            -- tax_no yok veya eşleşme yok: yeni kayıt olarak değerlendir
            v_status := 'insert';
            v_inserted := v_inserted + 1;
          end if;
        elsif v_effective_strategy = 'insert_only' then
          -- insert_only stratejisinde mevcut kayıtlar "skip" edilir
          if v_customer_code is not null and v_existing_by_code is not null then
            v_status := 'skip';
            v_skipped := v_skipped + 1;
          elsif v_tax_no is not null and v_existing_by_tax is not null then
            v_status := 'skip';
            v_skipped := v_skipped + 1;
          else
            v_status := 'insert';
            v_inserted := v_inserted + 1;
          end if;
        else
          -- Beklenmeyen stratejiler için mevcut davranışa geri düş
          if v_existing_by_tax is null then
            v_status := 'insert';
            v_inserted := v_inserted + 1;
          else
            v_status := 'update';
            v_updated := v_updated + 1;
            v_update_candidates := v_update_candidates + 1;
          end if;
        end if;
      else
        -- Apply modlarında sınıflandırma çalışma moduna göre yapılır
        if v_mode = 'upsert_by_customer_code' then
          if v_existing_by_code is null then
            v_status := 'insert';
            v_inserted := v_inserted + 1;
          else
            v_status := 'update';
            v_update_candidates := v_update_candidates + 1;
          end if;
        else
          if v_existing_by_tax is null then
            v_status := 'insert';
            v_inserted := v_inserted + 1;
          else
            v_status := 'update';
            v_update_candidates := v_update_candidates + 1;
          end if;
        end if;
      end if;
    end if;

    -- Build validate report row
    if v_is_validate then
      v_rows_report := v_rows_report || jsonb_build_array(
        jsonb_build_object(
          'index', v_index + 1,
          'status', v_status,
          'issues', to_jsonb(v_issue_list),
          'wouldInsert', (v_status = 'insert'),
          'wouldUpdate', (v_status = 'update'),
          'isSuspicious', (v_status = 'suspicious')
        )
      );
      if jsonb_array_length(v_error_samples) < 10 and (v_status = 'error' or v_status = 'suspicious') then
        v_error_samples := v_error_samples || jsonb_build_array(
          jsonb_build_object(
            'index', v_index + 1,
            'status', v_status,
            'issues', to_jsonb(v_issue_list)
          )
        );
      end if;
    else
      -- Apply modes: insert_only / upsert_by_taxno
      if v_status = 'suspicious' or v_status = 'error' then
        v_errors := v_errors + 1;
        if jsonb_array_length(v_error_samples) < 10 then
          v_error_samples := v_error_samples || jsonb_build_array(
            jsonb_build_object(
              'index', v_index + 1,
              'status', v_status,
              'issues', to_jsonb(v_issue_list)
            )
          );
        end if;
        insert into public.customer_import_items (
          batch_id, row_index, status, message, raw
        ) values (
          v_batch_id,
          v_index + 1,
          v_status,
          array_to_string(v_issue_list, '; '),
          v_row
        );
      elsif v_mode = 'insert_only' then
        if v_existing_by_tax is null then
          insert into public.customers (
            full_name, trade_title, customer_code, tax_no,
            phone, email, address, city, district,
            limit_amount, is_active
          ) values (
            v_full_name,
            v_trade_title,
            coalesce(v_row ->> 'customer_code', ''),
            v_tax_no,
            v_phone,
            v_email,
            v_address,
            v_city,
            v_district,
            v_limit_amount,
            v_is_active
          ) returning id into v_customer_id;

          v_inserted := v_inserted + 1;

          insert into public.customer_details (
            customer_id,
            city,
            district,
            tax_office,
            tax_no,
            limit_amount,
            warn_on_limit_exceeded,
            risk_note,
            group_name,
            sub_group,
            alt_group,
            opening_balance,
            opening_balance_type,
            marketer_name,
            due_days,
            price_tier,
            tags,
            address_detail
          ) values (
            v_customer_id,
            v_city,
            v_district,
            v_tax_office,
            v_tax_no,
            v_limit_amount,
            v_warn_on_limit_exceeded,
            v_risk_note,
            v_group_name,
            v_sub_group,
            v_alt_group,
            v_opening_balance,
            v_opening_balance_type,
            v_marketer_name,
            v_due_days,
            v_price_tier,
            v_tags,
            v_address_detail
          )
          on conflict (customer_id) do update set
            city = coalesce(nullif(excluded.city, ''), public.customer_details.city),
            district = coalesce(nullif(excluded.district, ''), public.customer_details.district),
            tax_office = coalesce(nullif(excluded.tax_office, ''), public.customer_details.tax_office),
            tax_no = coalesce(nullif(excluded.tax_no, ''), public.customer_details.tax_no),
            limit_amount = coalesce(excluded.limit_amount, public.customer_details.limit_amount),
            warn_on_limit_exceeded = coalesce(excluded.warn_on_limit_exceeded, public.customer_details.warn_on_limit_exceeded),
            risk_note = coalesce(nullif(excluded.risk_note, ''), public.customer_details.risk_note),
            group_name = coalesce(nullif(excluded.group_name, ''), public.customer_details.group_name),
            sub_group = coalesce(nullif(excluded.sub_group, ''), public.customer_details.sub_group),
            alt_group = coalesce(nullif(excluded.alt_group, ''), public.customer_details.alt_group),
            opening_balance = coalesce(excluded.opening_balance, public.customer_details.opening_balance),
            opening_balance_type = coalesce(nullif(excluded.opening_balance_type, ''), public.customer_details.opening_balance_type),
            marketer_name = coalesce(nullif(excluded.marketer_name, ''), public.customer_details.marketer_name),
            due_days = coalesce(excluded.due_days, public.customer_details.due_days),
            price_tier = coalesce(excluded.price_tier, public.customer_details.price_tier),
            tags = case
              when excluded.tags is null
                or array_length(excluded.tags, 1) is null
                or array_length(excluded.tags, 1) = 0
              then public.customer_details.tags
              else excluded.tags
            end,
            address_detail = coalesce(nullif(excluded.address_detail, ''), public.customer_details.address_detail),
            updated_at = now();
          insert into public.customer_import_items (
            batch_id, row_index, status, message, raw
          ) values (
            v_batch_id,
            v_index + 1,
            'inserted',
            null,
            v_row
          );
        else
          v_skipped := v_skipped + 1;
          insert into public.customer_import_items (
            batch_id, row_index, status, message, raw
          ) values (
            v_batch_id,
            v_index + 1,
            'skipped_existing',
            'Mevcut vergi_no nedeniyle insert-only modunda atlandı',
            v_row
          );
        end if;
      elsif v_mode = 'upsert_by_taxno' or v_mode = 'upsert_by_customer_code' then
        if (v_mode = 'upsert_by_taxno' and v_existing_by_tax is null)
           or (v_mode = 'upsert_by_customer_code' and v_existing_by_code is null) then
          insert into public.customers (
            full_name, trade_title, customer_code, tax_no,
            phone, email, address, city, district,
            limit_amount, is_active
          ) values (
            v_full_name,
            v_trade_title,
            coalesce(v_customer_code, ''),
            v_tax_no,
            v_phone,
            v_email,
            v_address,
            v_city,
            v_district,
            v_limit_amount,
            v_is_active
          ) returning id into v_customer_id;

          v_inserted := v_inserted + 1;

          insert into public.customer_details (
            customer_id,
            city,
            district,
            tax_office,
            tax_no,
            limit_amount,
            warn_on_limit_exceeded,
            risk_note,
            group_name,
            sub_group,
            alt_group,
            opening_balance,
            opening_balance_type,
            marketer_name,
            due_days,
            price_tier,
            tags,
            address_detail
          ) values (
            v_customer_id,
            v_city,
            v_district,
            v_tax_office,
            v_tax_no,
            v_limit_amount,
            v_warn_on_limit_exceeded,
            v_risk_note,
            v_group_name,
            v_sub_group,
            v_alt_group,
            v_opening_balance,
            v_opening_balance_type,
            v_marketer_name,
            v_due_days,
            v_price_tier,
            v_tags,
            v_address_detail
          )
          on conflict (customer_id) do update set
            city = coalesce(nullif(excluded.city, ''), public.customer_details.city),
            district = coalesce(nullif(excluded.district, ''), public.customer_details.district),
            tax_office = coalesce(nullif(excluded.tax_office, ''), public.customer_details.tax_office),
            tax_no = coalesce(nullif(excluded.tax_no, ''), public.customer_details.tax_no),
            limit_amount = coalesce(excluded.limit_amount, public.customer_details.limit_amount),
            warn_on_limit_exceeded = coalesce(excluded.warn_on_limit_exceeded, public.customer_details.warn_on_limit_exceeded),
            risk_note = coalesce(nullif(excluded.risk_note, ''), public.customer_details.risk_note),
            group_name = coalesce(nullif(excluded.group_name, ''), public.customer_details.group_name),
            sub_group = coalesce(nullif(excluded.sub_group, ''), public.customer_details.sub_group),
            alt_group = coalesce(nullif(excluded.alt_group, ''), public.customer_details.alt_group),
            opening_balance = coalesce(excluded.opening_balance, public.customer_details.opening_balance),
            opening_balance_type = coalesce(nullif(excluded.opening_balance_type, ''), public.customer_details.opening_balance_type),
            marketer_name = coalesce(nullif(excluded.marketer_name, ''), public.customer_details.marketer_name),
            due_days = coalesce(excluded.due_days, public.customer_details.due_days),
            price_tier = coalesce(excluded.price_tier, public.customer_details.price_tier),
            tags = case
              when excluded.tags is null
                or array_length(excluded.tags, 1) is null
                or array_length(excluded.tags, 1) = 0
              then public.customer_details.tags
              else excluded.tags
            end,
            address_detail = coalesce(nullif(excluded.address_detail, ''), public.customer_details.address_detail),
            updated_at = now();
          insert into public.customer_import_items (
            batch_id, row_index, status, message, raw
          ) values (
            v_batch_id,
            v_index + 1,
            'inserted',
            null,
            v_row
          );
        else
          -- Mevcut musteri guncellemesi icin id'yi netlestir.
          v_existing_customer_id := case
            when v_mode = 'upsert_by_taxno' then v_existing_by_tax.id
            else v_existing_by_code.id
          end;

          update public.customers set
            full_name = coalesce(v_full_name, full_name),
            trade_title = coalesce(v_trade_title, trade_title),
            phone = coalesce(v_phone, phone),
            email = coalesce(v_email, email),
            address = coalesce(v_address, address),
            city = coalesce(v_city, city),
            district = coalesce(v_district, district),
            limit_amount = coalesce(v_limit_amount, limit_amount),
            is_active = coalesce(v_is_active, is_active)
          where id = v_existing_customer_id
          returning id into v_customer_id;

          -- Guvenlik icin, her durumda v_customer_id set olsun.
          v_customer_id := coalesce(v_customer_id, v_existing_customer_id);

          insert into public.customer_details (
            customer_id,
            city,
            district,
            tax_office,
            tax_no,
            limit_amount,
            warn_on_limit_exceeded,
            risk_note,
            group_name,
            sub_group,
            alt_group,
            opening_balance,
            opening_balance_type,
            marketer_name,
            due_days,
            price_tier,
            tags,
            address_detail
          ) values (
            v_customer_id,
            v_city,
            v_district,
            v_tax_office,
            v_tax_no,
            v_limit_amount,
            v_warn_on_limit_exceeded,
            v_risk_note,
            v_group_name,
            v_sub_group,
            v_alt_group,
            v_opening_balance,
            v_opening_balance_type,
            v_marketer_name,
            v_due_days,
            v_price_tier,
            v_tags,
            v_address_detail
          )
          on conflict (customer_id) do update set
            city = coalesce(nullif(excluded.city, ''), public.customer_details.city),
            district = coalesce(nullif(excluded.district, ''), public.customer_details.district),
            tax_office = coalesce(nullif(excluded.tax_office, ''), public.customer_details.tax_office),
            tax_no = coalesce(nullif(excluded.tax_no, ''), public.customer_details.tax_no),
            limit_amount = coalesce(excluded.limit_amount, public.customer_details.limit_amount),
            warn_on_limit_exceeded = coalesce(excluded.warn_on_limit_exceeded, public.customer_details.warn_on_limit_exceeded),
            risk_note = coalesce(nullif(excluded.risk_note, ''), public.customer_details.risk_note),
            group_name = coalesce(nullif(excluded.group_name, ''), public.customer_details.group_name),
            sub_group = coalesce(nullif(excluded.sub_group, ''), public.customer_details.sub_group),
            alt_group = coalesce(nullif(excluded.alt_group, ''), public.customer_details.alt_group),
            opening_balance = coalesce(excluded.opening_balance, public.customer_details.opening_balance),
            opening_balance_type = coalesce(nullif(excluded.opening_balance_type, ''), public.customer_details.opening_balance_type),
            marketer_name = coalesce(nullif(excluded.marketer_name, ''), public.customer_details.marketer_name),
            due_days = coalesce(excluded.due_days, public.customer_details.due_days),
            price_tier = coalesce(excluded.price_tier, public.customer_details.price_tier),
            tags = case
              when excluded.tags is null
                or array_length(excluded.tags, 1) is null
                or array_length(excluded.tags, 1) = 0
              then public.customer_details.tags
              else excluded.tags
            end,
            address_detail = coalesce(nullif(excluded.address_detail, ''), public.customer_details.address_detail),
            updated_at = now();

          v_updated := v_updated + 1;
          insert into public.customer_import_items (
            batch_id, row_index, status, message, raw
          ) values (
            v_batch_id,
            v_index + 1,
            'updated',
            null,
            v_row
          );
        end if;
      else
        raise exception 'Unknown mode for apply: %', v_mode;
      end if;
    end if;
  end loop;

  if not v_is_validate then
    update public.customer_import_batches
    set
      inserted_count = v_inserted,
      updated_count = v_updated,
      skipped_count = v_skipped,
      error_count = v_errors
    where id = v_batch_id;
  end if;

  return jsonb_build_object(
    'mode', v_mode,
    'batch_id', case when v_is_validate then null else v_batch_id end,
    'summary', jsonb_build_object(
      'total', v_total,
      'inserted', v_inserted,
      'updated', v_updated,
      'skipped', v_skipped,
      'errors', v_errors,
      'suspicious', v_suspicious,
      'updateCandidates', v_update_candidates
    ),
    'rows', case when v_is_validate then v_rows_report else '[]'::jsonb end,
    'errorSamples', v_error_samples
  );
end;
$$;

revoke all on function public.rpc_import_customers(jsonb, text) from public;
grant execute on function public.rpc_import_customers(jsonb, text) to authenticated;

-- Notify PostgREST / Supabase to reload schema
notify pgrst, 'reload schema';
