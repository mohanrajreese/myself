-- Weight records (PRD §5.2). Created in Phase 1 because onboarding records
-- the first weight.

create table public.weight_logs (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  weight_g          integer not null check (weight_g between 1000 and 700000),
  entry_unit        text not null check (entry_unit in ('kg', 'lb')),
  occurred_at       timestamptz not null,
  local_date        date not null,
  tz                text not null,
  notes             text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index weight_logs_user_date_idx on public.weight_logs (user_id, local_date);
create index weight_logs_user_cursor_idx on public.weight_logs (user_id, server_updated_at, id);

alter table public.weight_logs enable row level security;
revoke all on table public.weight_logs from anon;
grant select, insert, update, delete on table public.weight_logs to authenticated;

create policy weight_logs_select on public.weight_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy weight_logs_insert on public.weight_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy weight_logs_update on public.weight_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy weight_logs_delete on public.weight_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger weight_logs_stale before update on public.weight_logs
  for each row execute function public.reject_stale_write();
create trigger weight_logs_cursor before insert or update on public.weight_logs
  for each row execute function public.set_server_updated_at();
