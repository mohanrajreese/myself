import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:fitbuddy/features/money/domain/money_report.dart';
import 'package:flutter_test/flutter_test.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

var _n = 0;
Expense e(
  int rupees,
  String cat,
  LocalDate day, {
  PaymentMethod m = PaymentMethod.upi,
  String? meal,
}) => Expense(
  id: 'e${_n++}',
  amountPaise: rupees * 100,
  categoryId: cat,
  method: m,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 8),
  localDate: day,
  mealLogId: meal,
);

void main() {
  final loan = Debt(
    id: 'l',
    direction: DebtDirection.iOwe,
    name: 'Home loan',
    counterparty: 'SBI',
    kind: DebtKind.bankLoan,
    principalPaise: 150000000,
    startDate: d(2023, 9, 5),
    emi: EmiPlan(emiPaise: 1250000, day: 5, count: 240, first: d(2023, 10, 5)),
  );
  final phone = Debt(
    id: 'p',
    direction: DebtDirection.iOwe,
    name: 'Phone',
    counterparty: 'Bajaj',
    kind: DebtKind.other,
    principalPaise: 1290000,
    startDate: d(2026, 8, 10),
    emi: EmiPlan(emiPaise: 215000, day: 10, count: 6, first: d(2026, 9, 10)),
  );
  final lent = Debt(
    id: 'r',
    direction: DebtDirection.owedToMe,
    name: 'Priya',
    counterparty: 'Priya',
    kind: DebtKind.personal,
    principalPaise: 850000,
    startDate: d(2026, 11, 1),
  );
  final payments = [
    for (var n = 1; n <= 38; n++)
      DebtPayment(
        id: 'h$n',
        debtId: 'l',
        amountPaise: 1250000,
        paidAt: DateTime.utc(2026),
        localDate: d(2026, 1, 1),
        instalmentNo: n,
      ),
    for (var n = 1; n <= 3; n++)
      DebtPayment(
        id: 'q$n',
        debtId: 'p',
        amountPaise: 215000,
        paidAt: DateTime.utc(2026),
        localDate: d(2026, 1, 1),
        instalmentNo: n,
      ),
  ];

  MoneyReport report({List<Budget> budgets = const []}) => MoneyReport.build(
    from: d(2026, 11, 1),
    to: d(2026, 11, 20),
    today: d(2026, 11, 20),
    expenses: [
      e(12500, 'emi', d(2026, 11, 5), m: PaymentMethod.netBanking),
      e(2150, 'emi', d(2026, 11, 10), m: PaymentMethod.netBanking),
      e(240, 'food', d(2026, 11, 20), meal: 'm1'),
      e(160, 'food', d(2026, 11, 19), meal: 'm2'),
      e(3400, 'shopping', d(2026, 11, 12), m: PaymentMethod.cash),
      e(999, 'food', d(2026, 10, 31)), // outside the range
    ],
    previous: [e(15000, 'emi', d(2026, 10, 5))],
    budgets: budgets,
    debts: [loan, phone, lent],
    payments: payments,
    emiCategoryId: 'emi',
    foodCategoryIds: const {'food', 'groceries'},
    junkMealIds: const {'m2'},
  );

  test('the previous period of a month-to-date range is the same days of the month before', () {
    expect(MoneyReport.previousRange(d(2026, 11, 1), d(2026, 11, 20)), (
      from: d(2026, 10, 1),
      to: d(2026, 10, 20),
    ));
    expect(MoneyReport.previousRange(d(2026, 3, 1), d(2026, 3, 31)), (
      from: d(2026, 2, 1),
      to: d(2026, 2, 28),
    ));
    expect(MoneyReport.previousRange(d(2026, 1, 1), d(2026, 1, 31)).from, d(2025, 12, 1));
    expect(MoneyReport.previousRange(d(2026, 11, 10), d(2026, 11, 16)), (
      from: d(2026, 11, 3),
      to: d(2026, 11, 9),
    ));
  });

  test('totals by category, by method and per day', () {
    final r = report();
    expect(r.totalPaise, 1845000);
    expect(r.byCategory.keys.first, 'emi');
    expect(r.byCategory['emi'], 1465000);
    expect(r.byMethod.keys.first, PaymentMethod.netBanking);
    expect(r.daily, hasLength(20));
    expect(r.daily[d(2026, 11, 5)], 1250000);
    expect(r.daily[d(2026, 11, 2)], 0);
    expect(r.sharePercent(r.emiPaise), 79);
  });

  test('food: linked meals, cost per meal, junk-food meals', () {
    final r = report();
    expect(r.foodPaise, 40000);
    expect(r.linkedMeals, 2);
    expect(r.junkMeals, 1);
    expect(r.junkMealPaise, 16000);
  });

  test('debts: what I owe, what I am owed, EMIs due in the next 30 days', () {
    final r = report();
    expect(r.iOwePaise, 202 * 1250000 + 3 * 215000);
    expect(r.owedToMePaise, 850000);
    expect(r.upcomingEmis, 2); // 5 Dec and 10 Dec
    expect(r.upcomingEmiPaise, 1465000);
  });

  test('facts are descriptive and include budgets only for a month', () {
    final r = report(
      budgets: [
        Budget(id: 'b', effectiveFrom: d(2026, 11, 1), amountPaise: 3000000),
        Budget(id: 'c', effectiveFrom: d(2026, 11, 1), categoryId: 'shopping', amountPaise: 300000),
      ],
    );
    final facts = r.facts;
    expect((facts[0] as SpendVsPrevious).differencePaise, 1845000 - 1500000);
    expect((facts[1] as EmiShare).percent, 79);
    expect((facts[2] as FoodPerMeal).averagePaise, 20000);
    expect((facts[3] as CategoryOverBudget).overPaise, 40000);
    expect((facts[4] as BudgetUsed).percent, 62);
  });

  test('an empty period gives no facts', () {
    final r = MoneyReport.build(
      from: d(2026, 11, 3),
      to: d(2026, 11, 9),
      today: d(2026, 11, 20),
      expenses: const [],
      previous: const [],
      budgets: const [],
      debts: const [],
      payments: const [],
      emiCategoryId: 'emi',
      foodCategoryIds: const {'food'},
    );
    expect(r.facts, isEmpty);
    expect(r.sharePercent(0), 0);
  });
}
