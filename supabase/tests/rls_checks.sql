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

-- ---------------------------------------------------------------- account deletion
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select t.eq((select count(*) from public.profiles), 0, 'deleting the account removes the profile');
select t.eq((select count(*) from public.user_goals), 0, 'deleting the account removes goals');
select t.eq((select count(*) from public.nutrition_goals), 0, 'deleting the account removes nutrition goals');
select t.eq((select count(*) from public.weight_logs), 0, 'deleting the account removes weight');

rollback;
\echo ALL CHECKS PASSED
