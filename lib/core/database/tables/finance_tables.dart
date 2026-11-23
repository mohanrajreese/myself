// Drift check constraints refer to the column being defined; this is the
// documented pattern, not a recursive call at run time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../converters.dart';
import 'synced_columns.dart';
import 'tracking_tables.dart';

/// Money module (PRD §5.21, 03 §2.8). Amounts are integer paise.

const paymentMethodCodes = ['cash', 'upi', 'debit_card', 'credit_card', 'net_banking', 'other'];

@DataClassName('FinanceCategoryRow')
class FinanceCategories extends Table with SyncedColumns {
  TextColumn get name => text()();

  /// Set for seeded categories (fixed ids, like exercises, C10).
  TextColumn get systemKey => text().nullable()();
  TextColumn get iconKey => text()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Expense categories or income sources (v11, §5.22L).
  TextColumn get kind =>
      text().withDefault(const Constant('expense')).check(kind.isIn(const ['expense', 'income']))();
}

@DataClassName('DebtRow')
class Debts extends Table with SyncedColumns {
  TextColumn get direction => text().check(direction.isIn(const ['i_owe', 'owed_to_me']))();
  TextColumn get name => text()();
  TextColumn get counterparty => text()();
  TextColumn get kind =>
      text().check(kind.isIn(const ['personal', 'bank_loan', 'credit_card', 'other']))();
  IntColumn get principalPaise => integer().check(principalPaise.isBiggerThanValue(0))();

  /// Basis points a year, for reference only (850 = 8.5 %).
  IntColumn get interestRateBp => integer().nullable().check(
    interestRateBp.isNull() | interestRateBp.isBetweenValues(0, 10000),
  )();
  TextColumn get startDate => text().map(const LocalDateConverter())();
  TextColumn get dueDate => text().map(const LocalDateConverter()).nullable()();
  IntColumn get emiPaise =>
      integer().nullable().check(emiPaise.isNull() | emiPaise.isBiggerThanValue(0))();
  IntColumn get emiDay =>
      integer().nullable().check(emiDay.isNull() | emiDay.isBetweenValues(1, 28))();
  IntColumn get emiCount =>
      integer().nullable().check(emiCount.isNull() | emiCount.isBetweenValues(1, 600))();
  TextColumn get firstEmiDate => text().map(const LocalDateConverter()).nullable()();
  BoolColumn get remind => boolean().withDefault(const Constant(true))();

  /// First reminder this many days before the due date (owner: at least 7).
  IntColumn get remindDaysBefore =>
      integer().withDefault(const Constant(7)).check(remindDaysBefore.isBetweenValues(7, 30))();
  BoolColumn get recordAsExpense => boolean().withDefault(const Constant(true))();
  TextColumn get status => text().check(status.isIn(const ['open', 'settled']))();
  TextColumn get notes => text().nullable()();

  // v11 (§5.22I, J): credit cards and due-date reminders.
  IntColumn get creditLimitPaise => integer().nullable().check(
    creditLimitPaise.isNull() | creditLimitPaise.isBiggerThanValue(0),
  )();
  IntColumn get statementDay =>
      integer().nullable().check(statementDay.isNull() | statementDay.isBetweenValues(1, 28))();
  IntColumn get cardDueDay =>
      integer().nullable().check(cardDueDay.isNull() | cardDueDay.isBetweenValues(1, 28))();
  BoolColumn get dueRemind => boolean().withDefault(const Constant(false))();
  IntColumn get dueRemindDays =>
      integer().withDefault(const Constant(0)).check(dueRemindDays.isIn(const [0, 1, 7]))();

  @override
  List<String> get customConstraints => [
    'CHECK ((emi_paise IS NULL AND emi_day IS NULL AND emi_count IS NULL AND first_emi_date IS NULL) '
        'OR (emi_paise IS NOT NULL AND emi_day IS NOT NULL AND emi_count IS NOT NULL AND first_emi_date IS NOT NULL))',
  ];
}

