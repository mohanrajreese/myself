-- Activity definitions and logs (PRD §5.14). Ordinary activities only;
-- private activities never leave the device (§7.1, decision C5).
-- "Missed" is derived from the schedule and never stored.

create table public.activity_definitions (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 80),
  description       text,
  category          text not null,
  icon_key          text not null,
  tracking_type     text not null check (tracking_type in ('boolean', 'count', 'numeric', 'duration', 'stopwatch', 'event_log', 'checklist')),
  priority          text not null check (priority in ('essential', 'optional')),
  target_milli      bigint check (target_milli > 0),
  target_unit       text,
  schedule          jsonb not null,
  schedule_history  jsonb not null default '[]',
  stopwatch_enabled boolean not null default false,
  show_on_dashboard boolean not null default true,
  checklist_items   jsonb not null default '[]',
  status            text not null check (status in ('active', 'archived')),
  sort_order        integer not null default 0,
  system_key        text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index activity_definitions_user_cursor_idx on public.activity_definitions (user_id, server_updated_at, id);

alter table public.activity_definitions enable row level security;
revoke all on table public.activity_definitions from anon;
grant select, insert, update, delete on table public.activity_definitions to authenticated;

create policy activity_definitions_select on public.activity_definitions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy activity_definitions_insert on public.activity_definitions for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy activity_definitions_update on public.activity_definitions for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy activity_definitions_delete on public.activity_definitions for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger activity_definitions_stale before update on public.activity_definitions
  for each row execute function public.reject_stale_write();
create trigger activity_definitions_cursor before insert or update on public.activity_definitions
  for each row execute function public.set_server_updated_at();


create table public.activity_logs (
  id                     uuid primary key,
  user_id                uuid not null default auth.uid() references auth.users (id) on delete cascade,
  activity_definition_id uuid not null,
  status                 text not null check (status in ('completed', 'skipped')),
  occurred_at            timestamptz not null,
  local_date             date not null,
  tz                     text not null,
  scheduled_slot         smallint check (scheduled_slot between 0 and 1439),
  count_value            integer check (count_value >= 0),
  numeric_value_milli    bigint,
  unit                   text,
  duration_s             integer check (duration_s between 0 and 86400),
  checklist_state        jsonb,
  source                 text not null check (source in ('manual', 'notification', 'timer')),
  notes                  text,
  created_at             timestamptz not null,
  updated_at             timestamptz not null,
  deleted_at             timestamptz,
  server_updated_at      timestamptz not null default now(),
  -- A log can only point at its owner's activity.
  foreign key (activity_definition_id, user_id)
    references public.activity_definitions (id, user_id) on delete cascade,
  unique (id, user_id)
);

create index activity_logs_user_date_idx on public.activity_logs (user_id, local_date);
create index activity_logs_user_activity_idx on public.activity_logs (user_id, activity_definition_id, local_date);
create index activity_logs_user_cursor_idx on public.activity_logs (user_id, server_updated_at, id);

alter table public.activity_logs enable row level security;
revoke all on table public.activity_logs from anon;
grant select, insert, update, delete on table public.activity_logs to authenticated;

create policy activity_logs_select on public.activity_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy activity_logs_insert on public.activity_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy activity_logs_update on public.activity_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy activity_logs_delete on public.activity_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger activity_logs_stale before update on public.activity_logs
  for each row execute function public.reject_stale_write();
create trigger activity_logs_cursor before insert or update on public.activity_logs
  for each row execute function public.set_server_updated_at();
