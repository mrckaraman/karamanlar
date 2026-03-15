-- Admin create order with items (transaction-safe numbering)
-- Date: 2026-03-01

set search_path = public;

create or replace function public.rpc_admin_create_order_with_items(
  p_customer_id uuid,
  p_note text default null,
  p_items jsonb
)
returns table (
  order_id uuid,
  order_no int
)
language plpgsql
security definer
set search_path = public, auth
as $$
#variable_conflict use_column
declare
  v_order_id uuid;
  v_next_no int;
  v_number_col text;
  v_total numeric := 0;
  v_item jsonb;
  v_stock_id uuid;
  v_qty numeric;
  v_unit_name text;
  v_unit_price numeric;
  v_line_total numeric;
  v_stock_name text;
begin
  -- Admin kontrolü
  if not public.is_admin() then
    raise exception 'not_authorized';
  end if;

  if p_customer_id is null then
    raise exception 'customer_id_required';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'items_invalid_format';
  end if;

  if jsonb_array_length(p_items) = 0 then
    raise exception 'items_empty';
  end if;

  -- Numbering satırını kilitle (concurrency-safe)
  select c.column_name
    into v_number_col
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'settings_numbering'
    and c.column_name in (
      'next_number',
      'next_no',
      'next_num',
      'next',
      'number',
      'value'
    )
  order by
    case c.column_name
      when 'next_number' then 1
      when 'next_no' then 2
      when 'next_num' then 3
      when 'next' then 4
      when 'number' then 5
      when 'value' then 6
      else 100
    end
  limit 1;

  if v_number_col is null then
    raise exception 'numbering_column_not_found';
  end if;

  execute format(
    'select %I::int from public.settings_numbering where key = $1 for update',
    v_number_col
  )
  into v_next_no
  using 'order';

  if v_next_no is null then
    raise exception 'numbering_not_configured';
  end if;

  -- Order insert (order_no: INT)
  insert into public.orders (
    customer_id,
    status,
    note,
    total_amount,
    order_no
  ) values (
    p_customer_id,
    'new',
    nullif(btrim(p_note), ''),
    0,
    v_next_no
  )
  returning id into v_order_id;

  -- Items loop
  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    v_stock_id := (v_item->>'stock_id')::uuid;
    v_qty := (v_item->>'qty')::numeric;
    v_unit_name := nullif(btrim(v_item->>'unit_name'), '');
    v_unit_price := (v_item->>'unit_price')::numeric;

    if v_stock_id is null then
      raise exception 'item_stock_id_required';
    end if;

    if v_qty is null or v_qty <= 0 then
      raise exception 'item_qty_invalid';
    end if;

    if v_unit_name is null then
      raise exception 'item_unit_name_required';
    end if;

    if v_unit_price is null or v_unit_price < 0 then
      raise exception 'item_unit_price_invalid';
    end if;

    select s.name
      into v_stock_name
    from public.stocks s
    where s.id = v_stock_id;

    if v_stock_name is null or btrim(v_stock_name) = '' then
      raise exception 'stock_not_found';
    end if;

    v_line_total := round(v_qty * v_unit_price, 2);
    v_total := v_total + v_line_total;

    insert into public.order_items (
      order_id,
      stock_id,
      name,
      qty,
      unit_name,
      unit_price,
      line_total
    ) values (
      v_order_id,
      v_stock_id,
      v_stock_name,
      v_qty,
      v_unit_name,
      v_unit_price,
      v_line_total
    );
  end loop;

  -- Total update
  update public.orders
  set total_amount = round(v_total, 2)
  where id = v_order_id;

  -- Increment numbering
  execute format(
    'update public.settings_numbering set %1$I = %1$I + 1 where key = $1',
    v_number_col
  )
  using 'order';

  return query
  select v_order_id as order_id, v_next_no as order_no;
end;
$$;

revoke all on function public.rpc_admin_create_order_with_items(uuid, text, jsonb) from public;
grant execute on function public.rpc_admin_create_order_with_items(uuid, text, jsonb) to authenticated;

-- Notify Supabase / PostgREST to reload schema
notify pgrst, 'reload schema';
