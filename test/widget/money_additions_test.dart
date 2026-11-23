import 'package:fitbuddy/core/errors/result.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/data/drift_money_repository.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import '../support/fakes.dart';
import 'onboarding_test.dart' show field;

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness(now: DateTime(2026, 12, 8, 10)));

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last,
      );
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(f.last);
    await tester.pumpAndSettle();
    await tester.tap(f.last);
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text));

  DriftMoneyRepository repo() => DriftMoneyRepository(
    app.db,
    clock: app.time.clock,
    ids: app.ids,
    timeZone: const FixedTimeZone(),
  );

  Future<void> openMoney(WidgetTester tester) async {
    await app.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
    );
    await app.pump(tester, session: signedInSession);
    await drain(tester);
    await tap(
      tester,
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Money')),
    );
  }

  /// Database work runs in the test's zone; pumping lets it finish.
  Future<T> settle<T>(WidgetTester tester, Future<T> work) async {
    await drain(tester);
    return work;
  }

  Future<Debt> carLoan(WidgetTester tester) async {
    final r = await settle(
      tester,
      repo().saveDebt(
        Debt(
          id: '',
          direction: DebtDirection.iOwe,
          name: 'Car loan',
          counterparty: 'HDFC',
          kind: DebtKind.bankLoan,
          principalPaise: 60000000,
          startDate: LocalDate(2026, 10, 5),
          interestRateBp: 900,
          emi: EmiPlan(emiPaise: 1245000, day: 5, count: 60, first: LocalDate(2026, 11, 5)),
        ),
      ),
    );
    return (r as Ok<Debt>).value;
  }

  testWidgets('an overdue EMI is labelled and can be skipped; the schedule opens', (tester) async {
    await openMoney(tester);
    await carLoan(tester);
    await tapText(tester, 'Debts');
    expect(find.text('Overdue'), findsWidgets);
    await tapText(tester, 'Car loan · HDFC');
    expect(find.text('Instalment 1: ₹12,450'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Skip'));
    expect(find.text('Skip instalment 1?'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Skip'));
    expect(
      find.textContaining('Instalment 2: '),
      findsOneWidget,
      reason: 'the next one is overdue too',
    );
    await tester.scrollUntilVisible(
      find.text('Skipped · 8 Dec 2026'),
      200,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .last,
    );
    expect(find.text('Skipped · 8 Dec 2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Schedule'),
      -200,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .last,
    );

    await tapText(tester, 'Schedule');
    expect(find.text('Repayment schedule'), findsOneWidget);
    expect(find.text('Interest still to pay'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a part-payment with fewer EMIs is listed and recorded as a payment', (tester) async {
    await openMoney(tester);
    final loan = await carLoan(tester);
    await tapText(tester, 'Debts');
    await tapText(tester, 'Car loan · HDFC');
    await tapText(tester, 'Part-payment');
    await tester.enterText(field('Amount'), '50000');
    await tester.pumpAndSettle();
    expect(find.textContaining('EMIs fewer'), findsOneWidget);
    await tapText(tester, 'Save');
    expect(find.text('Part-payment · fewer EMIs'), findsOneWidget);
    final payments = await settle(tester, repo().payments(debtId: loan.id));
    expect(payments.single.amountPaise, 5000000);
    await app.dispose(tester);
  });

  testWidgets('a credit card records a statement and shows what is left', (tester) async {
    await openMoney(tester);
    await tapText(tester, 'Debts');
    await tap(tester, find.bySemanticsLabel('Add a debt or loan'));
    await tapText(tester, 'Credit card');
    await tester.enterText(field('Name'), 'HDFC Millennia');
    await tester.enterText(field('Bank or lender (or the person)'), 'HDFC');
    await tester.enterText(field('Original amount'), '23480');
    await tester.enterText(field('Statement day (1–28)'), '18');
    await tester.enterText(field('Payment due day (1–28)'), '7');
    await tapText(tester, 'Save');
    await tapText(tester, 'HDFC Millennia · HDFC');
    expect(
      find.text('No statement recorded yet. Add one when your card statement arrives.'),
      findsOneWidget,
    );
    await tap(tester, find.widgetWithText(FilledButton, 'New statement'));
    await tester.enterText(field('Total due'), '23480');
    await tester.enterText(field('Minimum due'), '1180');
    await tapText(tester, 'Save');
    expect(find.text('₹23,480'), findsWidgets);
    expect(find.textContaining('₹23,480 left'), findsOneWidget);
    expect(find.textContaining('minimum not yet met'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('income shows what was saved this month', (tester) async {
    await openMoney(tester);
    await tap(tester, find.bySemanticsLabel('Add income'));
    await tester.enterText(field('Amount'), '85000');
    await tapText(tester, 'Save');
    expect(find.text('₹85,000'), findsWidgets);
    expect(find.text('You saved 100% of your income this month.'), findsOneWidget);
    final rows = await app.db.select(app.db.incomes).get();
    expect(rows.single.amountPaise, 8500000);
    await app.dispose(tester);
  });

  testWidgets('splitting an expense equally creates Owed-to-me debts', (tester) async {
    await openMoney(tester);
    await tap(tester, find.bySemanticsLabel('Add expense'));
    await tester.enterText(field('Amount'), '2400');
    await tapText(tester, 'Split with others');
    await tapText(tester, '+ Person');
    await tester.enterText(field('Name'), 'Ravi');
    await tap(tester, find.widgetWithText(FilledButton, 'Save').last);
    await tapText(tester, '+ Person');
    await tester.enterText(field('Name'), 'Priya');
    await tap(tester, find.widgetWithText(FilledButton, 'Save').last);
    expect(find.text('₹800'), findsNWidgets(3));
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    final debts = await app.db.select(app.db.debts).get();
    expect(debts.map((d) => (d.counterparty, d.principalPaise, d.direction)), [
      ('Ravi', 80000, 'owed_to_me'),
      ('Priya', 80000, 'owed_to_me'),
    ]);
    expect((await app.db.select(app.db.expenses).get()).single.amountPaise, 240000);
    await app.dispose(tester);
  });

  testWidgets('budget alerts can be turned off in Money settings', (tester) async {
    await openMoney(tester);
    await tap(tester, find.byTooltip('More options'));
    await tapText(tester, 'Money settings');
    expect(find.text('When a budget reaches 80% and 100% in a month'), findsOneWidget);
    await tapText(tester, '90%');
    expect(find.text('When a budget reaches 90% and 100% in a month'), findsOneWidget);
    await tapText(tester, 'Budget alerts');
    expect(find.text('First alert at'), findsNothing);
    await app.dispose(tester);
  });
}
