-- Sleep records and wellness check-ins (PRD §5.9, §5.10).
-- A night's local_date is the day the user woke up.

create table public.sleep_logs (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind              text not null check (kind in ('night', 'nap')),
  start_at          timestamptz not null,
  end_at            timestamptz not null,
  duration_s        integer not null check (duration_s between 60 and 86400),
  quality           smallint check (quality between 1 and 5),
  notes             text,
  local_date        date not null,
  tz                text not null,
  check (end_at > start_at),
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index sleep_logs_user_date_idx on public.sleep_logs (user_id, local_date);
create index sleep_logs_user_cursor_idx on public.sleep_logs (user_id, server_updated_at, id);

alter table public.sleep_logs enable row level security;
revoke all on table public.sleep_logs from anon;
grant select, insert, update, delete on table public.sleep_logs to authenticated;

create policy sleep_logs_select on public.sleep_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy sleep_logs_insert on public.sleep_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy sleep_logs_update on public.sleep_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy sleep_logs_delete on public.sleep_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger sleep_logs_stale before update on public.sleep_logs
  for each row execute function public.reject_stale_write();
create trigger sleep_logs_cursor before insert or update on public.sleep_logs
  for each row execute function public.set_server_updated_at();


create table public.daily_health_checkins (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  energy            smallint not null check (energy between 1 and 5),
  mood              smallint not null check (mood between 1 and 5),
  stress            smallint not null check (stress between 1 and 5),
  wellness          smallint not null check (wellness between 1 and 5),
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

create index daily_health_checkins_user_date_idx on public.daily_health_checkins (user_id, local_date);
create index daily_health_checkins_user_cursor_idx on public.daily_health_checkins (user_id, server_updated_at, id);

alter table public.daily_health_checkins enable row level security;
revoke all on table public.daily_health_checkins from anon;
grant select, insert, update, delete on table public.daily_health_checkins to authenticated;

create policy daily_health_checkins_select on public.daily_health_checkins for select to authenticated
  using ((select auth.uid()) = user_id);
create policy daily_health_checkins_insert on public.daily_health_checkins for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy daily_health_checkins_update on public.daily_health_checkins for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy daily_health_checkins_delete on public.daily_health_checkins for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger daily_health_checkins_stale before update on public.daily_health_checkins
  for each row execute function public.reject_stale_write();
create trigger daily_health_checkins_cursor before insert or update on public.daily_health_checkins
  for each row execute function public.set_server_updated_at();
