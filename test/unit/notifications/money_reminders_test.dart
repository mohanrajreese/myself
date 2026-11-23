import 'package:fitbuddy/app/money_reminder_source.dart';
import 'package:fitbuddy/app/reminder_service.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/settings_repository.dart';
import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/core/notifications/notification_gateway.dart';
import 'package:fitbuddy/core/notifications/notification_state_store.dart';
import 'package:fitbuddy/core/scheduling/occurrence_calculator.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/activities/data/drift_activity_repository.dart';
import 'package:fitbuddy/features/money/data/drift_money_repository.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:fitbuddy/features/reminders/data/drift_reminder_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class Utc implements TimeZoneRules {
  @override
  Duration offsetAt(DateTime instant) => Duration.zero;
}

final text = MoneyReminderText(
  emiInDays: (name, days) => 'EMI in $days days: $name',
  emiTomorrow: (name) => 'EMI due tomorrow: $name',
  emiToday: (name) => 'EMI due today: $name',
  emiBody: (lender, n, count) => '$lender · instalment $n of $count',
  recurringDue: (name) => '$name is due today',
  emiOverdue: (name) => 'EMI overdue: $name',
  emiOverdueBody: (lender, n, due) => '$lender · instalment $n was due on $due',
  card: (name, days) => 'Card payment in $days days: $name',
  cardBody: (st, due) => 'Statement of $st · due $due',
  dueOwe: (name, days) => '$name: due in $days days',
  dueOweBody: (person) => 'Money you owe $person',
  dueLent: (name, days) => 'Money you lent to $name: due in $days days',
  dueLentBody: 'Tap to record what you received',
  incomeDue: (name) => '$name: expected today',
);

