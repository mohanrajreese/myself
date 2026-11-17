-- Ordinary reminders (PRD §5.15). Sensitive reminders (medication, bowel,
-- private activities) never leave the device (§7.1). Notification state is
-- device-only and has no cloud table.

create table public.reminders (
  id                     uuid primary key,
  user_id                uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind                   text not null check (kind in ('custom', 'activity', 'water', 'workout', 'sleep', 'posture')),
  title                  text not null check (length(title) between 1 and 80),
  description            text,
  activity_definition_id uuid,
  schedule               jsonb not null,
  condition              text not null check (condition in ('always', 'if_incomplete')),
  channel_key            text not null check (channel_key in ('alarms', 'routines', 'hydration', 'fitness', 'medication', 'sleep', 'system')),
  sound_key              text,
  vibrate                boolean not null default true,
  snooze_default_min     smallint not null default 10 check (snooze_default_min between 1 and 720),
  priority               text not null check (priority in ('normal', 'alarm')),
  quiet_hours_behaviour  text not null check (quiet_hours_behaviour in ('defer', 'suppress', 'bypass')),
  exact                  boolean not null default false,
  enabled                boolean not null default true,
  start_date             date,
  end_date               date,
  check (end_date is null or start_date is null or end_date >= start_date),
  created_at             timestamptz not null,
  updated_at             timestamptz not null,
  deleted_at             timestamptz,
  server_updated_at      timestamptz not null default now(),
  -- A reminder can only point at its owner's activity.
  foreign key (activity_definition_id, user_id)
    references public.activity_definitions (id, user_id) on delete set null (activity_definition_id),
  unique (id, user_id)
);

create index reminders_user_cursor_idx on public.reminders (user_id, server_updated_at, id);

alter table public.reminders enable row level security;
revoke all on table public.reminders from anon;
grant select, insert, update, delete on table public.reminders to authenticated;

create policy reminders_select on public.reminders for select to authenticated
  using ((select auth.uid()) = user_id);
create policy reminders_insert on public.reminders for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy reminders_update on public.reminders for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy reminders_delete on public.reminders for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger reminders_stale before update on public.reminders
  for each row execute function public.reject_stale_write();
create trigger reminders_cursor before insert or update on public.reminders
  for each row execute function public.set_server_updated_at();
