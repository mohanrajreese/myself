-- Row Level Security and trigger checks. Plain SQL: any failed check raises
-- an exception and stops the script. Run with supabase/tests/run_local.sh,
-- or against a test project with psql.
\set ON_ERROR_STOP on
begin;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b');

create schema t;
grant usage on schema t to anon, authenticated;

create function t.login(who text) returns void language plpgsql as $$
begin
  if who = 'anon' then
    perform set_config('request.jwt.claim.sub', '', true);
    set local role anon;
  else
    perform set_config(
      'request.jwt.claim.sub',
      '00000000-0000-0000-0000-00000000000' || who,
      true
    );
    set local role authenticated;
  end if;
end $$;

create function t.eq(actual bigint, expected bigint, label text) returns void language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'FAILED: % (expected %, got %)', label, expected, actual;
  end if;
  raise notice 'ok - %', label;
end $$;

-- Runs a statement that must be refused, as the current role.
create function t.refused(statement text, label text) returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when insufficient_privilege or check_violation or foreign_key_violation then
    raise notice 'ok - %', label;
    return;
  end;
  raise exception 'FAILED: % (statement was allowed)', label;
end $$;
grant execute on all functions in schema t to anon, authenticated;

-- ---------------------------------------------------------------- user A writes
select t.login('a');
insert into public.profiles (id, display_name, weight_unit, length_unit, volume_unit, distance_unit,
                             timezone, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000000a', 'A', 'kg', 'cm', 'ml', 'km', 'Asia/Kolkata',
        '2026-11-16T09:00:00Z', '2026-11-16T09:00:00Z');
insert into public.user_goals (id, effective_from, daily_steps, created_at, updated_at)
values ('10000000-0000-0000-0000-000000000001', '2026-11-16', 8000,
        '2026-11-16T09:00:00Z', '2026-11-16T09:00:00Z');
insert into public.nutrition_goals (id, effective_from, protein_mg, created_at, updated_at)
values ('20000000-0000-0000-0000-000000000001', '2026-11-16', 120000,
        '2026-11-16T09:00:00Z', '2026-11-16T09:00:00Z');
insert into public.weight_logs (id, weight_g, entry_unit, occurred_at, local_date, tz, created_at, updated_at)
values ('30000000-0000-0000-0000-000000000001', 91800, 'kg', '2026-11-16T03:30:00Z', '2026-11-16',
        'Asia/Kolkata', '2026-11-16T09:00:00Z', '2026-11-16T09:00:00Z');

select t.eq((select count(*) from public.profiles), 1, 'owner sees own profile');
select t.eq((select count(*) from public.user_goals), 1, 'owner sees own goals');
select t.eq((select count(*) from public.nutrition_goals), 1, 'owner sees own nutrition goals');
select t.eq((select count(*) from public.weight_logs), 1, 'owner sees own weight');
select t.eq((select count(*) from public.weight_logs
             where user_id = '00000000-0000-0000-0000-00000000000a'), 1,
            'user_id defaults to the signed-in account');

-- ---------------------------------------------------------------- user B is shut out
reset role;
select t.login('b');
select t.eq((select count(*) from public.profiles), 0, 'other user cannot read profiles');
select t.eq((select count(*) from public.user_goals), 0, 'other user cannot read goals');
select t.eq((select count(*) from public.nutrition_goals), 0, 'other user cannot read nutrition goals');
select t.eq((select count(*) from public.weight_logs), 0, 'other user cannot read weight');

with changed as (update public.profiles set display_name = 'hacked' returning 1)
select t.eq((select count(*) from changed), 0, 'other user cannot update profiles');
with changed as (update public.user_goals set daily_steps = 1 returning 1)
select t.eq((select count(*) from changed), 0, 'other user cannot update goals');
with changed as (update public.nutrition_goals set protein_mg = 1 returning 1)
select t.eq((select count(*) from changed), 0, 'other user cannot update nutrition goals');
with changed as (update public.weight_logs set weight_g = 50000 returning 1)
select t.eq((select count(*) from changed), 0, 'other user cannot update weight');

with gone as (delete from public.profiles returning 1)
select t.eq((select count(*) from gone), 0, 'other user cannot delete profiles');
with gone as (delete from public.user_goals returning 1)
select t.eq((select count(*) from gone), 0, 'other user cannot delete goals');
with gone as (delete from public.nutrition_goals returning 1)
select t.eq((select count(*) from gone), 0, 'other user cannot delete nutrition goals');
with gone as (delete from public.weight_logs returning 1)
select t.eq((select count(*) from gone), 0, 'other user cannot delete weight');

