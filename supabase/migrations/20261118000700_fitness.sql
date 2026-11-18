-- Fitness (PRD §5.6–5.8): daily step totals only (raw readings and GPS
-- routes stay on the phone, §6.6, C3), exercises, workouts, sets, templates.

create table public.step_logs (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  log_date          date not null,
  steps             integer not null check (steps >= 0),
  source            text not null check (source in ('phone_sensor', 'phone_sensor_adjusted', 'manual')),
  timezone          text not null,
  collected_at      timestamptz,
  unique (user_id, log_date),
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index step_logs_user_cursor_idx on public.step_logs (user_id, server_updated_at, id);

alter table public.step_logs enable row level security;
revoke all on table public.step_logs from anon;
grant select, insert, update, delete on table public.step_logs to authenticated;

create policy step_logs_select on public.step_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy step_logs_insert on public.step_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy step_logs_update on public.step_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy step_logs_delete on public.step_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger step_logs_stale before update on public.step_logs
  for each row execute function public.reject_stale_write();
create trigger step_logs_cursor before insert or update on public.step_logs
  for each row execute function public.set_server_updated_at();

create table public.exercises (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 80),
  category          text not null,
  muscle_group      text not null,
  equipment         text not null,
  instructions      text,
  is_custom         boolean not null default false,
  measurement_kind  text not null check (measurement_kind in ('weight_reps', 'reps_only', 'duration', 'distance_duration')),
  system_key        text,
  archived          boolean not null default false,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index exercises_user_cursor_idx on public.exercises (user_id, server_updated_at, id);

alter table public.exercises enable row level security;
revoke all on table public.exercises from anon;
grant select, insert, update, delete on table public.exercises to authenticated;

create policy exercises_select on public.exercises for select to authenticated
  using ((select auth.uid()) = user_id);
create policy exercises_insert on public.exercises for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy exercises_update on public.exercises for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy exercises_delete on public.exercises for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger exercises_stale before update on public.exercises
  for each row execute function public.reject_stale_write();
create trigger exercises_cursor before insert or update on public.exercises
  for each row execute function public.set_server_updated_at();

create table public.workout_sessions (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind              text not null check (kind in ('gym', 'walk', 'run', 'cycle')),
  name              text not null,
  started_at        timestamptz not null,
  ended_at          timestamptz,
  duration_s        integer not null check (duration_s between 0 and 86400),
  local_date        date not null,
  tz                text not null,
  distance_m        integer check (distance_m between 0 and 500000),
  steps             integer,
  entry_mode        text not null check (entry_mode in ('manual', 'gps')),
  has_route         boolean not null default false,
  template_id       uuid,
  notes             text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index workout_sessions_user_cursor_idx on public.workout_sessions (user_id, server_updated_at, id);
create index workout_sessions_user_date_idx on public.workout_sessions (user_id, local_date);

alter table public.workout_sessions enable row level security;
revoke all on table public.workout_sessions from anon;
grant select, insert, update, delete on table public.workout_sessions to authenticated;

create policy workout_sessions_select on public.workout_sessions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy workout_sessions_insert on public.workout_sessions for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy workout_sessions_update on public.workout_sessions for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy workout_sessions_delete on public.workout_sessions for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger workout_sessions_stale before update on public.workout_sessions
  for each row execute function public.reject_stale_write();
create trigger workout_sessions_cursor before insert or update on public.workout_sessions
  for each row execute function public.set_server_updated_at();

create table public.workout_exercises (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  session_id        uuid not null,
  exercise_id       uuid not null,
  sort_order        integer not null default 0,
  notes             text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (session_id, user_id) references public.workout_sessions (id, user_id) on delete cascade,
  foreign key (exercise_id, user_id) references public.exercises (id, user_id),
  unique (id, user_id)
);

create index workout_exercises_user_cursor_idx on public.workout_exercises (user_id, server_updated_at, id);
create index workout_exercises_user_session_idx on public.workout_exercises (user_id, session_id);

alter table public.workout_exercises enable row level security;
revoke all on table public.workout_exercises from anon;
grant select, insert, update, delete on table public.workout_exercises to authenticated;

create policy workout_exercises_select on public.workout_exercises for select to authenticated
  using ((select auth.uid()) = user_id);
create policy workout_exercises_insert on public.workout_exercises for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy workout_exercises_update on public.workout_exercises for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy workout_exercises_delete on public.workout_exercises for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger workout_exercises_stale before update on public.workout_exercises
  for each row execute function public.reject_stale_write();
create trigger workout_exercises_cursor before insert or update on public.workout_exercises
  for each row execute function public.set_server_updated_at();

create table public.exercise_sets (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  workout_exercise_id uuid not null,
  set_number        integer not null check (set_number >= 1),
  reps              integer check (reps between 0 and 1000),
  load_g            integer check (load_g between 0 and 1000000),
  entry_unit        text check (entry_unit in ('kg', 'lb')),
  distance_m        integer check (distance_m between 0 and 500000),
  duration_s        integer check (duration_s between 0 and 86400),
  rest_s            integer check (rest_s between 0 and 3600),
  completed_at      timestamptz,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (workout_exercise_id, user_id) references public.workout_exercises (id, user_id) on delete cascade,
  unique (id, user_id)
);

create index exercise_sets_user_cursor_idx on public.exercise_sets (user_id, server_updated_at, id);
create index exercise_sets_user_parent_idx on public.exercise_sets (user_id, workout_exercise_id);

alter table public.exercise_sets enable row level security;
revoke all on table public.exercise_sets from anon;
grant select, insert, update, delete on table public.exercise_sets to authenticated;

create policy exercise_sets_select on public.exercise_sets for select to authenticated
  using ((select auth.uid()) = user_id);
create policy exercise_sets_insert on public.exercise_sets for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy exercise_sets_update on public.exercise_sets for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy exercise_sets_delete on public.exercise_sets for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger exercise_sets_stale before update on public.exercise_sets
  for each row execute function public.reject_stale_write();
create trigger exercise_sets_cursor before insert or update on public.exercise_sets
  for each row execute function public.set_server_updated_at();

create table public.workout_templates (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 80),
  exercises         jsonb not null,
  use_count         integer not null default 0,
  last_used_at      timestamptz,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index workout_templates_user_cursor_idx on public.workout_templates (user_id, server_updated_at, id);

alter table public.workout_templates enable row level security;
revoke all on table public.workout_templates from anon;
grant select, insert, update, delete on table public.workout_templates to authenticated;

create policy workout_templates_select on public.workout_templates for select to authenticated
  using ((select auth.uid()) = user_id);
create policy workout_templates_insert on public.workout_templates for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy workout_templates_update on public.workout_templates for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy workout_templates_delete on public.workout_templates for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger workout_templates_stale before update on public.workout_templates
  for each row execute function public.reject_stale_write();
create trigger workout_templates_cursor before insert or update on public.workout_templates
  for each row execute function public.set_server_updated_at();
