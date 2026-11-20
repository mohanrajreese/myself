import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import 'onboarding_test.dart' show field;

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness(now: DateTime(2026, 11, 20, 13, 10)));

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

  testWidgets('an empty month says so; an expense added from the tab shows up', (tester) async {
    await openMoney(tester);
    expect(find.text('Spent this month'), findsOneWidget);
    expect(find.text('No expenses in this month yet. Add one with Expense.'), findsOneWidget);
    expect(find.text('No monthly budget set.'), findsOneWidget);

    await tap(tester, find.bySemanticsLabel('Add expense'));
    await tapText(tester, 'Save');
    expect(find.text('Enter an amount in rupees, with up to 2 decimals.'), findsOneWidget);
    await tester.enterText(field('Amount'), '90');
    await tapText(tester, 'Transport');
    await tapText(tester, 'Cash');
    await tapText(tester, 'Save');
    final rows = await app.db.select(app.db.expenses).get();
    expect(rows.single.amountPaise, 9000);
    expect(rows.single.method, 'cash');
    expect(find.text('₹90'), findsWidgets);
    expect(find.text('Transport'), findsWidgets);
    await app.dispose(tester);
  });

  testWidgets('editing and deleting an expense asks first', (tester) async {
    await openMoney(tester);
    await tap(tester, find.bySemanticsLabel('Add expense'));
    await tester.enterText(field('Amount'), '240');
    await tapText(tester, 'Save');
    await tap(tester, find.text('₹240').last);
    expect(find.text('Edit expense'), findsOneWidget);
    await tap(tester, find.byTooltip('Delete'));
    expect(find.text('Delete this expense?'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Delete'));
    final row = (await app.db.select(app.db.expenses).get()).single;
    expect(row.deletedAt, isNotNull);
    expect(find.text('No expenses in this month yet. Add one with Expense.'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a monthly budget shows progress in words and numbers', (tester) async {
    await openMoney(tester);
    await tapText(tester, 'Set a budget');
    expect(find.text('No monthly budget yet. Set one to see progress here.'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Set a budget'));
    await tester.enterText(field('Amount'), '30000');
    await tapText(tester, 'Save');
    expect(find.text('₹30,000'), findsWidgets);
    expect(find.text('₹0 spent · ₹30,000 left · 0%'), findsOneWidget);
    final budget = (await app.db.select(app.db.budgets).get()).single;
    expect(budget.amountPaise, 3000000);
    await app.dispose(tester);
  });

  testWidgets('a home loan added late marks past EMIs paid; Mark paid records the next one', (
    tester,
  ) async {
    await openMoney(tester);
    await tapText(tester, 'Debts');
    expect(find.text('Nothing here yet.'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Add a debt or loan'));
    await tapText(tester, 'Bank loan');
    await tester.enterText(field('Name'), 'Home loan');
    await tester.enterText(field('Bank or lender (or the person)'), 'SBI');
    await tester.enterText(field('Original amount'), '1500000');
    await tapText(tester, 'Paid in EMIs');
    await tester.enterText(field('EMI amount'), '12500');
    await tester.enterText(field('Due on day (1–28)'), '5');
    await tester.enterText(field('Number of EMIs'), '240');
    // First EMI: pick 5 Oct 2023 through the date picker's text entry.
    await tap(tester, find.bySemanticsLabel(RegExp('^First EMI')));
    await tap(tester, find.byIcon(Icons.edit_outlined));
    await tester.enterText(find.byType(TextField).last, '10/05/2023');
    await tapText(tester, 'OK');
    expect(find.textContaining('38 EMIs fall before today.'), findsOneWidget);
    await tapText(tester, 'Save');
    expect(find.text('Home loan · SBI'), findsOneWidget);
    expect(find.text('₹25,25,000'), findsWidgets);
    expect(await app.db.select(app.db.debtPayments).get(), hasLength(38));

    await tapText(tester, 'Home loan · SBI');
    expect(find.text('Next EMI: ₹12,500'), findsOneWidget);
    await tapText(tester, 'Mark paid');
    expect(await app.db.select(app.db.debtPayments).get(), hasLength(39));
    expect((await app.db.select(app.db.expenses).get()).single.amountPaise, 1250000);
    expect(find.text('Instalment 39'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('analysis describes the month without advice', (tester) async {
    await openMoney(tester);
    await tap(tester, find.bySemanticsLabel('Add expense'));
    await tester.enterText(field('Amount'), '240');
    await tapText(tester, 'Save');
    await tapText(tester, 'Analysis');
    expect(find.text('Money analysis'), findsOneWidget);
    expect(find.text('• You spent ₹240 more than in the previous period.'), findsOneWidget);
    expect(find.text('Descriptions of your records only, not financial advice.'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a recurring expense is added from the Expenses menu', (tester) async {
    await openMoney(tester);
    await tapText(tester, 'Expenses');
    await tap(tester, find.byTooltip('More options'));
    await tapText(tester, 'Recurring expenses');
    expect(find.textContaining('No recurring expenses yet.'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, 'Add'));
    await tester.enterText(field('Name'), 'Rent');
    await tester.enterText(field('Amount'), '18000');
    await tapText(tester, 'Net banking');
    await tapText(tester, 'Save');
    final row = (await app.db.select(app.db.recurringExpenses).get()).single;
    expect(row.amountPaise, 1800000);
    expect(row.method, 'net_banking');
    expect(find.text('Rent · ₹18,000'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('categories can be added, archived and restored', (tester) async {
    await openMoney(tester);
    await tapText(tester, 'Expenses');
    await tap(tester, find.byTooltip('More options'));
    await tapText(tester, 'Categories');
    expect(find.bySemanticsLabel('Archive EMI and loan repayments'), findsNothing);
    await tap(tester, find.bySemanticsLabel('Archive Education'));
    expect(find.text('Archived'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Restore Education'));
    expect(find.text('Archived'), findsNothing);
    await tap(tester, find.bySemanticsLabel('New category'));
    await tester.enterText(field('Name'), 'Pet care');
    await tapText(tester, 'Save');
    expect(find.text('Pet care'), findsOneWidget);
    await app.dispose(tester);
  });
}
