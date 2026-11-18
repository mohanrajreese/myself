-- Push tokens and per-device sync status (03-database.md §2.7, PRD §5.15I).
-- No health data: a token, a label, preferences and timestamps.

create table public.device_notification_tokens (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  fcm_token     text not null unique check (length(fcm_token) between 20 and 4096),
  device_label  text not null default 'Android' check (length(device_label) <= 40),
  app_version   text not null check (length(app_version) <= 20),
  preferences   jsonb not null default '{"account": true, "sync_problems": true, "backup_status": false}',
  last_seen_at  timestamptz not null,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);

create index device_notification_tokens_user_idx on public.device_notification_tokens (user_id) where revoked_at is null;

alter table public.device_notification_tokens enable row level security;
revoke all on table public.device_notification_tokens from anon;
grant select, insert, update, delete on table public.device_notification_tokens to authenticated;

create policy device_notification_tokens_select on public.device_notification_tokens for select to authenticated
  using ((select auth.uid()) = user_id);
create policy device_notification_tokens_insert on public.device_notification_tokens for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy device_notification_tokens_update on public.device_notification_tokens for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy device_notification_tokens_delete on public.device_notification_tokens for delete to authenticated
  using ((select auth.uid()) = user_id);

create table public.cloud_sync_metadata (
  device_id       uuid primary key,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  last_push_at    timestamptz,
  last_pull_at    timestamptz,
  schema_version  smallint not null check (schema_version > 0),
  app_version     text not null check (length(app_version) <= 20),
  updated_at      timestamptz not null default now()
);

create index cloud_sync_metadata_user_idx on public.cloud_sync_metadata (user_id);

alter table public.cloud_sync_metadata enable row level security;
revoke all on table public.cloud_sync_metadata from anon;
grant select, insert, update, delete on table public.cloud_sync_metadata to authenticated;

create policy cloud_sync_metadata_select on public.cloud_sync_metadata for select to authenticated
  using ((select auth.uid()) = user_id);
create policy cloud_sync_metadata_insert on public.cloud_sync_metadata for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy cloud_sync_metadata_update on public.cloud_sync_metadata for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy cloud_sync_metadata_delete on public.cloud_sync_metadata for delete to authenticated
  using ((select auth.uid()) = user_id);
