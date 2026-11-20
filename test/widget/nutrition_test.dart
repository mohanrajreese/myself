import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import 'onboarding_test.dart' show field;

/// A 1×1 transparent PNG, so Image.memory can decode it.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  Future<void> start(WidgetTester tester) async {
    await app.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
    );
    await app.pump(tester, session: signedInSession);
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text).last);

  Future<void> openTab(WidgetTester tester, String tab) =>
      tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));

  /// Home → Add meal → create "Oats" (per 100 g) → add 100 g to the meal.
  Future<void> addOatsToNewMeal(WidgetTester tester) async {
    await tap(tester, find.widgetWithText(OutlinedButton, 'Meal'));
    expect(find.text('Add meal'), findsWidgets);
    await tapText(tester, 'Add food');
    await tapText(tester, 'Create a food');
    await tester.enterText(field('Name'), 'Oats');
    await tester.enterText(field('Serving'), '1 bowl');
    await tester.enterText(field('Calories'), '389');
    await tester.enterText(field('Protein'), '17');
    await tester.enterText(field('Fibre'), '10');
    await tapText(tester, 'Save');
    expect(find.text('Add to meal'), findsOneWidget);
    await tapText(tester, 'Add to meal');
    expect(find.text('Oats'), findsWidgets);
    // Let the "Food saved" message clear so it does not cover the save button.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  group('Water', () {
    testWidgets('a quick amount is saved in one tap and can be removed', (tester) async {
      await start(tester);
      await openTab(tester, 'Nutrition');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Water'));
      await tap(tester, find.bySemanticsLabel('Add 250 ml'));
      expect(find.text('250 ml added'), findsOneWidget);
      var rows = await app.db.select(app.db.waterLogs).get();
      expect(rows.single.amountMl, 250);

      await tap(tester, find.bySemanticsLabel(RegExp('^Remove 250 ml')));
      expect(find.text('Remove this entry?'), findsOneWidget);
      await tapText(tester, 'Remove');
      rows = await app.db.select(app.db.waterLogs).get();
      expect(rows.where((r) => r.deletedAt == null), isEmpty);
      await app.dispose(tester);
    });

    testWidgets('quick add on Home opens the water sheet and updates the tile', (tester) async {
      await start(tester);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Water'));
      expect(find.text('Add water'), findsOneWidget);
      await tap(tester, find.bySemanticsLabel('Add 500 ml'));
      expect(find.text('Add water'), findsNothing);
      expect(find.text('500 ml'), findsWidgets);
      await app.dispose(tester);
    });
  });

  group('Meals', () {
    testWidgets('a meal with a new food is saved and shown in the diary and on Home', (
      tester,
    ) async {
      await start(tester);
      await addOatsToNewMeal(tester);
      await tapText(tester, 'Save meal');
      expect(find.text('Meal saved'), findsOneWidget);
      expect(await app.db.select(app.db.mealLogs).get(), hasLength(1));
      final items = await app.db.select(app.db.mealFoodItems).get();
      expect(items.single.fibreMg, 10000);
      expect(find.text('10 g'), findsWidgets);

      await openTab(tester, 'Nutrition');
      expect(find.text('Nothing logged for this day yet. Add a meal to start.'), findsNothing);
      expect(find.textContaining('389 kcal'), findsWidgets);
      await app.dispose(tester);
    });

    testWidgets('leaving with unsaved items asks before discarding', (tester) async {
      await start(tester);
      await addOatsToNewMeal(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard this meal?'), findsOneWidget);
      await tapText(tester, 'Keep editing');
      expect(find.text('Save meal'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tapText(tester, 'Discard');
      expect(find.text('Save meal'), findsNothing);
      expect(await app.db.select(app.db.mealLogs).get(), isEmpty);
      await app.dispose(tester);
    });

    testWidgets('a meal photo is stored through the encrypted photo store', (tester) async {
      await start(tester);
      app.picker.next = _png;
      await addOatsToNewMeal(tester);
      await tapText(tester, 'Add photo');
      await tapText(tester, 'Choose from photos');
      expect(find.text('Change photo'), findsOneWidget);
      await tapText(tester, 'Save meal');
      final meal = (await app.db.select(app.db.mealLogs).get()).single;
      expect(app.photos.photos[meal.id], _png);
      await app.dispose(tester);
    });

    testWidgets('a meal kept as a saved meal can be logged again in one tap', (tester) async {
      await start(tester);
      await addOatsToNewMeal(tester);
      await tapText(tester, 'Also keep as a saved meal');
      await tapText(tester, 'Save meal');
      await openTab(tester, 'Nutrition');
      await tap(tester, find.widgetWithText(OutlinedButton, 'Saved meals'));
      expect(find.text('Breakfast'), findsWidgets);
      await tapText(tester, 'Log now');
      expect(find.text('Breakfast logged'), findsOneWidget);
      expect(await app.db.select(app.db.mealLogs).get(), hasLength(2));
      await app.dispose(tester);
    });

    testWidgets('a meal cost records a linked Food expense; deleting asks about it', (
      tester,
    ) async {
      await start(tester);
      await addOatsToNewMeal(tester);
      await tester.enterText(field('Cost'), '240');
      await tap(tester, find.bySemanticsLabel('Paid with'));
      await tapText(tester, 'Cash');
      await tapText(tester, 'Save meal');
      final meal = (await app.db.select(app.db.mealLogs).get()).single;
      var expense = (await app.db.select(app.db.expenses).get()).single;
      expect(expense.amountPaise, 24000);
      expect(expense.mealLogId, meal.id);
      expect(expense.method, 'cash');

      await openTab(tester, 'Nutrition');
      await tap(tester, find.textContaining('389 kcal').first);
      expect(find.text('240'), findsOneWidget);
      await tap(tester, find.byTooltip('Delete'));
      expect(find.text('It has a linked expense of ₹240.'), findsOneWidget);
      await tapText(tester, 'Delete meal, keep expense');
      expense = (await app.db.select(app.db.expenses).get()).single;
      expect(expense.deletedAt, isNull);
      expect(expense.mealLogId, isNull);
      await app.dispose(tester);
    });

    testWidgets('an empty meal cannot be saved', (tester) async {
      await start(tester);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Meal'));
      await tapText(tester, 'Save meal');
      expect(find.text('Save meal'), findsOneWidget);
      expect(await app.db.select(app.db.mealLogs).get(), isEmpty);
      await app.dispose(tester);
    });
  });

  testWidgets('the summary shows the fibre target', (tester) async {
    await start(tester);
    await openTab(tester, 'Nutrition');
    await tapText(tester, 'Calories left');
    expect(find.text('Nutrition summary'), findsOneWidget);
    expect(find.text('0 g of 40 g'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Junk food, last 7 days'), 200);
    expect(find.text('None logged.'), findsOneWidget);
    await app.dispose(tester);
  });
}
