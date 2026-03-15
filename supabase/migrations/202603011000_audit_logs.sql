-- Central audit logs for critical data changes
-- Date: 2026-03-01

set search_path = public;

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  action text not null,
  entity text not null,
  entity_id text not null,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_entity
  on public.audit_logs (entity, entity_id, created_at desc);

create index if not exists idx_audit_logs_user
  on public.audit_logs (user_id, created_at desc);

alter table public.audit_logs enable row level security;

drop policy if exists "admin_select_audit_logs" on public.audit_logs;
create policy "admin_select_audit_logs"
  on public.audit_logs
  for select
  to authenticated
  using (public.is_admin());

drop policy if exists "auth_insert_audit_logs" on public.audit_logs;
create policy "auth_insert_audit_logs"
  on public.audit_logs
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Intentionally no update/delete policies.
