-- Money (PRD §5.21, 03 §2.8). Amounts are integer paise. Receipt photos
-- stay on the phone and have no cloud table (C2). Reminders for EMIs and
-- recurring expenses are derived on the phone from these rows.

create table public.finance_categories (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 40),
  system_key        text,
  icon_key          text not null,
  archived          boolean not null default false,
  sort_order        integer not null default 0,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create index finance_categories_user_cursor_idx on public.finance_categories (user_id, server_updated_at, id);

alter table public.finance_categories enable row level security;
revoke all on table public.finance_categories from anon;
grant select, insert, update, delete on table public.finance_categories to authenticated;

create policy finance_categories_select on public.finance_categories for select to authenticated
  using ((select auth.uid()) = user_id);
create policy finance_categories_insert on public.finance_categories for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy finance_categories_update on public.finance_categories for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy finance_categories_delete on public.finance_categories for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger finance_categories_stale before update on public.finance_categories
  for each row execute function public.reject_stale_write();
create trigger finance_categories_cursor before insert or update on public.finance_categories
  for each row execute function public.set_server_updated_at();

create table public.debts (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  direction         text not null check (direction in ('i_owe', 'owed_to_me')),
  name              text not null check (length(name) between 1 and 60),
  counterparty      text not null check (length(counterparty) between 1 and 60),
  kind              text not null check (kind in ('personal', 'bank_loan', 'credit_card', 'other')),
  principal_paise   bigint not null check (principal_paise > 0),
  interest_rate_bp  integer check (interest_rate_bp between 0 and 10000),
  start_date        date not null,
  due_date          date,
  emi_paise         bigint check (emi_paise > 0),
  emi_day           smallint check (emi_day between 1 and 28),
  emi_count         smallint check (emi_count between 1 and 600),
  first_emi_date    date,
  remind            boolean not null default true,
  remind_days_before smallint not null default 7 check (remind_days_before between 7 and 30),
  record_as_expense boolean not null default true,
  status            text not null check (status in ('open', 'settled')),
  notes             text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  check ((emi_paise is null and emi_day is null and emi_count is null and first_emi_date is null)
      or (emi_paise is not null and emi_day is not null and emi_count is not null and first_emi_date is not null)),
  unique (id, user_id)
);

create index debts_user_cursor_idx on public.debts (user_id, server_updated_at, id);

alter table public.debts enable row level security;
revoke all on table public.debts from anon;
grant select, insert, update, delete on table public.debts to authenticated;

create policy debts_select on public.debts for select to authenticated
  using ((select auth.uid()) = user_id);
create policy debts_insert on public.debts for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy debts_update on public.debts for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy debts_delete on public.debts for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger debts_stale before update on public.debts
  for each row execute function public.reject_stale_write();
create trigger debts_cursor before insert or update on public.debts
  for each row execute function public.set_server_updated_at();

create table public.debt_payments (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  debt_id           uuid not null,
  amount_paise      bigint not null check (amount_paise > 0),
  paid_at           timestamptz not null,
  local_date        date not null,
  tz                text not null,
  instalment_no     smallint check (instalment_no > 0),
  note              text,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (debt_id, user_id) references public.debts (id, user_id) on delete cascade,
  unique (id, user_id)
);

create index debt_payments_user_cursor_idx on public.debt_payments (user_id, server_updated_at, id);
create index debt_payments_user_debt_idx on public.debt_payments (user_id, debt_id, local_date);

alter table public.debt_payments enable row level security;
revoke all on table public.debt_payments from anon;
grant select, insert, update, delete on table public.debt_payments to authenticated;

create policy debt_payments_select on public.debt_payments for select to authenticated
  using ((select auth.uid()) = user_id);
create policy debt_payments_insert on public.debt_payments for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy debt_payments_update on public.debt_payments for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy debt_payments_delete on public.debt_payments for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger debt_payments_stale before update on public.debt_payments
  for each row execute function public.reject_stale_write();
create trigger debt_payments_cursor before insert or update on public.debt_payments
  for each row execute function public.set_server_updated_at();

