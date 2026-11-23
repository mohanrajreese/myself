import 'dart:math' as math;

import '../../../core/utils/local_date.dart';
import 'money.dart';

/// Loan changes, skipped instalments and the repayment schedule
/// (PRD §5.22F–H). Pure: no I/O.

enum LoanChangeKind {
  prepayment('prepayment'),
  rateChange('rate_change'),
  balanceCorrection('balance_correction');

  const LoanChangeKind(this.code);
  final String code;
  static LoanChangeKind fromCode(String c) => values.firstWhere((k) => k.code == c);
}

enum PrepayMode {
  reduceTenure('reduce_tenure'),
  reduceEmi('reduce_emi');

  const PrepayMode(this.code);
  final String code;
  static PrepayMode? fromCode(String? c) =>
      c == null ? null : values.firstWhere((m) => m.code == c);
}

final class LoanChange {
  const LoanChange({
    required this.id,
    required this.debtId,
    required this.kind,
    required this.effectiveDate,
    this.fromInstalment,
    this.amountPaise,
    this.rateBp,
    this.emiPaise,
    this.instalmentsLeft,
    this.mode,
    this.paymentId,
    this.note,
  });
  final String id;
  final String debtId;
  final LoanChangeKind kind;
  final LocalDate effectiveDate;

  /// Rate or EMI change: the first instalment it applies to.
  final int? fromInstalment;

  /// Prepayment amount, or the corrected outstanding balance.
  final int? amountPaise;
  final int? rateBp;
  final int? emiPaise;
  final int? instalmentsLeft;
  final PrepayMode? mode;
  final String? paymentId;
  final String? note;
}

final class InstalmentSkip {
  const InstalmentSkip({
    required this.id,
    required this.debtId,
    required this.instalmentNo,
    required this.skippedOn,
  });
  final String id;
  final String debtId;
  final int instalmentNo;
  final LocalDate skippedOn;
}

final class ScheduleRow {
  const ScheduleRow({
    required this.n,
    required this.due,
    required this.emiPaise,
    this.interestPaise,
    this.principalPaise,
    this.balancePaise,
  });
  final int n;
  final LocalDate due;
  final int emiPaise;

  /// Null without an interest rate.
  final int? interestPaise;
  final int? principalPaise;
  final int? balancePaise;
}

/// Months for [balance] to reach zero at [emi] and monthly rate [r].
int tenureFor(int balance, double r, int emi) {
  if (balance <= 0) return 0;
  if (emi <= 0) return 600;
  if (r == 0) return (balance / emi).ceil();
  final x = 1 - r * balance / emi;
  if (x <= 0) return 600; // the EMI does not cover the interest
  return (-math.log(x) / math.log(1 + r)).ceil().clamp(1, 600);
}

/// The EMI that repays [balance] in [months] at monthly rate [r].
int emiFor(int balance, double r, int months) {
  if (balance <= 0 || months <= 0) return 0;
  if (r == 0) return (balance / months).ceil();
  return (balance * r / (1 - math.pow(1 + r, -months))).round();
}

/// Builds the schedule from the plan, applying changes in date order.
/// Without a rate the loan is treated as EMI × instalments with no split.
List<ScheduleRow> loanSchedule(Debt debt, List<LoanChange> changes) {
  final plan = debt.emi;
  if (plan == null) return const [];
  var rateBp = debt.interestRateBp;
  var emi = plan.emiPaise;
  var count = plan.count;
  var balance = rateBp == null ? plan.emiPaise * plan.count : debt.principalPaise;
  final sorted = [...changes]..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
  final applied = <String>{};
  final rows = <ScheduleRow>[];
  double rate() => (rateBp ?? 0) / 10000 / 12;
  for (var n = 1; n <= count && n <= 600; n++) {
    final due = plan.dueDate(n);
    for (final c in sorted) {
      if (applied.contains(c.id)) continue;
      final byInstalment = c.kind == LoanChangeKind.rateChange && c.fromInstalment != null;
      final applies = byInstalment ? c.fromInstalment! <= n : c.effectiveDate.isBefore(due);
      if (!applies) continue;
      applied.add(c.id);
      final left = count - n + 1;
      switch (c.kind) {
        case LoanChangeKind.balanceCorrection:
          balance = c.amountPaise ?? balance;
          if (rateBp != null) count = n - 1 + tenureFor(balance, rate(), emi);
          if (rateBp == null) count = n - 1 + tenureFor(balance, 0, emi);
        case LoanChangeKind.prepayment:
          balance = math.max(0, balance - (c.amountPaise ?? 0));
          if (c.mode == PrepayMode.reduceEmi) {
            emi = emiFor(balance, rate(), left);
          } else {
            count = n - 1 + tenureFor(balance, rate(), emi);
          }
        case LoanChangeKind.rateChange:
          if (c.rateBp != null) rateBp = c.rateBp;
          if (c.emiPaise != null) emi = c.emiPaise!;
          count = c.instalmentsLeft != null
              ? n - 1 + c.instalmentsLeft!
              : n - 1 + tenureFor(balance, rate(), emi);
      }
    }
    if (balance <= 0 || n > count) break;
    final interest = (balance * rate()).round();
    var principal = emi - interest;
    if (n == count || principal >= balance) principal = balance;
    if (principal < 0) principal = 0;
    balance -= principal;
    rows.add(
      ScheduleRow(
        n: n,
        due: due,
        emiPaise: principal + interest,
        interestPaise: rateBp == null ? null : interest,
        principalPaise: rateBp == null ? null : principal,
        balancePaise: rateBp == null ? null : balance,
      ),
    );
    if (balance <= 0) break;
  }
  return rows;
}
