import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/data/drift_money_repository.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftMoneyRepository money;
  final food = DriftMoneyRepository.categoryId('food');
  final emiCat = DriftMoneyRepository.categoryId('emi');

  setUp(() async {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 20, 13, 10));
    money = DriftMoneyRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
    await money.seedCategories({'food': 'Food', 'emi': 'EMI and loan repayments'});
  });
  tearDown(() => db.close());

  ExpenseDraft draft(int paise, {DateTime? at, String? meal}) => (
    amountPaise: paise,
    categoryId: food,
    method: PaymentMethod.upi,
    at: at ?? time.now,
    note: null,
    mealLogId: meal,
  );

  Debt homeLoan({bool record = true}) => Debt(
    id: '',
    direction: DebtDirection.iOwe,
    name: 'Home loan',
    counterparty: 'SBI',
    kind: DebtKind.bankLoan,
    principalPaise: 150000000,
    startDate: LocalDate(2023, 9, 5),
    emi: EmiPlan(emiPaise: 1250000, day: 5, count: 240, first: LocalDate(2023, 10, 5)),
    recordAsExpense: record,
  );

  test('categories are seeded once, in order, with the same ids on every phone', () async {
    await money.seedCategories({'food': 'Renamed'});
    final cats = await money.watchCategories().first;
    expect(cats, hasLength(defaultCategoryKeys.length));
    expect(cats.first.name, 'Food');
    expect(cats.first.id, food);
    expect(cats.last.systemKey, 'other');
    expect(DriftMoneyRepository.categoryId('food'), food);
  });

  test('custom categories are added and archived; EMI and Other cannot be archived', () async {
    final pet = ((await money.addCategory('Pet care')) as Ok<FinanceCategory>).value;
    await money.archiveCategory(pet.id, archived: true);
    expect(
      (await money.watchCategories().first).firstWhere((c) => c.id == pet.id).archived,
      isTrue,
    );
    expect(
      (await money.archiveCategory(emiCat, archived: true)).failureOrNull?.code,
      'not_archivable',
    );
    expect((await money.addCategory('  ')).failureOrNull?.code, 'name_required');
  });

  test('an expense is stored in paise and queued for sync in the same write', () async {
    final before = (await outboxEntries(db)).length;
    final r = await money.addExpense(draft(24000));
    final e = (r as Ok<Expense>).value;
    expect(e.localDate, LocalDate(2026, 11, 20));
    expect((await outboxEntries(db)).skip(before), [(table: 'expenses', id: e.id)]);
    final listed = await money
        .watchExpenses(from: LocalDate(2026, 11, 1), to: LocalDate(2026, 11, 30))
        .first;
    expect(listed.single.amountPaise, 24000);
  });

  test('zero, negative and absurd amounts are rejected and nothing is written', () async {
    for (final bad in [0, -100, 100000000001]) {
      expect((await money.addExpense(draft(bad))).failureOrNull?.code, 'amount_invalid');
    }
    expect(await db.select(db.expenses).get(), isEmpty);
  });

  test('editing and deleting an expense; deleted ones disappear from lists', () async {
    final e = ((await money.addExpense(draft(24000))) as Ok<Expense>).value;
    await money.updateExpense(e.id, draft(26000));
    final range = (from: LocalDate(2026, 11, 1), to: LocalDate(2026, 11, 30));
    expect(
      (await money.watchExpenses(from: range.from, to: range.to).first).single.amountPaise,
      26000,
    );
    await money.deleteExpense(e.id);
    expect(await money.watchExpenses(from: range.from, to: range.to).first, isEmpty);
  });

  test('a meal can find its linked expense', () async {
    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            id: 'meal-1',
            createdAt: time.now.toUtc(),
            updatedAt: time.now.toUtc(),
            mealCategory: 'lunch',
            occurredAt: time.now.toUtc(),
            localDate: LocalDate(2026, 11, 20),
            tz: 'Asia/Kolkata',
          ),
        );
    await money.addExpense(draft(24000, meal: 'meal-1'));
    expect((await money.expenseForMeal('meal-1'))?.amountPaise, 24000);
    expect(await money.expenseForMeal('meal-2'), isNull);
  });

  test('budgets are effective-dated; removing one leaves earlier months alone', () async {
    await money.setBudget(categoryId: null, amountPaise: 2500000, from: LocalDate(2026, 10, 1));
    await money.setBudget(categoryId: null, amountPaise: 3000000, from: LocalDate(2026, 11, 1));
    await money.setBudget(categoryId: null, amountPaise: 3200000, from: LocalDate(2026, 11, 1));
    await money.setBudget(categoryId: food, amountPaise: 500000, from: LocalDate(2026, 10, 1));
    await money.removeBudget(categoryId: food, from: LocalDate(2026, 11, 1));
    final all = await money.watchBudgets().first;
    expect(
      all,
      hasLength(4),
      reason: 'same month and category updates in place; removal is a zero row',
    );
    expect(budgetFor(LocalDate(2026, 10, 1), null, all)?.amountPaise, 2500000);
    expect(budgetFor(LocalDate(2026, 11, 1), null, all)?.amountPaise, 3200000);
    expect(budgetFor(LocalDate(2026, 10, 1), food, all)?.amountPaise, 500000);
    expect(budgetFor(LocalDate(2026, 11, 1), food, all), isNull);
  });

  test('a loan added late can mark past instalments paid without inventing expenses', () async {
    final loan =
        ((await money.saveDebt(homeLoan(), markPastInstalmentsPaid: true)) as Ok<Debt>).value;
    final paid = await money.payments(debtId: loan.id);
    expect(paid, hasLength(38));
    expect(paid.last.localDate, LocalDate(2023, 10, 5));
    expect(await db.select(db.expenses).get(), isEmpty);
    final status = DebtStatus(loan, paid);
    expect(status.nextInstalment, 39);
    expect(status.nextDue, LocalDate(2026, 12, 5));
    // Saving again (an edit) adds nothing twice.
    await money.saveDebt(loan, markPastInstalmentsPaid: true);
    expect(await money.payments(debtId: loan.id), hasLength(38));
  });

  test('paying an EMI records the instalment and an expense in EMI and loan repayments', () async {
    final loan =
        ((await money.saveDebt(homeLoan(), markPastInstalmentsPaid: true)) as Ok<Debt>).value;
    final p =
        ((await money.addPayment(loan.id, amountPaise: 1250000, at: time.now, instalmentNo: 39))
                    as Ok)
                .value
            as DebtPayment;
    final expenses = await db.select(db.expenses).get();
    expect(expenses.single.categoryId, emiCat);
    expect(expenses.single.debtPaymentId, p.id);
    expect(expenses.single.note, 'Home loan');
    // The same instalment cannot be paid twice.
    final again = await money.addPayment(
      loan.id,
      amountPaise: 1250000,
      at: time.now,
      instalmentNo: 39,
    );
    expect(again.failureOrNull?.code, 'instalment_paid');
    // Deleting the payment removes the expense recorded from it.
    await money.deletePayment(p.id);
    expect(
      await money.watchExpenses(from: LocalDate(2026, 11, 1), to: LocalDate(2026, 11, 30)).first,
      isEmpty,
    );
    expect(DebtStatus(loan, await money.payments(debtId: loan.id)).nextInstalment, 39);
  });

  test('no expense when the loan is set not to record one, or the money is owed to me', () async {
    final loan = ((await money.saveDebt(homeLoan(record: false))) as Ok<Debt>).value;
    await money.addPayment(loan.id, amountPaise: 1250000, at: time.now, instalmentNo: 1);
    final lent =
        ((await money.saveDebt(
                  Debt(
                    id: '',
                    direction: DebtDirection.owedToMe,
                    name: 'Priya',
                    counterparty: 'Priya',
                    kind: DebtKind.personal,
                    principalPaise: 850000,
                    startDate: LocalDate(2026, 11, 1),
                  ),
                ))
                as Ok<Debt>)
            .value;
    await money.addPayment(lent.id, amountPaise: 100000, at: time.now);
    expect(await db.select(db.expenses).get(), isEmpty);
  });

  test('an invalid debt is rejected: first reminder under 7 days', () async {
    final bad = Debt(
      id: '',
      direction: DebtDirection.iOwe,
      name: 'x',
      counterparty: 'y',
      kind: DebtKind.other,
      principalPaise: 100,
      startDate: LocalDate(2026, 11, 1),
      remindDaysBefore: 3,
    );
    expect((await money.saveDebt(bad)).failureOrNull?.code, 'remind_days');
    expect(await money.debts(), isEmpty);
  });

  test('settling and deleting a debt; deletion keeps the money already spent', () async {
    final loan = ((await money.saveDebt(homeLoan())) as Ok<Debt>).value;
    await money.addPayment(loan.id, amountPaise: 1250000, at: time.now, instalmentNo: 1);
    await money.setSettled(loan.id, settled: true);
    expect((await money.debts()).single.settled, isTrue);
    await money.deleteDebt(loan.id);
    expect(await money.debts(), isEmpty);
    expect(await money.payments(), isEmpty);
    expect((await db.select(db.expenses).get()).where((e) => e.deletedAt == null), hasLength(1));
  });

  test('recurring expenses keep their schedule', () async {
    final rent =
        ((await money.saveRecurring(
                  RecurringExpense(
                    id: '',
                    name: 'Rent',
                    amountPaise: 1800000,
                    categoryId: DriftMoneyRepository.categoryId('rent'),
                    method: PaymentMethod.netBanking,
                    rule: Monthly.dayOfMonth(1, times: const [540]),
                  ),
                ))
                as Ok<RecurringExpense>)
            .value;
    final back = (await money.recurring()).single;
    expect(back.id, rent.id);
    expect(back.rule.toJson(), rent.rule.toJson());
    await money.deleteRecurring(rent.id);
    expect(await money.recurring(), isEmpty);
  });
}
