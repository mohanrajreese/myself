-- A food can be the user's edited copy of a bundled catalogue food
-- (`<source>:<id>`, for example `indb:ASC144`). The catalogue itself is
-- reference data on the phone and is not stored here.

alter table public.food_items add column catalogue_ref text
  check (catalogue_ref is null or catalogue_ref ~ '^[a-z]+:[A-Za-z0-9_.-]+$');

create index food_items_user_catalogue_ref_idx on public.food_items (user_id, catalogue_ref)
  where catalogue_ref is not null;