@DataClassName('DebtPaymentRow')
@TableIndex(name: 'debt_payments_debt', columns: {#debtId, #localDate})
class DebtPayments extends Table with SyncedColumns {
  TextColumn get debtId => text().references(Debts, #id, onDelete: KeyAction.cascade)();
  IntColumn get amountPaise => integer().check(amountPaise.isBiggerThanValue(0))();
  DateTimeColumn get paidAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  IntColumn get instalmentNo =>
      integer().nullable().check(instalmentNo.isNull() | instalmentNo.isBiggerThanValue(0))();
  TextColumn get note => text().nullable()();
}

@DataClassName('RecurringExpenseRow')
class RecurringExpenses extends Table with SyncedColumns {
  TextColumn get name => text()();
  IntColumn get amountPaise => integer().check(amountPaise.isBiggerThanValue(0))();
  TextColumn get categoryId => text().references(FinanceCategories, #id)();
  TextColumn get method => text().check(method.isIn(paymentMethodCodes))();

  /// Schedule rule as JSON (`ScheduleRule`).
  TextColumn get schedule => text()();
  BoolColumn get remind => boolean().withDefault(const Constant(true))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  /// Recurring expense or recurring income (v11).
  TextColumn get kind =>
      text().withDefault(const Constant('expense')).check(kind.isIn(const ['expense', 'income']))();
}

@DataClassName('ExpenseRow')
@TableIndex(name: 'expenses_local_date', columns: {#localDate})
@TableIndex(name: 'expenses_meal', columns: {#mealLogId})
class Expenses extends Table with SyncedColumns {
  IntColumn get amountPaise => integer().check(amountPaise.isBiggerThanValue(0))();
  TextColumn get categoryId => text().references(FinanceCategories, #id)();
  TextColumn get method => text().check(method.isIn(paymentMethodCodes))();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get note => text().nullable()();
  TextColumn get mealLogId =>
      text().nullable().references(MealLogs, #id, onDelete: KeyAction.setNull)();
  TextColumn get debtPaymentId =>
      text().nullable().references(DebtPayments, #id, onDelete: KeyAction.setNull)();
  TextColumn get recurringExpenseId =>
      text().nullable().references(RecurringExpenses, #id, onDelete: KeyAction.setNull)();
  BoolColumn get hasReceipt => boolean().withDefault(const Constant(false))();

  /// The credit card charged (v11, §5.22I).
  TextColumn get cardDebtId =>
      text().nullable().references(Debts, #id, onDelete: KeyAction.setNull)();
}

/// Effective-dated, like goals: the row in force for a month is the latest
/// whose `effectiveFrom` is on or before its first day.
@DataClassName('BudgetRow')
class Budgets extends Table with SyncedColumns {
  TextColumn get effectiveFrom => text().map(const LocalDateConverter())();

  /// Null: the overall monthly budget.
  TextColumn get categoryId => text().nullable().references(FinanceCategories, #id)();

  /// 0 means "no budget from this month" (removing never changes past months).
  IntColumn get amountPaise => integer().check(amountPaise.isBiggerOrEqualValue(0))();
}

/// Index of encrypted receipt photos (local only, like meal photos, C2).
@DataClassName('ExpenseReceiptRow')
class LocalExpenseReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get expenseId => text()();
  TextColumn get fileName => text()();
  DateTimeColumn get takenAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ---- v11: money additions (PRD §5.22, 03 §2.9) ----

const loanChangeKinds = ['prepayment', 'rate_change', 'balance_correction'];

@DataClassName('LoanChangeRow')
@TableIndex(name: 'loan_changes_debt', columns: {#debtId, #effectiveDate})
class LoanChanges extends Table with SyncedColumns {
  TextColumn get debtId => text().references(Debts, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text().check(kind.isIn(loanChangeKinds))();
  TextColumn get effectiveDate => text().map(const LocalDateConverter())();
  IntColumn get fromInstalment =>
      integer().nullable().check(fromInstalment.isNull() | fromInstalment.isBiggerThanValue(0))();
  IntColumn get amountPaise =>
      integer().nullable().check(amountPaise.isNull() | amountPaise.isBiggerOrEqualValue(0))();
  IntColumn get rateBp =>
      integer().nullable().check(rateBp.isNull() | rateBp.isBetweenValues(0, 10000))();
  IntColumn get emiPaise =>
      integer().nullable().check(emiPaise.isNull() | emiPaise.isBiggerThanValue(0))();
  IntColumn get instalmentsLeft => integer().nullable().check(
    instalmentsLeft.isNull() | instalmentsLeft.isBetweenValues(1, 600),
  )();
  TextColumn get mode =>
      text().nullable().check(mode.isNull() | mode.isIn(const ['reduce_tenure', 'reduce_emi']))();
  TextColumn get paymentId =>
      text().nullable().references(DebtPayments, #id, onDelete: KeyAction.setNull)();
  TextColumn get note => text().nullable()();
}

@DataClassName('InstalmentSkipRow')
@TableIndex(name: 'instalment_skips_debt', columns: {#debtId, #instalmentNo})
class InstalmentSkips extends Table with SyncedColumns {
  TextColumn get debtId => text().references(Debts, #id, onDelete: KeyAction.cascade)();
  IntColumn get instalmentNo => integer().check(instalmentNo.isBiggerThanValue(0))();
  TextColumn get skippedOn => text().map(const LocalDateConverter())();
}

@DataClassName('CardStatementRow')
@TableIndex(name: 'card_statements_debt', columns: {#debtId, #statementDate})
class CardStatements extends Table with SyncedColumns {
  TextColumn get debtId => text().references(Debts, #id, onDelete: KeyAction.cascade)();
  TextColumn get statementDate => text().map(const LocalDateConverter())();
  TextColumn get dueDate => text().map(const LocalDateConverter())();
  IntColumn get totalDuePaise => integer().check(totalDuePaise.isBiggerOrEqualValue(0))();
  IntColumn get minDuePaise => integer().check(minDuePaise.isBiggerOrEqualValue(0))();
  BoolColumn get remind => boolean().withDefault(const Constant(true))();
}

@DataClassName('IncomeRow')
@TableIndex(name: 'incomes_local_date', columns: {#localDate})
class Incomes extends Table with SyncedColumns {
  IntColumn get amountPaise => integer().check(amountPaise.isBiggerThanValue(0))();
  TextColumn get categoryId => text().references(FinanceCategories, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  TextColumn get note => text().nullable()();
  TextColumn get recurringId =>
      text().nullable().references(RecurringExpenses, #id, onDelete: KeyAction.setNull)();
}

@DataClassName('ExpenseSplitRow')
@TableIndex(name: 'expense_splits_expense', columns: {#expenseId})
class ExpenseSplits extends Table with SyncedColumns {
  TextColumn get expenseId => text().references(Expenses, #id, onDelete: KeyAction.cascade)();
  TextColumn get person => text()();
  IntColumn get sharePaise => integer().check(sharePaise.isBiggerThanValue(0))();
  TextColumn get debtId => text().nullable().references(Debts, #id, onDelete: KeyAction.setNull)();
}

/// Budget alerts already shown, so each threshold alerts once a month (local).
@DataClassName('BudgetAlertRow')
class LocalBudgetAlerts extends Table {
  TextColumn get month => text()();

  /// Category id, or empty for the overall budget.
  TextColumn get categoryKey => text()();
  IntColumn get threshold => integer()();
  DateTimeColumn get shownAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {month, categoryKey, threshold};
}
