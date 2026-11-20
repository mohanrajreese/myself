import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/reminder_scheduler.dart';
import '../core/scheduling/reminder_planner.dart';
import '../core/scheduling/schedule_rule.dart';
import '../core/utils/clock.dart';
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
  });
  final String Function(String name, int days) emiInDays;
  final String Function(String name) emiTomorrow;
  final String Function(String name) emiToday;
  final String Function(String lender, int instalment, int count) emiBody;
  final String Function(String name) recurringDue;
}

MoneyReminderText moneyReminderText(AppLocalizations l10n) => MoneyReminderText(
  emiInDays: (name, days) => l10n.moneyEmiInDays(days, name),
  emiTomorrow: l10n.moneyEmiTomorrow,
  emiToday: l10n.moneyEmiToday,
  emiBody: l10n.moneyEmiBody,
  recurringDue: l10n.moneyRecurringDue,
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

  @override
  Future<List<SchedulableReminder>> reminders() async {
    final payments = await money.payments();
    return [
      for (final d in await money.debts())
        if (d.emi != null && d.remind && !d.settled && d.direction == DebtDirection.iOwe)
          ..._emi(
            d,
            DebtStatus(d, [
              for (final p in payments)
                if (p.debtId == d.id) p,
            ]),
          ),
      for (final r in await money.recurring())
        if (r.active && r.remind)
          SchedulableReminder(
            plan: PlannerReminder(id: 'rec:${r.id}', rule: r.rule),
            channelId: channelIdFor('routines'),
            title: text.recurringDue(r.name),
          ),
    ];
  }

  Iterable<SchedulableReminder> _emi(Debt d, DebtStatus s) sync* {
    final n = s.nextInstalment;
    final due = s.nextDue;
    if (n == null || due == null) return;
    for (final r in emiReminderDays(due, d.remindDaysBefore)) {
      yield SchedulableReminder(
        plan: PlannerReminder(
          id: 'emi:${d.id}:$n:${r.daysBefore}',
          rule: OneTime(date: r.day, time: remindAt),
        ),
        channelId: channelIdFor('routines'),
        title: _emiTitle(d.name, r.daysBefore),
        body: text.emiBody(d.counterparty, n, d.emi!.count),
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
    final d = (await money.debts()).where((d) => d.id == parts[1]).firstOrNull;
    if (d == null || d.emi == null) return (title: '', body: null);
    return (
      title: _emiTitle(d.name, int.parse(parts[3])),
      body: text.emiBody(d.counterparty, int.parse(parts[2]), d.emi!.count),
    );
  }

  @override
  String route(String reminderId) {
    final parts = reminderId.split(':');
    return parts.first == 'emi' ? '/money/debts/${parts[1]}' : '/money';
  }

  /// Paid records the instalment (and its expense, per the loan) or the
  /// recurring expense; Skip records nothing.
  @override
  Future<void> acted(String reminderId, String occurrenceLocal, {required bool completed}) async {
    if (!completed) return;
    final parts = reminderId.split(':');
    final now = clock.now();
    if (parts.first == 'emi') {
      final d = (await money.debts()).where((d) => d.id == parts[1]).firstOrNull;
      if (d == null || d.emi == null) return;
      // Already paid in the app: the result is a validation failure; fine.
      await money.addPayment(
        d.id,
        amountPaise: d.emi!.emiPaise,
        at: now,
        instalmentNo: int.parse(parts[2]),
      );
      return;
    }
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
