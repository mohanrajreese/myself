-- Money additions (PRD §5.22, 03 §2.9): loan changes and skipped
-- instalments, credit-card statements, income, bill splits, and new columns
-- for cards, due reminders, income sources and recurring income.

alter table public.finance_categories
  add column kind text not null default 'expense' check (kind in ('expense', 'income'));

alter table public.debts
  add column credit_limit_paise bigint check (credit_limit_paise > 0),
  add column statement_day smallint check (statement_day between 1 and 28),
  add column card_due_day smallint check (card_due_day between 1 and 28),
  add column due_remind boolean not null default false,
  add column due_remind_days smallint not null default 0 check (due_remind_days in (0, 1, 7));

alter table public.recurring_expenses
  add column kind text not null default 'expense' check (kind in ('expense', 'income'));

alter table public.expenses
  add column card_debt_id uuid,
  add foreign key (card_debt_id, user_id) references public.debts (id, user_id) on delete set null (card_debt_id);

create table public.loan_changes (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  debt_id           uuid not null,
  kind              text not null check (kind in ('prepayment', 'rate_change', 'balance_correction')),
  effective_date    date not null,
  from_instalment   smallint check (from_instalment > 0),
  amount_paise      bigint check (amount_paise >= 0),
  rate_bp           integer check (rate_bp between 0 and 10000),
  emi_paise         bigint check (emi_paise > 0),
  instalments_left  smallint check (instalments_left between 1 and 600),
  mode              text check (mode in ('reduce_tenure', 'reduce_emi')),
  payment_id        uuid,
  note              text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (debt_id, user_id) references public.debts (id, user_id) on delete cascade,
  foreign key (payment_id, user_id) references public.debt_payments (id, user_id) on delete set null (payment_id),
  unique (id, user_id)
);

create index loan_changes_user_cursor_idx on public.loan_changes (user_id, server_updated_at, id);
create index loan_changes_user_debt_idx on public.loan_changes (user_id, debt_id, effective_date);

alter table public.loan_changes enable row level security;
revoke all on table public.loan_changes from anon;
grant select, insert, update, delete on table public.loan_changes to authenticated;

create policy loan_changes_select on public.loan_changes for select to authenticated
  using ((select auth.uid()) = user_id);
create policy loan_changes_insert on public.loan_changes for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy loan_changes_update on public.loan_changes for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy loan_changes_delete on public.loan_changes for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger loan_changes_stale before update on public.loan_changes
  for each row execute function public.reject_stale_write();
create trigger loan_changes_cursor before insert or update on public.loan_changes
  for each row execute function public.set_server_updated_at();

create table public.instalment_skips (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  debt_id           uuid not null,
  instalment_no     smallint not null check (instalment_no > 0),
  skipped_on        date not null,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (debt_id, user_id) references public.debts (id, user_id) on delete cascade,
  unique (id, user_id)
);

create index instalment_skips_user_cursor_idx on public.instalment_skips (user_id, server_updated_at, id);
create index instalment_skips_user_debt_idx on public.instalment_skips (user_id, debt_id, instalment_no);

alter table public.instalment_skips enable row level security;
revoke all on table public.instalment_skips from anon;
grant select, insert, update, delete on table public.instalment_skips to authenticated;

create policy instalment_skips_select on public.instalment_skips for select to authenticated
  using ((select auth.uid()) = user_id);
create policy instalment_skips_insert on public.instalment_skips for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy instalment_skips_update on public.instalment_skips for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy instalment_skips_delete on public.instalment_skips for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger instalment_skips_stale before update on public.instalment_skips
  for each row execute function public.reject_stale_write();
create trigger instalment_skips_cursor before insert or update on public.instalment_skips
  for each row execute function public.set_server_updated_at();

create table public.card_statements (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  debt_id           uuid not null,
  statement_date    date not null,
  due_date          date not null check (due_date >= statement_date),
  total_due_paise   bigint not null check (total_due_paise >= 0),
  min_due_paise     bigint not null check (min_due_paise >= 0 and min_due_paise <= total_due_paise),
  remind            boolean not null default true,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (debt_id, user_id) references public.debts (id, user_id) on delete cascade,
  unique (id, user_id)
);

create index card_statements_user_cursor_idx on public.card_statements (user_id, server_updated_at, id);
create index card_statements_user_debt_idx on public.card_statements (user_id, debt_id, statement_date);

alter table public.card_statements enable row level security;
revoke all on table public.card_statements from anon;
grant select, insert, update, delete on table public.card_statements to authenticated;

create policy card_statements_select on public.card_statements for select to authenticated
  using ((select auth.uid()) = user_id);
create policy card_statements_insert on public.card_statements for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy card_statements_update on public.card_statements for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy card_statements_delete on public.card_statements for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger card_statements_stale before update on public.card_statements
  for each row execute function public.reject_stale_write();
create trigger card_statements_cursor before insert or update on public.card_statements
  for each row execute function public.set_server_updated_at();

create table public.incomes (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  amount_paise      bigint not null check (amount_paise > 0),
  category_id       uuid not null,
  occurred_at       timestamptz not null,
  local_date        date not null,
  tz                text not null,
  note              text,
  recurring_id      uuid,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (category_id, user_id) references public.finance_categories (id, user_id),
  foreign key (recurring_id, user_id) references public.recurring_expenses (id, user_id) on delete set null (recurring_id),
  unique (id, user_id)
);

create index incomes_user_cursor_idx on public.incomes (user_id, server_updated_at, id);
create index incomes_user_date_idx on public.incomes (user_id, local_date);

alter table public.incomes enable row level security;
revoke all on table public.incomes from anon;
grant select, insert, update, delete on table public.incomes to authenticated;

create policy incomes_select on public.incomes for select to authenticated
  using ((select auth.uid()) = user_id);
create policy incomes_insert on public.incomes for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy incomes_update on public.incomes for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy incomes_delete on public.incomes for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger incomes_stale before update on public.incomes
  for each row execute function public.reject_stale_write();
create trigger incomes_cursor before insert or update on public.incomes
  for each row execute function public.set_server_updated_at();

create table public.expense_splits (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  expense_id        uuid not null,
  person            text not null check (length(person) between 1 and 60),
  share_paise       bigint not null check (share_paise > 0),
  debt_id           uuid,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (expense_id, user_id) references public.expenses (id, user_id) on delete cascade,
  foreign key (debt_id, user_id) references public.debts (id, user_id) on delete set null (debt_id),
  unique (id, user_id)
);

create index expense_splits_user_cursor_idx on public.expense_splits (user_id, server_updated_at, id);
create index expense_splits_user_expense_idx on public.expense_splits (user_id, expense_id);

alter table public.expense_splits enable row level security;
revoke all on table public.expense_splits from anon;
grant select, insert, update, delete on table public.expense_splits to authenticated;

create policy expense_splits_select on public.expense_splits for select to authenticated
  using ((select auth.uid()) = user_id);
create policy expense_splits_insert on public.expense_splits for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy expense_splits_update on public.expense_splits for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy expense_splits_delete on public.expense_splits for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger expense_splits_stale before update on public.expense_splits
  for each row execute function public.reject_stale_write();
create trigger expense_splits_cursor before insert or update on public.expense_splits
  for each row execute function public.set_server_updated_at();
