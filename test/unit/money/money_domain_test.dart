import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  final plan = EmiPlan(emiPaise: 1250000, day: 5, count: 240, first: d(2023, 10, 5));
  Debt loan({EmiPlan? emi, int principal = 150000000}) => Debt(
    id: 'l1',
    direction: DebtDirection.iOwe,
    name: 'Home loan',
    counterparty: 'SBI',
    kind: DebtKind.bankLoan,
    principalPaise: principal,
    startDate: d(2023, 9, 5),
    emi: emi ?? plan,
  );
  DebtPayment pay(int n, {int amount = 1250000}) => DebtPayment(
    id: 'p$n',
    debtId: 'l1',
    amountPaise: amount,
    paidAt: DateTime.utc(2026),
    localDate: d(2026, 1, 1),
    instalmentNo: n == 0 ? null : n,
  );

  group('EMI plan', () {
    test('due dates step by calendar month across years', () {
      expect(plan.dueDate(1), d(2023, 10, 5));
      expect(plan.dueDate(3), d(2023, 12, 5));
      expect(plan.dueDate(4), d(2024, 1, 5));
      expect(plan.dueDate(240), d(2043, 9, 5));
    });

    test('counts instalments due by a date', () {
      expect(plan.dueBy(d(2023, 10, 4)), 0);
      expect(plan.dueBy(d(2023, 10, 5)), 1);
      expect(plan.dueBy(d(2026, 11, 20)), 38);
    });
  });

  group('debt status', () {
    test('next instalment, remaining by EMI, and outstanding by payments', () {
      final s = DebtStatus(loan(), [for (var n = 1; n <= 38; n++) pay(n), pay(0, amount: 5000000)]);
      expect(s.nextInstalment, 39);
      expect(s.nextDue, d(2026, 12, 5));
      expect(s.instalmentsLeft, 202);
      expect(s.remainingPaise, 252500000); // ₹25,25,000
      expect(s.paidPaise, 52500000); // 38 EMIs + ₹50,000 part-payment
      expect(s.outstandingPaise, 97500000);
    });

    test('an instalment paid out of order leaves the earlier one next', () {
      final s = DebtStatus(loan(), [pay(1), pay(3)]);
      expect(s.nextInstalment, 2);
    });

    test('all instalments paid: no next due date', () {
      final small = EmiPlan(emiPaise: 215000, day: 10, count: 2, first: d(2026, 9, 10));
      final s = DebtStatus(loan(emi: small, principal: 430000), [
        pay(1, amount: 215000),
        pay(2, amount: 215000),
      ]);
      expect(s.nextInstalment, isNull);
      expect(s.nextDue, isNull);
      expect(s.remainingPaise, 0);
    });

    test('a personal debt is outstanding minus repayments, never below zero', () {
      final ravi = Debt(
        id: 'r',
        direction: DebtDirection.iOwe,
        name: 'Ravi',
        counterparty: 'Ravi',
        kind: DebtKind.personal,
        principalPaise: 3000000,
        startDate: d(2026, 9, 1),
      );
      expect(DebtStatus(ravi, [pay(0, amount: 575000)]).remainingPaise, 2425000);
      expect(DebtStatus(ravi, [pay(0, amount: 9999999)]).outstandingPaise, 0);
    });

    test('the first reminder must be 7 to 30 days ahead', () {
      expect(
        Debt(
          id: 'x',
          direction: DebtDirection.iOwe,
          name: 'x',
          counterparty: 'y',
          kind: DebtKind.other,
          principalPaise: 1,
          startDate: d(2026, 9, 1),
          remindDaysBefore: 3,
        ).problems,
        contains('remind_days'),
      );
    });
  });

  test('EMI reminders: lead days before, the day before, and the due day', () {
    expect(emiReminderDays(d(2026, 12, 5), 7).map((r) => r.day), [
      d(2026, 11, 28),
      d(2026, 12, 4),
      d(2026, 12, 5),
    ]);
    expect(emiReminderDays(d(2026, 12, 5), 14).first.day, d(2026, 11, 21));
  });

  group('budgets', () {
    final all = [
      Budget(id: 'a', effectiveFrom: d(2026, 9, 1), amountPaise: 2500000),
      Budget(id: 'b', effectiveFrom: d(2026, 11, 1), amountPaise: 3000000),
      Budget(id: 'c', effectiveFrom: d(2026, 10, 1), categoryId: 'food', amountPaise: 500000),
    ];
    test('a later budget never changes earlier months', () {
      expect(budgetFor(d(2026, 10, 1), null, all)?.amountPaise, 2500000);
      expect(budgetFor(d(2026, 11, 1), null, all)?.amountPaise, 3000000);
      expect(budgetFor(d(2026, 8, 1), null, all), isNull);
    });
    test('category budgets are separate from the overall one', () {
      expect(budgetFor(d(2026, 11, 1), 'food', all)?.amountPaise, 500000);
      expect(budgetFor(d(2026, 11, 1), 'shopping', all), isNull);
    });
    test('a zero row removes a budget from that month on only', () {
      final withEnd = [
        ...all,
        Budget(id: 'd', effectiveFrom: d(2026, 12, 1), categoryId: 'food', amountPaise: 0),
      ];
      expect(budgetFor(d(2026, 11, 1), 'food', withEnd)?.amountPaise, 500000);
      expect(budgetFor(d(2026, 12, 1), 'food', withEnd), isNull);
    });
  });
}