void main() {
  late AppDatabase db;
  late MutableClock time;
  late FakeNotificationGateway gateway;
  late NotificationStateStore store;
  late DriftMoneyRepository money;
  late ReminderService service;

  setUp(() async {
    db = memoryDatabase();
    // 28 Nov 2026, 08:00: the 7-day reminder for 5 Dec is due at 09:00.
    time = MutableClock(DateTime.utc(2026, 11, 28, 8));
    final ids = SequentialIds();
    gateway = FakeNotificationGateway();
    store = NotificationStateStore(db);
    money = DriftMoneyRepository(db, clock: time.clock, ids: ids, timeZone: const FixedTimeZone());
    await money.seedCategories(const {});
    service = ReminderService(
      reminders: DriftReminderRepository(db, clock: time.clock, ids: ids),
      activities: DriftActivityRepository(
        db,
        clock: time.clock,
        ids: ids,
        timeZone: const FixedTimeZone(),
      ),
      settings: SettingsRepository(db, clock: time.clock),
      store: store,
      gateway: gateway,
      capabilities: FakeAlarmCapabilities(),
      timeZone: const FixedTimeZone(),
      clock: time.clock,
      zoneFor: (_) => Utc(),
      extraSources: [MoneyReminderSource(money: money, text: text, clock: time.clock)],
    );
  });
  tearDown(() => db.close());

  Future<Debt> homeLoan({int lead = 7, bool remind = true}) async =>
      ((await money.saveDebt(
                Debt(
                  id: '',
                  direction: DebtDirection.iOwe,
                  name: 'Home loan',
                  counterparty: 'SBI',
                  kind: DebtKind.bankLoan,
                  principalPaise: 150000000,
                  startDate: LocalDate(2023, 9, 5),
                  emi: EmiPlan(
                    emiPaise: 1250000,
                    day: 5,
                    count: 240,
                    first: LocalDate(2023, 10, 5),
                  ),
                  remindDaysBefore: lead,
                  remind: remind,
                ),
                markPastInstalmentsPaid: true,
              ))
              as Ok<Debt>)
          .value;

  List<NotificationRequest> emiNotes() =>
      gateway.pending.values.where((n) => n.title.contains('EMI')).toList()
        ..sort((a, b) => a.at!.compareTo(b.at!));

  test('EMI reminders come 7 days before and 1 day before, at 09:00, without the amount', () async {
    await homeLoan();
    await service.replan();
    final notes = emiNotes();
    expect(notes.map((n) => n.at), [DateTime.utc(2026, 11, 28, 9), DateTime.utc(2026, 12, 4, 9)]);
    expect(notes.first.title, 'EMI in 7 days: Home loan');
    expect(notes.first.body, 'SBI · instalment 39 of 240');
    expect(notes.last.title, 'EMI due tomorrow: Home loan');
    expect(notes.every((n) => !'${n.title}${n.body}'.contains('12,500')), isTrue);
  });

  test('the due-day reminder says "EMI due today"', () async {
    time.now = DateTime.utc(2026, 12, 5, 6);
    await homeLoan();
    await service.replan();
    expect(emiNotes().single.title, 'EMI due today: Home loan');
  });

  test('a longer lead time moves only the first reminder', () async {
    time.now = DateTime.utc(2026, 11, 20, 8);
    await homeLoan(lead: 14);
    await service.replan();
    expect(emiNotes().first.at, DateTime.utc(2026, 11, 21, 9));
  });

  test('Paid records the instalment and an expense, and stops the remaining reminders', () async {
    final loan = await homeLoan();
    await service.replan();
    final first = (await store.active()).firstWhere((r) => r.reminderId.startsWith('emi:'));
    await service.handle(
      NotificationTap(notificationId: first.id, action: ReminderAction.complete),
    );
    final paid = await money.payments(debtId: loan.id);
    expect(paid.first.instalmentNo, 39);
    expect(paid.first.amountPaise, 1250000);
    final expenses = await db.select(db.expenses).get();
    expect(expenses.single.categoryId, DriftMoneyRepository.categoryId('emi'));
    expect(emiNotes(), isEmpty, reason: 'the next instalment (5 Jan) is outside the window');
  });

  test('Skip records nothing; the instalment stays due', () async {
    final loan = await homeLoan();
    await service.replan();
    final first = (await store.active()).firstWhere((r) => r.reminderId.startsWith('emi:'));
    await service.handle(NotificationTap(notificationId: first.id, action: ReminderAction.skip));
    expect(DebtStatus(loan, await money.payments(debtId: loan.id)).nextInstalment, 39);
    expect(emiNotes().map((n) => n.title), ['EMI due tomorrow: Home loan']);
  });

  test('Snooze keeps the text; tapping the body opens the loan', () async {
    final loan = await homeLoan();
    await service.replan();
    final first = (await store.active()).firstWhere((r) => r.reminderId.startsWith('emi:'));
    time.now = DateTime.utc(2026, 11, 28, 9);
    await service.handle(
      NotificationTap(notificationId: first.id, action: ReminderAction.snooze),
      snoozeMinutes: 60,
    );
    expect(gateway.pending[first.id]!.at, DateTime.utc(2026, 11, 28, 10));
    expect(gateway.pending[first.id]!.title, 'EMI in 7 days: Home loan');
    expect(
      await service.handle(NotificationTap(notificationId: first.id)),
      '/money/debts/${loan.id}',
    );
  });

  test('no reminders when they are off, the loan is settled, or paid ahead', () async {
    final loan = await homeLoan(remind: false);
    await service.replan();
    expect(emiNotes(), isEmpty);
    await money.saveDebt(
      Debt(
        id: loan.id,
        direction: loan.direction,
        name: loan.name,
        counterparty: loan.counterparty,
        kind: loan.kind,
        principalPaise: loan.principalPaise,
        startDate: loan.startDate,
        emi: loan.emi,
      ),
    );
    await money.addPayment(loan.id, amountPaise: 1250000, at: time.now, instalmentNo: 39);
    await service.replan();
    expect(emiNotes(), isEmpty, reason: 'paying early stops the rest');
    await money.setSettled(loan.id, settled: true);
    await service.replan();
    expect(emiNotes(), isEmpty);
  });

  test('a recurring expense reminds on schedule and Paid records the expense', () async {
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
    await service.replan();
    final note = gateway.pending.values.singleWhere((n) => n.title == 'Rent is due today');
    expect(note.at, DateTime.utc(2026, 12, 1, 9));
    final record = (await store.active()).singleWhere((r) => r.reminderId == 'rec:${rent.id}');
    await service.handle(
      NotificationTap(notificationId: record.id, action: ReminderAction.complete),
    );
    final e = (await db.select(db.expenses).get()).single;
    expect(e.amountPaise, 1800000);
    expect(e.recurringExpenseId, rent.id);
    expect(e.method, 'net_banking');
  });

  test('an overdue instalment reminds daily until Paid or Skipped', () async {
    final loan = await homeLoan();
    time.now = DateTime.utc(2026, 12, 8, 6); // instalment 39 was due on 5 Dec
    await service.replan();
    final notes = emiNotes();
    expect(notes.first.title, 'EMI overdue: Home loan');
    expect(notes.first.body, 'SBI · instalment 39 was due on 2026-12-05');
    expect(notes.map((n) => n.at!.day).take(3), [8, 9, 10]);
    final first = (await store.active()).firstWhere((r) => r.reminderId.endsWith(':od'));
    await service.handle(NotificationTap(notificationId: first.id, action: ReminderAction.skip));
    expect((await money.skips()).single.instalmentNo, 39);
    expect(emiNotes().where((n) => n.title.startsWith('EMI overdue')), isEmpty);
    final payments = await money.payments(debtId: loan.id);
    expect(payments, hasLength(38), reason: 'Skip records no money');
  });

  test('Paid on an overdue reminder records the instalment', () async {
    final loan = await homeLoan();
    time.now = DateTime.utc(2026, 12, 8, 6);
    await service.replan();
    final first = (await store.active()).firstWhere((r) => r.reminderId.endsWith(':od'));
    await service.handle(
      NotificationTap(notificationId: first.id, action: ReminderAction.complete),
    );
    expect((await money.payments(debtId: loan.id)).first.instalmentNo, 39);
  });

  test('a card statement reminds before its due date and Paid pays what is left', () async {
    final card =
        ((await money.saveDebt(
                  Debt(
                    id: '',
                    direction: DebtDirection.iOwe,
                    name: 'HDFC Millennia',
                    counterparty: 'HDFC',
                    kind: DebtKind.creditCard,
                    principalPaise: 2348000,
                    startDate: LocalDate(2026, 11, 18),
                    statementDay: 18,
                    cardDueDay: 7,
                    recordAsExpense: false,
                  ),
                ))
                as Ok<Debt>)
            .value;
    await money.saveStatement(
      CardStatement(
        id: '',
        debtId: card.id,
        statementDate: LocalDate(2026, 11, 18),
        dueDate: LocalDate(2026, 12, 3),
        totalDuePaise: 2348000,
        minDuePaise: 118000,
      ),
    );
    await money.addPayment(card.id, amountPaise: 1000000, at: DateTime.utc(2026, 11, 25));
    await service.replan();
    final notes = gateway.pending.values.where((n) => n.title.startsWith('Card payment')).toList();
    expect(
      notes.map((n) => n.at),
      containsAll([DateTime.utc(2026, 12, 2, 9), DateTime.utc(2026, 12, 3, 9)]),
    );
    final rec = (await store.active()).firstWhere((r) => r.reminderId.startsWith('card:'));
    await service.handle(NotificationTap(notificationId: rec.id, action: ReminderAction.complete));
    final paid = await money.payments(debtId: card.id);
    expect(paid.map((p) => p.amountPaise), containsAll([1000000, 1348000]));
    expect(gateway.pending.values.where((n) => n.title.startsWith('Card payment')), isEmpty);
  });

  test('a personal debt reminds on its due date (and the day before when chosen)', () async {
    await money.saveDebt(
      Debt(
        id: '',
        direction: DebtDirection.owedToMe,
        name: 'Priya',
        counterparty: 'Priya',
        kind: DebtKind.personal,
        principalPaise: 850000,
        startDate: LocalDate(2026, 11, 1),
        dueDate: LocalDate(2026, 12, 1),
        dueRemind: true,
        dueRemindDays: 1,
      ),
    );
    await service.replan();
    final notes = gateway.pending.values.where((n) => n.title.startsWith('Money you lent')).toList()
      ..sort((a, b) => a.at!.compareTo(b.at!));
    expect(notes.map((n) => n.at), [DateTime.utc(2026, 11, 30, 9), DateTime.utc(2026, 12, 1, 9)]);
    expect(notes.every((n) => !'${n.title}${n.body}'.contains('8,500')), isTrue);
  });

  test('recurring income reminds and Received records the income', () async {
    await money.seedIncomeSources(const {});
    final salary =
        ((await money.saveRecurring(
                  RecurringExpense(
                    id: '',
                    name: 'Salary',
                    amountPaise: 8000000,
                    categoryId: DriftMoneyRepository.categoryId('salary'),
                    method: PaymentMethod.netBanking,
                    rule: Monthly.dayOfMonth(1, times: const [540]),
                    isIncome: true,
                  ),
                ))
                as Ok<RecurringExpense>)
            .value;
    await service.replan();
    final rec = (await store.active()).singleWhere((r) => r.reminderId == 'rec:${salary.id}');
    expect(gateway.pending[rec.id]!.title, 'Salary: expected today');
    await service.handle(NotificationTap(notificationId: rec.id, action: ReminderAction.complete));
    final incomes = await money
        .watchIncomes(from: LocalDate(2026, 11, 1), to: LocalDate(2026, 12, 31))
        .first;
    expect(incomes.single.amountPaise, 8000000);
    expect(await db.select(db.expenses).get(), isEmpty);
  });
}