create table public.recurring_expenses (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name              text not null check (length(name) between 1 and 60),
  amount_paise      bigint not null check (amount_paise > 0),
  category_id       uuid not null,
  method            text not null check (method in ('cash', 'upi', 'debit_card', 'credit_card', 'net_banking', 'other')),
  schedule          jsonb not null,
  remind            boolean not null default true,
  active            boolean not null default true,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (category_id, user_id) references public.finance_categories (id, user_id),
  unique (id, user_id)
);

create index recurring_expenses_user_cursor_idx on public.recurring_expenses (user_id, server_updated_at, id);

alter table public.recurring_expenses enable row level security;
revoke all on table public.recurring_expenses from anon;
grant select, insert, update, delete on table public.recurring_expenses to authenticated;

create policy recurring_expenses_select on public.recurring_expenses for select to authenticated
  using ((select auth.uid()) = user_id);
create policy recurring_expenses_insert on public.recurring_expenses for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy recurring_expenses_update on public.recurring_expenses for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy recurring_expenses_delete on public.recurring_expenses for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger recurring_expenses_stale before update on public.recurring_expenses
  for each row execute function public.reject_stale_write();
create trigger recurring_expenses_cursor before insert or update on public.recurring_expenses
  for each row execute function public.set_server_updated_at();

create table public.expenses (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  amount_paise      bigint not null check (amount_paise > 0),
  category_id       uuid not null,
  method            text not null check (method in ('cash', 'upi', 'debit_card', 'credit_card', 'net_banking', 'other')),
  occurred_at       timestamptz not null,
  local_date        date not null,
  tz                text not null,
  note              text,
  meal_log_id       uuid,
  debt_payment_id   uuid,
  recurring_expense_id uuid,
  has_receipt       boolean not null default false,
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (category_id, user_id) references public.finance_categories (id, user_id),
  foreign key (meal_log_id, user_id) references public.meal_logs (id, user_id) on delete set null (meal_log_id),
  foreign key (debt_payment_id, user_id) references public.debt_payments (id, user_id) on delete set null (debt_payment_id),
  foreign key (recurring_expense_id, user_id) references public.recurring_expenses (id, user_id) on delete set null (recurring_expense_id),
  unique (id, user_id)
);

create index expenses_user_cursor_idx on public.expenses (user_id, server_updated_at, id);
create index expenses_user_date_idx on public.expenses (user_id, local_date);

alter table public.expenses enable row level security;
revoke all on table public.expenses from anon;
grant select, insert, update, delete on table public.expenses to authenticated;

create policy expenses_select on public.expenses for select to authenticated
  using ((select auth.uid()) = user_id);
create policy expenses_insert on public.expenses for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy expenses_update on public.expenses for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy expenses_delete on public.expenses for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger expenses_stale before update on public.expenses
  for each row execute function public.reject_stale_write();
create trigger expenses_cursor before insert or update on public.expenses
  for each row execute function public.set_server_updated_at();

create table public.budgets (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  effective_from    date not null,
  category_id       uuid,
  amount_paise      bigint not null check (amount_paise >= 0), -- 0: no budget from effective_from
  created_at        timestamptz not null,
  updated_at        timestamptz not null,
  deleted_at        timestamptz,
  server_updated_at timestamptz not null default now(),
  foreign key (category_id, user_id) references public.finance_categories (id, user_id),
  unique (id, user_id)
);

create index budgets_user_cursor_idx on public.budgets (user_id, server_updated_at, id);

alter table public.budgets enable row level security;
revoke all on table public.budgets from anon;
grant select, insert, update, delete on table public.budgets to authenticated;

create policy budgets_select on public.budgets for select to authenticated
  using ((select auth.uid()) = user_id);
create policy budgets_insert on public.budgets for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy budgets_update on public.budgets for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy budgets_delete on public.budgets for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger budgets_stale before update on public.budgets
  for each row execute function public.reject_stale_write();
create trigger budgets_cursor before insert or update on public.budgets
  for each row execute function public.set_server_updated_at();
