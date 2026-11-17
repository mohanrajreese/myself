-- Water, foods, meals and saved meals (PRD §5.4, §5.5).
-- Meal items store a snapshot of nutrition values, so editing a food never
-- rewrites past meals.

create table public.water_logs (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  amount_ml         integer not null check (amount_ml between 1 and 5000),
  occurred_at       timestamptz not null,
  local_date        date not null,
  tz                text not null,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index water_logs_user_date_idx on public.water_logs (user_id, local_date);
create index water_logs_user_cursor_idx on public.water_logs (user_id, server_updated_at, id);

alter table public.water_logs enable row level security;
revoke all on table public.water_logs from anon;
grant select, insert, update, delete on table public.water_logs to authenticated;

create policy water_logs_select on public.water_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy water_logs_insert on public.water_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy water_logs_update on public.water_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy water_logs_delete on public.water_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger water_logs_stale before update on public.water_logs
  for each row execute function public.reject_stale_write();
create trigger water_logs_cursor before insert or update on public.water_logs
  for each row execute function public.set_server_updated_at();


create table public.food_items (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (char_length(btrim(name)) between 1 and 120),
  brand             text,
  category          text not null default 'other',
  serving_label     text not null,
  serving_qty_milli integer not null check (serving_qty_milli > 0),
  serving_unit      text not null,
  serving_weight_mg integer check (serving_weight_mg > 0),
  energy_kcal_milli bigint not null check (energy_kcal_milli >= 0),
  protein_mg        integer not null check (protein_mg >= 0),
  carbs_mg          integer not null check (carbs_mg >= 0),
  fat_mg            integer not null check (fat_mg >= 0),
  fibre_mg          integer not null check (fibre_mg >= 0),
  junk_category     text check (junk_category in ('fast_food', 'fried_snacks', 'sweets', 'sugary_drinks', 'packaged_snacks', 'other')),
  is_saved          boolean not null default false,
  use_count         integer not null default 0 check (use_count >= 0),
  last_used_at      timestamptz,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index food_items_user_name_idx on public.food_items (user_id, lower(name));
create index food_items_user_cursor_idx on public.food_items (user_id, server_updated_at, id);

alter table public.food_items enable row level security;
revoke all on table public.food_items from anon;
grant select, insert, update, delete on table public.food_items to authenticated;

create policy food_items_select on public.food_items for select to authenticated
  using ((select auth.uid()) = user_id);
create policy food_items_insert on public.food_items for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy food_items_update on public.food_items for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy food_items_delete on public.food_items for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger food_items_stale before update on public.food_items
  for each row execute function public.reject_stale_write();
create trigger food_items_cursor before insert or update on public.food_items
  for each row execute function public.set_server_updated_at();


create table public.meal_logs (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  meal_category     text not null check (meal_category in ('early_morning', 'breakfast', 'mid_morning', 'lunch', 'evening_snack', 'dinner', 'late_night', 'other')),
  occurred_at       timestamptz not null,
  local_date        date not null,
  tz                text not null,
  notes             text,
  has_photo         boolean not null default false,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index meal_logs_user_date_idx on public.meal_logs (user_id, local_date);
create index meal_logs_user_cursor_idx on public.meal_logs (user_id, server_updated_at, id);

alter table public.meal_logs enable row level security;
revoke all on table public.meal_logs from anon;
grant select, insert, update, delete on table public.meal_logs to authenticated;

create policy meal_logs_select on public.meal_logs for select to authenticated
  using ((select auth.uid()) = user_id);
create policy meal_logs_insert on public.meal_logs for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy meal_logs_update on public.meal_logs for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy meal_logs_delete on public.meal_logs for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger meal_logs_stale before update on public.meal_logs
  for each row execute function public.reject_stale_write();
create trigger meal_logs_cursor before insert or update on public.meal_logs
  for each row execute function public.set_server_updated_at();


create table public.meal_food_items (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  meal_log_id       uuid not null,
  food_item_id      uuid,
  food_name         text not null,
  quantity_milli    integer not null check (quantity_milli > 0),
  unit              text not null,
  serving_weight_mg integer check (serving_weight_mg > 0),
  energy_kcal_milli bigint not null check (energy_kcal_milli >= 0),
  protein_mg        integer not null check (protein_mg >= 0),
  carbs_mg          integer not null check (carbs_mg >= 0),
  fat_mg            integer not null check (fat_mg >= 0),
  fibre_mg          integer not null check (fibre_mg >= 0),
  junk_category     text check (junk_category in ('fast_food', 'fried_snacks', 'sweets', 'sugary_drinks', 'packaged_snacks', 'other')),
  item_notes        text,
  sort_order        integer not null default 0,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  -- A child row can only point at its owner's meal and food.
  foreign key (meal_log_id, user_id) references public.meal_logs (id, user_id) on delete cascade,
  foreign key (food_item_id, user_id) references public.food_items (id, user_id)
    on delete set null (food_item_id),
  unique (id, user_id)
);

create index meal_food_items_user_meal_idx on public.meal_food_items (user_id, meal_log_id);
create index meal_food_items_user_cursor_idx on public.meal_food_items (user_id, server_updated_at, id);

alter table public.meal_food_items enable row level security;
revoke all on table public.meal_food_items from anon;
grant select, insert, update, delete on table public.meal_food_items to authenticated;

create policy meal_food_items_select on public.meal_food_items for select to authenticated
  using ((select auth.uid()) = user_id);
create policy meal_food_items_insert on public.meal_food_items for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy meal_food_items_update on public.meal_food_items for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy meal_food_items_delete on public.meal_food_items for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger meal_food_items_stale before update on public.meal_food_items
  for each row execute function public.reject_stale_write();
create trigger meal_food_items_cursor before insert or update on public.meal_food_items
  for each row execute function public.set_server_updated_at();


create table public.saved_meals (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (char_length(btrim(name)) between 1 and 120),
  meal_category     text check (meal_category in ('early_morning', 'breakfast', 'mid_morning', 'lunch', 'evening_snack', 'dinner', 'late_night', 'other')),
  items             jsonb not null default '[]'::jsonb,
  use_count         integer not null default 0 check (use_count >= 0),
  last_used_at      timestamptz,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index saved_meals_user_cursor_idx on public.saved_meals (user_id, server_updated_at, id);

alter table public.saved_meals enable row level security;
revoke all on table public.saved_meals from anon;
grant select, insert, update, delete on table public.saved_meals to authenticated;

create policy saved_meals_select on public.saved_meals for select to authenticated
  using ((select auth.uid()) = user_id);
create policy saved_meals_insert on public.saved_meals for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy saved_meals_update on public.saved_meals for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy saved_meals_delete on public.saved_meals for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger saved_meals_stale before update on public.saved_meals
  for each row execute function public.reject_stale_write();
create trigger saved_meals_cursor before insert or update on public.saved_meals
  for each row execute function public.set_server_updated_at();
