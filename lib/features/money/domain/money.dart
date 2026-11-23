import 'dart:math' as math;

import '../../../core/errors/result.dart';
import '../../../core/scheduling/schedule_rule.dart';
import '../../../core/utils/local_date.dart';
import 'loans.dart';

/// Money module (PRD §5.21). Amounts are integer paise.

enum PaymentMethod {
  cash('cash'),
  upi('upi'),
  debitCard('debit_card'),
  creditCard('credit_card'),
  netBanking('net_banking'),
  other('other');

  const PaymentMethod(this.code);
  final String code;
  static PaymentMethod fromCode(String c) =>
      values.firstWhere((m) => m.code == c, orElse: () => other);
}

final class FinanceCategory {
  const FinanceCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    this.systemKey,
    this.archived = false,
    this.sortOrder = 0,
  });
  final String id;
  final String name;
  final String? systemKey;
  final String iconKey;
  final bool archived;
  final int sortOrder;
}

/// Seeded categories, in order (§5.21A). Names come from l10n by key.
/// Categories that every expense can fall back on; never archived.
const unarchivableCategoryKeys = {'emi', 'other'};

const defaultCategoryKeys = [
  ('food', 'food'),
  ('groceries', 'basket'),
  ('transport', 'transport'),
  ('fuel', 'fuel'),
  ('bills', 'bill'),
  ('rent', 'home'),
  ('shopping', 'bag'),
  ('health', 'health'),
  ('entertainment', 'film'),
  ('education', 'book'),
  ('travel', 'travel'),
  ('gifts', 'gift'),
  ('emi', 'bank'),
  ('other', 'other'),
];

final class Expense {
  const Expense({
    required this.id,
    required this.amountPaise,
    required this.categoryId,
    required this.method,
    required this.occurredAt,
    required this.localDate,
    this.note,
    this.mealLogId,
    this.debtPaymentId,
    this.recurringExpenseId,
    this.hasReceipt = false,
  });
  final String id;
  final int amountPaise;
  final String categoryId;
  final PaymentMethod method;
  final DateTime occurredAt;
  final LocalDate localDate;
  final String? note;
  final String? mealLogId;
  final String? debtPaymentId;
  final String? recurringExpenseId;
  final bool hasReceipt;
}

typedef ExpenseDraft = ({
  int amountPaise,
  String categoryId,
  PaymentMethod method,
  DateTime at,
  String? note,
  String? mealLogId,
});

final class Budget {
  const Budget({
    required this.id,
    required this.effectiveFrom,
    required this.amountPaise,
    this.categoryId,
  });
  final String id;
  final LocalDate effectiveFrom;

  /// Null: the overall monthly budget.
  final String? categoryId;
  final int amountPaise;
}

/// The budget in force for the month starting [monthStart]: the latest row
/// for that category whose `effectiveFrom` is on or before it. A zero row
/// ends a budget without touching earlier months.
Budget? budgetFor(LocalDate monthStart, String? categoryId, List<Budget> all) {
  Budget? best;
  for (final b in all) {
    if (b.categoryId != categoryId || b.effectiveFrom.isAfter(monthStart)) continue;
    if (best == null || b.effectiveFrom.isAfter(best.effectiveFrom)) best = b;
  }
  return best == null || best.amountPaise == 0 ? null : best;
}

enum DebtDirection {
  iOwe('i_owe'),
  owedToMe('owed_to_me');

  const DebtDirection(this.code);
  final String code;
  static DebtDirection fromCode(String c) => values.firstWhere((d) => d.code == c);
}

enum DebtKind {
  personal('personal'),
  bankLoan('bank_loan'),
  creditCard('credit_card'),
  other('other');

  const DebtKind(this.code);
  final String code;
  static DebtKind fromCode(String c) => values.firstWhere((k) => k.code == c, orElse: () => other);
}

/// An EMI schedule: [count] instalments of [emiPaise] on day [day], the
/// first on [first].
final class EmiPlan {
  const EmiPlan({
    required this.emiPaise,
    required this.day,
    required this.count,
    required this.first,
  });
  final int emiPaise;
  final int day;
  final int count;
  final LocalDate first;

  /// Due date of instalment [n] (1-based).
  LocalDate dueDate(int n) {
    final d = DateTime.utc(first.year, first.month + n - 1, day);
    return LocalDate(d.year, d.month, d.day);
  }

