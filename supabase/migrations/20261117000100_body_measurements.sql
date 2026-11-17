-- Body measurements (PRD §5.3). value_milli is thousandths of `unit`.

create table public.body_measurements (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  measurement_type  text not null check (char_length(measurement_type) between 1 and 60),
  value_milli       integer not null check (value_milli > 0),
  unit              text not null check (unit in ('cm', 'percent')),
  entry_unit        text not null check (entry_unit in ('cm', 'in', 'percent')),
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

create index body_measurements_user_type_date_idx on public.body_measurements (user_id, measurement_type, local_date);
create index body_measurements_user_cursor_idx on public.body_measurements (user_id, server_updated_at, id);

alter table public.body_measurements enable row level security;
revoke all on table public.body_measurements from anon;
grant select, insert, update, delete on table public.body_measurements to authenticated;

create policy body_measurements_select on public.body_measurements for select to authenticated
  using ((select auth.uid()) = user_id);
create policy body_measurements_insert on public.body_measurements for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy body_measurements_update on public.body_measurements for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy body_measurements_delete on public.body_measurements for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger body_measurements_stale before update on public.body_measurements
  for each row execute function public.reject_stale_write();
create trigger body_measurements_cursor before insert or update on public.body_measurements
  for each row execute function public.set_server_updated_at();
