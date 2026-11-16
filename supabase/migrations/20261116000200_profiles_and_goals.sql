-- Profile and goals (PRD §5.1). One profile per account; goals are
-- effective-dated so history is never rewritten.

create table public.profiles (
  id                       uuid primary key references auth.users (id) on delete cascade,
  display_name             text not null check (char_length(btrim(display_name)) between 1 and 80),
  date_of_birth            date,
  height_mm                integer check (height_mm between 300 and 3000),
  weight_unit              text not null check (weight_unit in ('kg', 'lb')),
  length_unit              text not null check (length_unit in ('cm', 'in')),
  volume_unit              text not null check (volume_unit in ('ml', 'fl_oz')),
  distance_unit            text not null check (distance_unit in ('km', 'mi')),
  timezone                 text not null,
  wake_time                text check (wake_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  workout_days             jsonb not null default '[]'::jsonb,
  custom_measurement_types jsonb not null default '[]'::jsonb,
  onboarding_completed_at  timestamptz,
  created_at               timestamptz not null,
  updated_at               timestamptz not null,
  deleted_at               timestamptz,
  server_updated_at        timestamptz not null default now()
);

create index profiles_cursor_idx on public.profiles (id, server_updated_at);

alter table public.profiles enable row level security;
revoke all on table public.profiles from anon;
grant select, insert, update, delete on table public.profiles to authenticated;

create policy profiles_select on public.profiles for select to authenticated
  using ((select auth.uid()) = id);
create policy profiles_insert on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);
create policy profiles_update on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy profiles_delete on public.profiles for delete to authenticated
  using ((select auth.uid()) = id);

create trigger profiles_stale before update on public.profiles
  for each row execute function public.reject_stale_write();
create trigger profiles_cursor before insert or update on public.profiles
  for each row execute function public.set_server_updated_at();


create table public.user_goals (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  effective_from    date not null,
  target_weight_g   integer check (target_weight_g between 1000 and 700000),
  daily_steps       integer check (daily_steps between 0 and 200000),
  daily_water_ml    integer check (daily_water_ml between 0 and 20000),
  sleep_target_min  integer check (sleep_target_min between 0 and 1440),
  fitness_goals     jsonb not null default '[]'::jsonb,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index user_goals_user_date_idx on public.user_goals (user_id, effective_from);
create index user_goals_user_cursor_idx on public.user_goals (user_id, server_updated_at, id);

alter table public.user_goals enable row level security;
revoke all on table public.user_goals from anon;
grant select, insert, update, delete on table public.user_goals to authenticated;

create policy user_goals_select on public.user_goals for select to authenticated
  using ((select auth.uid()) = user_id);
create policy user_goals_insert on public.user_goals for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy user_goals_update on public.user_goals for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy user_goals_delete on public.user_goals for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger user_goals_stale before update on public.user_goals
  for each row execute function public.reject_stale_write();
create trigger user_goals_cursor before insert or update on public.user_goals
  for each row execute function public.set_server_updated_at();


create table public.nutrition_goals (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  effective_from    date not null,
  energy_kcal_milli bigint check (energy_kcal_milli between 0 and 20000000),
  protein_mg        integer check (protein_mg between 0 and 2000000),
  carbs_mg          integer check (carbs_mg between 0 and 2000000),
  fat_mg            integer check (fat_mg between 0 and 2000000),
  fibre_mg          integer check (fibre_mg between 0 and 2000000),
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index nutrition_goals_user_date_idx on public.nutrition_goals (user_id, effective_from);
create index nutrition_goals_user_cursor_idx on public.nutrition_goals (user_id, server_updated_at, id);

alter table public.nutrition_goals enable row level security;
revoke all on table public.nutrition_goals from anon;
grant select, insert, update, delete on table public.nutrition_goals to authenticated;

create policy nutrition_goals_select on public.nutrition_goals for select to authenticated
  using ((select auth.uid()) = user_id);
create policy nutrition_goals_insert on public.nutrition_goals for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy nutrition_goals_update on public.nutrition_goals for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy nutrition_goals_delete on public.nutrition_goals for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger nutrition_goals_stale before update on public.nutrition_goals
  for each row execute function public.reject_stale_write();
create trigger nutrition_goals_cursor before insert or update on public.nutrition_goals
  for each row execute function public.set_server_updated_at();