  /// Instalments whose due date is on or before [day].
  int dueBy(LocalDate on) {
    var n = 0;
    while (n < count && !dueDate(n + 1).isAfter(on)) {
      n++;
    }
    return n;
  }
}

final class Debt {
  const Debt({
    required this.id,
    required this.direction,
    required this.name,
    required this.counterparty,
    required this.kind,
    required this.principalPaise,
    required this.startDate,
    this.interestRateBp,
    this.dueDate,
    this.emi,
    this.remind = true,
    this.remindDaysBefore = 7,
    this.recordAsExpense = true,
    this.settled = false,
    this.notes,
  });
  final String id;
  final DebtDirection direction;
  final String name;
  final String counterparty;
  final DebtKind kind;
  final int principalPaise;
  final LocalDate startDate;
  final int? interestRateBp;
  final LocalDate? dueDate;
  final EmiPlan? emi;
  final bool remind;

  /// At least 7 (owner, 20 Nov 2026), at most 30.
  final int remindDaysBefore;
  final bool recordAsExpense;
  final bool settled;
  final String? notes;

  List<String> get problems => [
    if (name.trim().isEmpty) 'name_required',
    if (counterparty.trim().isEmpty) 'counterparty_required',
    if (principalPaise <= 0) 'amount_required',
    if (remindDaysBefore < 7 || remindDaysBefore > 30) 'remind_days',
    if (emi != null && (emi!.emiPaise <= 0 || emi!.count < 1 || emi!.day < 1 || emi!.day > 28))
      'emi_invalid',
  ];
}

final class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.debtId,
    required this.amountPaise,
    required this.paidAt,
    required this.localDate,
    this.instalmentNo,
    this.note,
  });
  final String id;
  final String debtId;
  final int amountPaise;
  final DateTime paidAt;
  final LocalDate localDate;
  final int? instalmentNo;
  final String? note;
}

/// What a debt stands at, from its payments, loan changes and skipped
/// instalments (§5.21C, §5.22F–H).
final class DebtStatus {
  DebtStatus(
    this.debt,
    List<DebtPayment> payments, {
    List<LoanChange> changes = const [],
    List<InstalmentSkip> skips = const [],
  }) : paidPaise = payments.fold(0, (n, p) => n + p.amountPaise),
       paidInstalments = {for (final p in payments) ?p.instalmentNo},
       skippedInstalments = {for (final s in skips) s.instalmentNo},
       changes = [
         for (final c in changes)
           if (c.debtId == debt.id) c,
       ],
       _payments = payments;
  final Debt debt;
  final int paidPaise;
  final Set<int> paidInstalments;
  final Set<int> skippedInstalments;
  final List<LoanChange> changes;
  final List<DebtPayment> _payments;

  late final List<ScheduleRow> schedule = loanSchedule(debt, changes);

  LoanChange? get _lastCorrection {
    LoanChange? last;
    for (final c in changes) {
      if (c.kind != LoanChangeKind.balanceCorrection) continue;
      if (last == null || c.effectiveDate.isAfter(last.effectiveDate)) last = c;
    }
    return last;
  }

  /// Original amount (or the latest corrected balance) minus payments made
  /// since, never below zero.
  int get outstandingPaise {
    final fix = _lastCorrection;
    if (fix == null) return (debt.principalPaise - paidPaise).clamp(0, debt.principalPaise);
    final after = _payments
        .where((p) => p.localDate.isAfter(fix.effectiveDate))
        .fold(0, (n, p) => n + p.amountPaise);
    return math.max(0, (fix.amountPaise ?? 0) - after);
  }

  int get instalmentCount => schedule.length;

  int get instalmentsLeft =>
      debt.emi == null ? 0 : schedule.where((r) => !paidInstalments.contains(r.n)).length;

  /// The EMIs still to pay (the bank's own figure may differ).
  int get remainingByEmiPaise => debt.emi == null
      ? 0
      : schedule.where((r) => !paidInstalments.contains(r.n)).fold(0, (s, r) => s + r.emiPaise);

  /// What the lists show: EMI loans by instalments, others by payments.
  int get remainingPaise => debt.emi == null ? outstandingPaise : remainingByEmiPaise;

  /// The lowest instalment neither paid nor skipped, or null when none is.
  int? get nextInstalment {
    for (final r in schedule) {
      if (!paidInstalments.contains(r.n) && !skippedInstalments.contains(r.n)) return r.n;
    }
    return null;
  }

  ScheduleRow? rowFor(int n) => schedule.where((r) => r.n == n).firstOrNull;

