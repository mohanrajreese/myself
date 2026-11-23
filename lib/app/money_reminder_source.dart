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
    required this.card,
    required this.cardBody,
    required this.dueOwe,
    required this.dueOweBody,
    required this.dueLent,
    required this.dueLentBody,
    required this.incomeDue,
  });
  final String Function(String name, int days) emiInDays;
  final String Function(String name) emiTomorrow;
  final String Function(String name) emiToday;
  final String Function(String lender, int instalment, int count) emiBody;
  final String Function(String name) recurringDue;
  final String Function(String name) emiOverdue;
  final String Function(String lender, int instalment, LocalDate due) emiOverdueBody;
  final String Function(String card, int daysBefore) card;
  final String Function(LocalDate statement, LocalDate due) cardBody;
  final String Function(String name, int daysBefore) dueOwe;
  final String Function(String person) dueOweBody;
  final String Function(String name, int daysBefore) dueLent;
  final String dueLentBody;
  final String Function(String name) incomeDue;
}

MoneyReminderText moneyReminderText(AppLocalizations l10n) => MoneyReminderText(
  emiInDays: (name, days) => l10n.moneyEmiInDays(days, name),
  emiTomorrow: l10n.moneyEmiTomorrow,
  emiToday: l10n.moneyEmiToday,
  emiBody: l10n.moneyEmiBody,
  recurringDue: l10n.moneyRecurringDue,
  emiOverdue: l10n.moneyEmiOverdue,
  emiOverdueBody: (lender, n, due) => l10n.moneyEmiOverdueBody(lender, n, _day(due)),
  card: (name, days) => l10n.moneyCardDue(days, name),
  cardBody: (st, due) => l10n.moneyCardDueBody(_day(st), _day(due)),
  dueOwe: (name, days) => l10n.moneyDueOwe(days, name),
  dueOweBody: l10n.moneyDueOweBody,
  dueLent: (name, days) => l10n.moneyDueLent(days, name),
  dueLentBody: l10n.moneyDueLentBody,
  incomeDue: l10n.moneyIncomeDue,
);

String _day(LocalDate d) => DateFormat('d MMM').format(DateTime(d.year, d.month, d.day));

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
  bool owns(String reminderId) =>
      reminderId.startsWith('emi:') ||
      reminderId.startsWith('rec:') ||
      reminderId.startsWith('card:') ||
      reminderId.startsWith('due:');

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
            title: r.isIncome ? text.incomeDue(r.name) : text.recurringDue(r.name),
          ),
      ...await _cards(),
      for (final s in await _statuses())
        if (s.debt.emi == null &&
            !s.debt.isCard &&
            s.debt.dueRemind &&
            !s.debt.settled &&
            s.debt.dueDate != null)
          ..._due(s.debt),
    ];
  }

  Future<List<CardStatus>> _cardStatuses() async {
    final statements = await money.statements();
    final payments = await money.payments();
    final spent = await money.expensesOnCards();
    return [
      for (final d in await money.debts())
        if (d.isCard && !d.settled) CardStatus(d, statements, payments, spent),
    ];
  }

  Future<List<SchedulableReminder>> _cards() async => [
    for (final c in await _cardStatuses())
      if (c.latest != null && c.latest!.remind && c.leftPaise > 0)
        for (final r in emiReminderDays(c.latest!.dueDate, c.card.remindDaysBefore))
          SchedulableReminder(
            plan: PlannerReminder(
              id: 'card:${c.card.id}:${c.latest!.id}:${r.daysBefore}',
              rule: OneTime(date: r.day, time: remindAt),
            ),
            channelId: channelIdFor('routines'),
            title: text.card(c.card.name, r.daysBefore),
            body: text.cardBody(c.latest!.statementDate, c.latest!.dueDate),
          ),
  ];

  Iterable<SchedulableReminder> _due(Debt d) sync* {
    final due = d.dueDate!;
    for (final before in {d.dueRemindDays, 0}) {
      yield SchedulableReminder(
        plan: PlannerReminder(
          id: 'due:${d.id}:$before',
          rule: OneTime(date: due.addDays(-before), time: remindAt),
        ),
        channelId: channelIdFor('routines'),
        title: d.direction == DebtDirection.iOwe
            ? text.dueOwe(d.name, before)
            : text.dueLent(d.name, before),
        body: d.direction == DebtDirection.iOwe
            ? text.dueOweBody(d.counterparty)
            : text.dueLentBody,
      );
    }
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
      if (r == null) return (title: '', body: null);
      return (title: r.isIncome ? text.incomeDue(r.name) : text.recurringDue(r.name), body: null);
    }
    if (parts.first == 'card') {
      final c = (await _cardStatuses()).where((c) => c.card.id == parts[1]).firstOrNull;
      if (c == null || c.latest == null) return (title: '', body: null);
      return (
        title: text.card(c.card.name, int.parse(parts[3])),
        body: text.cardBody(c.latest!.statementDate, c.latest!.dueDate),
      );
    }
    if (parts.first == 'due') {
      final d = (await money.debts()).where((d) => d.id == parts[1]).firstOrNull;
      if (d == null) return (title: '', body: null);
      final before = int.parse(parts[2]);
      return d.direction == DebtDirection.iOwe
          ? (title: text.dueOwe(d.name, before), body: text.dueOweBody(d.counterparty))
          : (title: text.dueLent(d.name, before), body: text.dueLentBody);
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
    return switch (parts.first) {
      'emi' || 'card' || 'due' => '/money/debts/${parts[1]}',
      _ => '/money',
    };
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
    if (parts.first == 'card') {
      final c = (await _cardStatuses()).where((c) => c.card.id == parts[1]).firstOrNull;
      if (c == null || c.leftPaise <= 0) return;
      await money.addPayment(c.card.id, amountPaise: c.leftPaise, at: now);
      return;
    }
    if (parts.first == 'due') {
      final st = await _status(parts[1]);
      if (st == null || st.outstandingPaise <= 0) return;
      await money.addPayment(st.debt.id, amountPaise: st.outstandingPaise, at: now);
      return;
    }
    final r = (await money.recurring()).where((r) => r.id == parts[1]).firstOrNull;
    if (r == null) return;
    if (r.isIncome) {
      await money.addIncome((
        amountPaise: r.amountPaise,
        categoryId: r.categoryId,
        at: now,
        note: r.name,
      ), recurringId: r.id);
      return;
    }
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
