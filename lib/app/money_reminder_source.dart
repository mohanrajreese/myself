import 'package:intl/intl.dart';

import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../core/scheduling/reminder_planner.dart';
import '../core/scheduling/schedule_rule.dart';
import '../core/utils/clock.dart';
import '../core/utils/local_date.dart';
import '../features/money/domain/money.dart';
import '../l10n/generated/app_localizations.dart';
import 'reminder_service.dart';

/// Notification text for money reminders, from l10n. Amounts are never in
/// the text: the lock screen may show it (§5.21C).
final class MoneyReminderText {
  const MoneyReminderText({
    required this.emiInDays,
    required this.emiTomorrow,
    required this.emiToday,
    required this.emiBody,
    required this.recurringDue,
    required this.emiOverdue,
    required this.emiOverdueBody,
  });
  final String Function(String name, int days) emiInDays;
  final String Function(String name) emiTomorrow;
  final String Function(String name) emiToday;
  final String Function(String lender, int instalment, int count) emiBody;
  final String Function(String name) recurringDue;
  final String Function(String name) emiOverdue;
  final String Function(String lender, int instalment, LocalDate due) emiOverdueBody;
}

MoneyReminderText moneyReminderText(AppLocalizations l10n) => MoneyReminderText(
  emiInDays: (name, days) => l10n.moneyEmiInDays(days, name),
  emiTomorrow: l10n.moneyEmiTomorrow,
  emiToday: l10n.moneyEmiToday,
  emiBody: l10n.moneyEmiBody,
  recurringDue: l10n.moneyRecurringDue,
  emiOverdue: l10n.moneyEmiOverdue,
  emiOverdueBody: (lender, n, due) => l10n.moneyEmiOverdueBody(
    lender,
    n,
    DateFormat('d MMM').format(DateTime(due.year, due.month, due.day)),
  ),
);

/// EMI reminders (lead days, 1 day and the due day, at 09:00, for the next
/// unpaid instalment) and recurring-expense reminders (§5.21A, C).
/// Ids: `emi:<debtId>:<instalment>:<daysBefore>` and `rec:<id>`.
final class MoneyReminderSource implements ExtraReminderSource {
  MoneyReminderSource({required this.money, required this.text, required this.clock});

  final MoneyRepository money;
  final MoneyReminderText text;
  final Clock clock;

  static const remindAt = 9 * 60;

  @override
  bool owns(String reminderId) => reminderId.startsWith('emi:') || reminderId.startsWith('rec:');

  Future<List<DebtStatus>> _statuses() async {
    final payments = await money.payments();
    final changes = await money.loanChanges();
    final skips = await money.skips();
    return [
      for (final d in await money.debts())
        DebtStatus(
          d,
          [
            for (final p in payments)
              if (p.debtId == d.id) p,
          ],
          changes: [
            for (final c in changes)
              if (c.debtId == d.id) c,
          ],
          skips: [
            for (final s in skips)
              if (s.debtId == d.id) s,
          ],
        ),
    ];
  }

  Future<DebtStatus?> _status(String debtId) async =>
      (await _statuses()).where((s) => s.debt.id == debtId).firstOrNull;

  LocalDate get _today => LocalDate.fromDateTime(clock.now().toLocal());

  @override
  Future<List<SchedulableReminder>> reminders() async {
    final today = _today;
    return [
      for (final s in await _statuses())
        if (s.debt.emi != null &&
            s.debt.remind &&
            !s.debt.settled &&
            s.debt.direction == DebtDirection.iOwe)
          ..._emi(s, today),
      for (final r in await money.recurring())
        if (r.active && r.remind)
          SchedulableReminder(
            plan: PlannerReminder(id: 'rec:${r.id}', rule: r.rule),
            channelId: channelIdFor('routines'),
            title: text.recurringDue(r.name),
          ),
    ];
  }

  Iterable<SchedulableReminder> _emi(DebtStatus s, LocalDate today) sync* {
    final d = s.debt;
    final n = s.nextInstalment;
    final due = s.nextDue;
    if (n == null || due == null) return;
    if (due.isBefore(today)) {
      // Overdue: every day at 09:00 until Paid or Skipped (§5.22F).
      yield SchedulableReminder(
        plan: PlannerReminder(
          id: 'emi:${d.id}:$n:od',
          rule: Daily(times: const [remindAt]),
          startDate: due.addDays(1),
        ),
        channelId: channelIdFor('routines'),
        title: text.emiOverdue(d.name),
        body: text.emiOverdueBody(d.counterparty, n, due),
      );
      return;
    }
    for (final r in emiReminderDays(due, d.remindDaysBefore)) {
      yield SchedulableReminder(
        plan: PlannerReminder(
          id: 'emi:${d.id}:$n:${r.daysBefore}',
          rule: OneTime(date: r.day, time: remindAt),
        ),
        channelId: channelIdFor('routines'),
        title: _emiTitle(d.name, r.daysBefore),
        body: text.emiBody(d.counterparty, n, s.instalmentCount),
      );
    }
  }

  String _emiTitle(String name, int daysBefore) => switch (daysBefore) {
    0 => text.emiToday(name),
    1 => text.emiTomorrow(name),
    _ => text.emiInDays(name, daysBefore),
  };

  @override
  Future<({String title, String? body})> textFor(String reminderId) async {
    final parts = reminderId.split(':');
    if (parts.first == 'rec') {
      final r = (await money.recurring()).where((r) => r.id == parts[1]).firstOrNull;
      return (title: text.recurringDue(r?.name ?? ''), body: null);
    }
    final st = await _status(parts[1]);
    if (st == null || st.debt.emi == null) return (title: '', body: null);
    final n = int.parse(parts[2]);
    if (parts[3] == 'od') {
      return (
        title: text.emiOverdue(st.debt.name),
        body: text.emiOverdueBody(st.debt.counterparty, n, st.rowFor(n)?.due ?? _today),
      );
    }
    return (
      title: _emiTitle(st.debt.name, int.parse(parts[3])),
      body: text.emiBody(st.debt.counterparty, n, st.instalmentCount),
    );
  }

  @override
  String route(String reminderId) {
    final parts = reminderId.split(':');
    return parts.first == 'emi' ? '/money/debts/${parts[1]}' : '/money';
  }

  /// Paid records the instalment (and its expense, per the loan) or the
  /// recurring expense. Skip on an overdue instalment marks it skipped;
  /// otherwise Skip records nothing.
  @override
  Future<void> acted(String reminderId, String occurrenceLocal, {required bool completed}) async {
    final parts = reminderId.split(':');
    final now = clock.now();
    if (parts.first == 'emi') {
      final n = int.parse(parts[2]);
      if (!completed) {
        if (parts[3] == 'od') await money.skipInstalment(parts[1], n, on: _today);
        return;
      }
      final st = await _status(parts[1]);
      if (st == null || st.debt.emi == null) return;
      // Already paid in the app: the result is a validation failure; fine.
      await money.addPayment(
        st.debt.id,
        amountPaise: st.rowFor(n)?.emiPaise ?? st.debt.emi!.emiPaise,
        at: now,
        instalmentNo: n,
      );
      return;
    }
    if (!completed) return;
    final r = (await money.recurring()).where((r) => r.id == parts[1]).firstOrNull;
    if (r == null) return;
    await money.addExpense((
      amountPaise: r.amountPaise,
      categoryId: r.categoryId,
      method: r.method,
      at: now,
      note: r.name,
      mealLogId: null,
    ), recurringExpenseId: r.id);
  }
}