  LocalDate? get nextDue {
    final n = nextInstalment;
    return n == null ? null : rowFor(n)?.due;
  }

  int? get nextEmiPaise {
    final n = nextInstalment;
    return n == null ? null : rowFor(n)?.emiPaise;
  }

  /// The next instalment is past its due date without a payment.
  bool overdueOn(LocalDate today) {
    final due = nextDue;
    return !debt.settled && due != null && due.isBefore(today);
  }

  /// Instalments past due and neither paid nor skipped.
  int overdueCount(LocalDate today) => schedule
      .where(
        (r) =>
            r.due.isBefore(today) &&
            !paidInstalments.contains(r.n) &&
            !skippedInstalments.contains(r.n),
      )
      .length;

  LocalDate? get endsOn => schedule.isEmpty ? null : schedule.last.due;
}

/// Days on which an EMI reminder fires for an instalment due on [due]:
/// [leadDays] before (at least 7), the day before, and the due day.
List<({LocalDate day, int daysBefore})> emiReminderDays(LocalDate due, int leadDays) => [
  (day: due.addDays(-leadDays), daysBefore: leadDays),
  (day: due.addDays(-1), daysBefore: 1),
  (day: due, daysBefore: 0),
];

final class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.name,
    required this.amountPaise,
    required this.categoryId,
    required this.method,
    required this.rule,
    this.remind = true,
    this.active = true,
  });
  final String id;
  final String name;
  final int amountPaise;
  final String categoryId;
  final PaymentMethod method;
  final ScheduleRule rule;
  final bool remind;
  final bool active;
}

abstract interface class MoneyRepository {
  Future<void> seedCategories(Map<String, String> namesByKey);
  Stream<List<FinanceCategory>> watchCategories();
  Future<Result<FinanceCategory>> addCategory(String name, {String iconKey = 'other'});
  Future<Result<void>> archiveCategory(String id, {required bool archived});

  Future<Result<Expense>> addExpense(
    ExpenseDraft draft, {
    String? debtPaymentId,
    String? recurringExpenseId,
  });
  Future<Result<void>> updateExpense(String id, ExpenseDraft draft);
  Future<Result<void>> deleteExpense(String id);
  Stream<List<Expense>> watchExpenses({required LocalDate from, required LocalDate to});
  Future<Expense?> expenseForMeal(String mealLogId);
  Future<Result<void>> setHasReceipt(String expenseId, bool value);

  /// Meals in the range with at least one junk-food item (§5.21D).
  Stream<Set<String>> watchJunkMealIds({required LocalDate from, required LocalDate to});

  Future<Result<void>> setBudget({
    required String? categoryId,
    required int amountPaise,
    required LocalDate from,
  });
  Future<Result<void>> removeBudget({required String? categoryId, required LocalDate from});
  Stream<List<Budget>> watchBudgets();

  Future<Result<Debt>> saveDebt(Debt debt, {bool markPastInstalmentsPaid = false});
  Future<Result<void>> deleteDebt(String id);
  Future<Result<void>> setSettled(String id, {required bool settled});
  Stream<List<Debt>> watchDebts();
  Future<List<Debt>> debts();

  /// Records a payment; for an I-owe debt with `recordAsExpense`, also an
  /// expense in "EMI and loan repayments" linked to it.
  Future<Result<DebtPayment>> addPayment(
    String debtId, {
    required int amountPaise,
    required DateTime at,
    int? instalmentNo,
    String? note,
  });
  Future<Result<void>> deletePayment(String id);
  Stream<List<DebtPayment>> watchPayments({String? debtId});
  Future<List<DebtPayment>> payments({String? debtId});

  /// A part-payment also records a payment (and its expense, per the loan).
  Future<Result<LoanChange>> addLoanChange(LoanChange change, {DateTime? at});
  Future<Result<void>> deleteLoanChange(String id);
  Stream<List<LoanChange>> watchLoanChanges();
  Future<List<LoanChange>> loanChanges();
  Future<Result<void>> skipInstalment(String debtId, int instalmentNo, {required LocalDate on});
  Future<Result<void>> unskipInstalment(String id);
  Stream<List<InstalmentSkip>> watchSkips();
  Future<List<InstalmentSkip>> skips();

  Future<Result<RecurringExpense>> saveRecurring(RecurringExpense r);
  Future<Result<void>> deleteRecurring(String id);
  Stream<List<RecurringExpense>> watchRecurring();
  Future<List<RecurringExpense>> recurring();
}
