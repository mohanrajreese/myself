import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/domain/loans.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  const r = 850 / 10000 / 12;
  final emi = emiFor(150000000, r, 240); // ₹15 lakh, 8.5 %, 20 years
  Debt loan({int? rate = 850, int? emiPaise}) => Debt(
    id: 'l',
    direction: DebtDirection.iOwe,
    name: 'Home loan',
    counterparty: 'SBI',
    kind: DebtKind.bankLoan,
    principalPaise: 150000000,
    startDate: d(2023, 9, 5),
    interestRateBp: rate,
    emi: EmiPlan(emiPaise: emiPaise ?? emi, day: 5, count: 240, first: d(2023, 10, 5)),
  );
  DebtPayment paid(int n) => DebtPayment(
    id: 'p$n',
    debtId: 'l',
    amountPaise: emi,
    paidAt: DateTime.utc(2026),
    localDate: loan().emi!.dueDate(n),
    instalmentNo: n,
  );

  test('the standard EMI repays the loan in 240 instalments with interest falling', () {
    expect(emi, closeTo(1301700, 100)); // about ₹13,017
    final rows = loanSchedule(loan(), const []);
    expect(rows, hasLength(240));
    expect(rows.first.interestPaise, 1062500); // 15,00,000 × 8.5 % ÷ 12
    expect(rows.first.principalPaise, emi - 1062500);
    expect(rows.last.balancePaise, 0);
    expect(rows[100].interestPaise! < rows[99].interestPaise!, isTrue);
  });

  test('without a rate: dates and EMIs only, no split', () {
    final rows = loanSchedule(loan(rate: null, emiPaise: 1250000), const []);
    expect(rows, hasLength(240));
    expect(rows.first.interestPaise, isNull);
    expect(rows.every((r) => r.emiPaise == 1250000), isTrue);
  });

  test('a part-payment with fewer EMIs shortens the loan and leaves earlier instalments alone', () {
    final before = loanSchedule(loan(), const []);
    final c = LoanChange(
      id: 'c',
      debtId: 'l',
      kind: LoanChangeKind.prepayment,
      effectiveDate: d(2026, 8, 12),
      amountPaise: 5000000,
      mode: PrepayMode.reduceTenure,
    );
    final after = loanSchedule(loan(), [c]);
    expect(after.length, lessThan(240));
    expect(
      after.sublist(0, 35).map((r) => r.balancePaise),
      before.sublist(0, 35).map((r) => r.balancePaise),
    );
    expect(after[35].emiPaise, emi, reason: 'EMI unchanged');
    expect(after.last.balancePaise, 0);
  });

  test('a part-payment with a lower EMI keeps the end date', () {
    final c = LoanChange(
      id: 'c',
      debtId: 'l',
      kind: LoanChangeKind.prepayment,
      effectiveDate: d(2026, 8, 12),
      amountPaise: 5000000,
      mode: PrepayMode.reduceEmi,
    );
    final after = loanSchedule(loan(), [c]);
    expect(after, hasLength(240));
    expect(after[36].emiPaise, lessThan(emi));
    expect(after.last.balancePaise, 0);
  });

  test('a rate change applies from its instalment; instalments left can be given', () {
    final c = LoanChange(
      id: 'c',
      debtId: 'l',
      kind: LoanChangeKind.rateChange,
      effectiveDate: d(2026, 5, 5),
      fromInstalment: 30,
      rateBp: 900,
      emiPaise: 1350000,
      instalmentsLeft: 211,
    );
    final rows = loanSchedule(loan(), [c]);
    expect(rows[28].emiPaise, emi);
    expect(rows[29].emiPaise, 1350000);
    expect(rows.length, lessThanOrEqualTo(240));
  });

  test('a balance correction restarts the outstanding amount from the statement', () {
    final c = LoanChange(
      id: 'c',
      debtId: 'l',
      kind: LoanChangeKind.balanceCorrection,
      effectiveDate: d(2026, 11, 30),
      amountPaise: 128431000,
    );
    final rows = loanSchedule(loan(), [c]);
    final dec = rows.firstWhere((r) => r.due == d(2026, 12, 5));
    expect(dec.interestPaise, (128431000 * r).round());
    final status = DebtStatus(loan(), [paid(38)], changes: [c]);
    expect(status.outstandingPaise, 128431000);
  });

  test('skipped and overdue instalments', () {
    final s = DebtStatus(loan(), [for (var n = 1; n <= 38; n++) paid(n)], skips: const []);
    expect(s.nextInstalment, 39);
    expect(s.overdueOn(d(2026, 12, 8)), isTrue);
    expect(s.overdueOn(d(2026, 12, 5)), isFalse, reason: 'due today is not overdue');
    expect(s.overdueCount(d(2027, 1, 8)), 2);
    final skipped = DebtStatus(
      loan(),
      [for (var n = 1; n <= 38; n++) paid(n)],
      skips: [InstalmentSkip(id: 's', debtId: 'l', instalmentNo: 39, skippedOn: d(2026, 12, 8))],
    );
    expect(skipped.nextInstalment, 40);
    expect(skipped.overdueOn(d(2026, 12, 8)), isFalse);
  });

  test('tenure and EMI helpers', () {
    expect(tenureFor(100000, 0, 30000), 4);
    expect(tenureFor(100000, 0.01, 500), 600, reason: 'an EMI below the interest never repays');
    expect(emiFor(120000, 0, 12), 10000);
  });
}