select t.refused($$insert into public.weight_logs (id, user_id, weight_g, entry_unit, occurred_at, local_date, tz, created_at, updated_at)
  values ('30000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 80000, 'kg',
          now(), '2026-11-16', 'UTC', now(), now())$$,
  'cannot insert a weight row owned by someone else');
select t.refused($$insert into public.user_goals (id, user_id, effective_from, created_at, updated_at)
  values ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', '2026-11-16', now(), now())$$,
  'cannot insert goals owned by someone else');
select t.refused($$insert into public.profiles (id, display_name, weight_unit, length_unit, volume_unit, distance_unit, timezone, created_at, updated_at)
  values ('00000000-0000-0000-0000-00000000000a', 'x', 'kg', 'cm', 'ml', 'km', 'UTC', now(), now())$$,
  'cannot create a profile for another account');

-- ---------------------------------------------------------------- anonymous role
reset role;
select t.login('anon');
select t.refused('select 1 from public.profiles', 'anon cannot read profiles');
select t.refused('select 1 from public.user_goals', 'anon cannot read goals');
select t.refused('select 1 from public.nutrition_goals', 'anon cannot read nutrition goals');
select t.refused('select 1 from public.weight_logs', 'anon cannot read weight');
select t.refused($$insert into public.weight_logs (id, weight_g, entry_unit, occurred_at, local_date, tz, created_at, updated_at)
  values ('30000000-0000-0000-0000-000000000003', 80000, 'kg', now(), '2026-11-16', 'UTC', now(), now())$$,
  'anon cannot insert weight');

-- ---------------------------------------------------------------- constraints
reset role;
select t.login('a');
select t.refused($$update public.weight_logs set weight_g = 5, updated_at = '2026-11-17T00:00:00Z'$$,
  'weight outside the valid range is rejected');
select t.refused($$update public.profiles set weight_unit = 'stone', updated_at = '2026-11-17T00:00:00Z'$$,
  'unknown unit is rejected');
select t.refused($$update public.profiles set wake_time = '25:00', updated_at = '2026-11-17T00:00:00Z'$$,
  'malformed wake time is rejected');

-- ---------------------------------------------------------------- last write wins
update public.weight_logs set weight_g = 90000, updated_at = '2026-11-16T08:00:00Z';
select t.eq((select weight_g from public.weight_logs), 91800, 'an older write is ignored');

select pg_sleep(0.01);
update public.weight_logs set weight_g = 91200, updated_at = '2026-11-16T10:00:00Z';
select t.eq((select weight_g from public.weight_logs), 91200, 'a newer write is applied');
select t.eq((select count(*) from public.weight_logs where server_updated_at > created_at), 1,
            'server_updated_at is set by the server');

-- ---------------------------------------------------------------- Phase 2 tables
reset role;
create function t.phase2_tables() returns text[] language sql as $$
  select array['body_measurements', 'water_logs', 'food_items', 'meal_logs', 'meal_food_items',
               'saved_meals', 'sleep_logs', 'daily_health_checkins']
