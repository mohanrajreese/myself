-- Shared trigger functions for every user-owned table.
-- See docs/blueprint/03-database.md §5.3.

-- Pull cursor: always the server's clock, never the device's.
create or replace function public.set_server_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.server_updated_at := now();
  return new;
end;
$$;

-- Last write wins: an update carrying an older client timestamp than the
-- stored row is ignored (the row is left as it is).
create or replace function public.reject_stale_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.updated_at < old.updated_at then
    return null;
  end if;
  return new;
end;
$$;
