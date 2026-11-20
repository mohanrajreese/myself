import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import 'onboarding_test.dart' show field;

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  Future<void> openHealth(WidgetTester tester) async {
    await app.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8', targetWeightText: '80'),
    );
    await app.pump(tester, session: signedInSession);
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Health')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text).last;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('Health tab shows each area with its first-day state', (tester) async {
    await openHealth(tester);
    expect(find.text('91.8 kg'), findsOneWidget);
    expect(find.text('Nothing recorded yet'), findsOneWidget);
    expect(find.text('No sleep logged'), findsOneWidget);
    expect(find.text('Not checked in today'), findsOneWidget);
    await app.dispose(tester);
  });

  group('Weight', () {
    testWidgets('an entry can be edited and deleted', (tester) async {
      await openHealth(tester);
      await tapText(tester, 'Weight');
      expect(find.text('Log at least two weights to see a chart.'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('^Edit entry of')).first);
      await tester.pumpAndSettle();
      expect(find.text('Edit weight'), findsOneWidget);
      await tester.enterText(field('Weight'), '90.4');
      await tapText(tester, 'Save');
      final rows = await app.db.select(app.db.weightLogs).get();
      expect(rows.single.weightG, 90400);

      await tester.tap(find.bySemanticsLabel(RegExp('^Edit entry of')).first);
      await tester.pumpAndSettle();
      await tapText(tester, 'Delete');
      expect(find.text('Delete this entry?'), findsOneWidget);
      await tapText(tester, 'Delete');
      expect(find.text('Deleted'), findsOneWidget);
      final left = await app.db.select(app.db.weightLogs).get();
      expect(left.where((r) => r.deletedAt == null), isEmpty);
      await app.dispose(tester);
    });
  });

  group('Measurements', () {
    testWidgets('a waist measurement is saved and shown with its history', (tester) async {
      await openHealth(tester);
      await tapText(tester, 'Body measurements');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add measurement'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '96.5');
      await tapText(tester, 'Save');
      expect(find.text('Saved'), findsOneWidget);
      final rows = await app.db.select(app.db.bodyMeasurements).get();
      expect(rows.single.valueMilli, 96500);
      await app.dispose(tester);
    });

    testWidgets('an impossible value is rejected and nothing is saved', (tester) async {
      await openHealth(tester);
      await tapText(tester, 'Body measurements');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '0');
      await tapText(tester, 'Save');
      expect(find.text('Add measurement'), findsOneWidget);
      expect(await app.db.select(app.db.bodyMeasurements).get(), isEmpty);
      await app.dispose(tester);
    });
  });

  group('Sleep', () {
    testWidgets('last night is saved from the default times and counted on the Health tab', (
      tester,
    ) async {
      await openHealth(tester);
      await tapText(tester, 'Sleep');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add sleep'), findsOneWidget);
      await tapText(tester, 'Save');
      final rows = await app.db.select(app.db.sleepLogs).get();
      expect(rows, hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('8 h 00 min'), findsOneWidget);
      await app.dispose(tester);
    });
  });

  group('Check-in', () {
    testWidgets('needs every score, then saves', (tester) async {
      await openHealth(tester);
      await tapText(tester, 'Wellness check-in');
      await tapText(tester, 'Save check-in');
      expect(find.text('Choose a score for each scale.'), findsOneWidget);
      expect(await app.db.select(app.db.dailyHealthCheckins).get(), isEmpty);

      final semantics = tester.ensureSemantics();
      for (final scale in ['Energy', 'Mood', 'Stress', 'Overall']) {
        final score = find.bySemanticsLabel('$scale 4');
        await tester.ensureVisible(score);
        await tester.tap(score);
        await tester.pump();
      }
      semantics.dispose();
      await tapText(tester, 'Save check-in');
      expect(find.text('Check-in saved'), findsOneWidget);
      expect(await app.db.select(app.db.dailyHealthCheckins).get(), hasLength(1));
      await app.dispose(tester);
    });
  });
}