$$;
create function t.count_visible(tbl text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute format('select count(*) from public.%I', tbl) into n;
  return n;
end $$;
create function t.count_changed(statement text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute statement;
  get diagnostics n = row_count;
  return n;
end $$;

grant execute on all functions in schema t to anon, authenticated;

select t.login('a');
insert into public.body_measurements (id, measurement_type, value_milli, unit, entry_unit, occurred_at, local_date, tz, created_at, updated_at)
values ('40000000-0000-0000-0000-000000000001', 'waist', 92000, 'cm', 'cm', now(), '2026-11-16', 'UTC', now(), now());
insert into public.water_logs (id, amount_ml, occurred_at, local_date, tz, created_at, updated_at)
values ('41000000-0000-0000-0000-000000000001', 250, now(), '2026-11-16', 'UTC', now(), now());
insert into public.food_items (id, name, serving_label, serving_qty_milli, serving_unit, energy_kcal_milli, protein_mg, carbs_mg, fat_mg, fibre_mg, created_at, updated_at)
values ('42000000-0000-0000-0000-000000000001', 'Dal', '1 bowl', 1000, 'bowl', 230000, 12000, 30000, 6000, 8000, now(), now());
insert into public.meal_logs (id, meal_category, occurred_at, local_date, tz, created_at, updated_at)
values ('43000000-0000-0000-0000-000000000001', 'lunch', now(), '2026-11-16', 'UTC', now(), now());
insert into public.meal_food_items (id, meal_log_id, food_item_id, food_name, quantity_milli, unit, energy_kcal_milli, protein_mg, carbs_mg, fat_mg, fibre_mg, created_at, updated_at)
values ('44000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000001', '42000000-0000-0000-0000-000000000001', 'Dal', 1000, 'bowl', 230000, 12000, 30000, 6000, 8000, now(), now());
insert into public.saved_meals (id, name, created_at, updated_at)
values ('45000000-0000-0000-0000-000000000001', 'Usual lunch', now(), now());
insert into public.sleep_logs (id, kind, start_at, end_at, duration_s, quality, local_date, tz, created_at, updated_at)
values ('46000000-0000-0000-0000-000000000001', 'night', '2026-11-15T17:40:00Z', '2026-11-16T00:45:00Z', 25500, 4, '2026-11-16', 'Asia/Kolkata', now(), now());
insert into public.daily_health_checkins (id, energy, mood, stress, wellness, occurred_at, local_date, tz, created_at, updated_at)
values ('47000000-0000-0000-0000-000000000001', 4, 3, 2, 4, now(), '2026-11-16', 'UTC', now(), now());

select t.eq(t.count_visible(tbl), 1, 'owner sees own ' || tbl) from unnest(t.phase2_tables()) tbl;

select t.refused($$update public.sleep_logs set quality = 9, updated_at = now() + interval '1 hour'$$,
  'sleep quality outside 1 to 5 is rejected');
select t.refused($$update public.daily_health_checkins set mood = 0, updated_at = now() + interval '1 hour'$$,
  'check-in score outside 1 to 5 is rejected');
select t.refused($$update public.meal_logs set meal_category = 'brunch', updated_at = now() + interval '1 hour'$$,
  'unknown meal category is rejected');
select t.refused($$update public.food_items set junk_category = 'crisps', updated_at = now() + interval '1 hour'$$,
  'unknown junk-food category is rejected');
select t.refused($$update public.water_logs set amount_ml = 0, updated_at = now() + interval '1 hour'$$,
  'zero water amount is rejected');
update public.food_items set catalogue_ref = 'indb:ASC144', updated_at = now() + interval '1 hour';
select t.eq((select count(*) from public.food_items where catalogue_ref = 'indb:ASC144'), 1,
            'an edited catalogue food keeps its reference');
select t.refused($$update public.food_items set catalogue_ref = 'not a ref', updated_at = now() + interval '2 hours'$$,
  'a malformed catalogue reference is rejected');

reset role;
select t.login('b');
select t.eq(t.count_visible(tbl), 0, 'other user cannot read ' || tbl) from unnest(t.phase2_tables()) tbl;
select t.eq(t.count_changed(format('update public.%I set updated_at = now() + interval ''2 hours''', tbl)), 0,
            'other user cannot update ' || tbl) from unnest(t.phase2_tables()) tbl;
select t.eq(t.count_changed(format('delete from public.%I', tbl)), 0,
            'other user cannot delete ' || tbl) from unnest(t.phase2_tables()) tbl;
select t.refused($$insert into public.meal_food_items (id, meal_log_id, food_name, quantity_milli, unit, energy_kcal_milli, protein_mg, carbs_mg, fat_mg, fibre_mg, created_at, updated_at)
  values ('44000000-0000-0000-0000-000000000002', '43000000-0000-0000-0000-000000000001', 'x', 1000, 'g', 0, 0, 0, 0, 0, now(), now())$$,
  'cannot attach an item to another user''s meal');
select t.refused($$insert into public.water_logs (id, user_id, amount_ml, occurred_at, local_date, tz, created_at, updated_at)
  values ('41000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 250, now(), '2026-11-16', 'UTC', now(), now())$$,
  'cannot insert water owned by someone else');

reset role;
select t.login('anon');
select t.refused(format('select 1 from public.%I', tbl), 'anon cannot read ' || tbl)
from unnest(t.phase2_tables()) tbl;

-- Deleting a food keeps the meal item and its snapshot.
reset role;
select t.login('a');
delete from public.food_items where id = '42000000-0000-0000-0000-000000000001';
select t.eq((select count(*) from public.meal_food_items where food_item_id is null and energy_kcal_milli = 230000), 1,
            'deleting a food keeps the meal item with its snapshot');
-- Deleting a meal removes its items.
delete from public.meal_logs where id = '43000000-0000-0000-0000-000000000001';
select t.eq((select count(*) from public.meal_food_items), 0, 'deleting a meal removes its items');

-- ---------------------------------------------------------------- account deletion
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select t.eq((select count(*) from public.profiles), 0, 'deleting the account removes the profile');
select t.eq((select count(*) from public.user_goals), 0, 'deleting the account removes goals');
select t.eq((select count(*) from public.nutrition_goals), 0, 'deleting the account removes nutrition goals');
select t.eq((select count(*) from public.weight_logs), 0, 'deleting the account removes weight');

rollback;
\echo ALL CHECKS PASSED
