import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/profile/data/drift_goals_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

Finder field(String label) => find.descendant(
  of: find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
  matching: find.byType(EditableText),
);

Future<void> next(WidgetTester tester, [String label = 'Continue']) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  testWidgets('the whole flow: profile, goals from weight, day, permissions, summary, Home', (
    tester,
  ) async {
    await app.pump(tester, session: signedInSession);
    expect(find.text('About you'), findsOneWidget);

    await tester.enterText(field('Height'), '172.5');
    await tester.enterText(field('Current weight'), '91.8');
    await next(tester);

    expect(find.text('Your goals'), findsOneWidget);
    expect(find.text('3 of 6'), findsOneWidget);
    expect(tester.widget<EditableText>(field('Daily calories')).controller.text, '2750');
    expect(tester.widget<EditableText>(field('Daily protein')).controller.text, '110');
    expect(tester.widget<EditableText>(field('Daily water')).controller.text, '3200');
    expect(tester.widget<EditableText>(field('Daily steps')).controller.text, '8000');
    expect(find.textContaining('Not medical advice'), findsOneWidget);

    await tester.enterText(field('Target weight'), '80');
    await tester.ensureVisible(find.text('Recalculate'));
    await tester.tap(find.text('Recalculate'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(field('Daily calories')).controller.text, '2300');
    expect(tester.widget<EditableText>(field('Daily protein')).controller.text, '145');

    await tester.ensureVisible(find.text('Build strength'));
    await tester.tap(find.text('Build strength'));
    await tester.pumpAndSettle();
    await next(tester);

    expect(find.text('Your day'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Monday'));
    await tester.tap(find.bySemanticsLabel('Friday'));
    await tester.ensureVisible(find.text('Water reminders'));
    await tester.tap(find.text('Water reminders'));
    await tester.pumpAndSettle();
    await next(tester);

    expect(find.text('Permissions, when needed'), findsOneWidget);
    expect(find.textContaining('Nothing is requested now'), findsOneWidget);
    for (final title in ['Physical activity', 'Notifications', 'Exact alarms', 'Usage access']) {
      expect(find.text(title), findsOneWidget);
    }
    await next(tester);

    expect(find.text('Check your setup'), findsOneWidget);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('91.8 kg'), findsOneWidget);
    expect(find.text('2300 kcal'), findsOneWidget);
    expect(find.text('Build strength'), findsOneWidget);
    expect(find.text('Water'), findsOneWidget);
    await tester.ensureVisible(find.text('Finish setup'));
    await next(tester, 'Finish setup');

    expect(find.text('Good morning, Asha'), findsOneWidget);
    final goals = DriftGoalsRepository(app.db, clock: app.time.clock, ids: app.ids);
    final saved = (await goals.dailyGoalsOn(LocalDate(2026, 11, 16)))!;
    expect(saved.targetWeightG, 80000);
    expect(saved.dailyWaterMl, 3200);
    expect((await app.db.select(app.db.weightLogs).get()).single.weightG, 91800);
    await app.dispose(tester);
  });

  testWidgets('a name is required; other fields can be skipped', (tester) async {
    await app.pump(tester, session: signedInSession);
    await tester.enterText(field('Name'), '');
    await next(tester);
    expect(find.text('Enter your name.'), findsOneWidget);
    expect(find.text('Check the highlighted fields.'), findsOneWidget);
    expect(find.text('About you'), findsOneWidget);

    await tester.enterText(field('Name'), 'Asha');
    await next(tester);
    expect(find.text('Your goals'), findsOneWidget);
    expect(find.textContaining('Add your weight on the previous step'), findsOneWidget);
    expect(tester.widget<EditableText>(field('Daily calories')).controller.text, isEmpty);
    await app.dispose(tester);
  });

  testWidgets('an impossible weight is rejected with a message', (tester) async {
    await app.pump(tester, session: signedInSession);
    await tester.enterText(field('Current weight'), '0.2');
    await next(tester);
    expect(find.text('That value is outside the allowed range.'), findsOneWidget);
    expect(find.text('About you'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('switching units converts the typed values', (tester) async {
    await app.pump(tester, session: signedInSession);
    await tester.enterText(field('Current weight'), '91.8');
    await tester.tap(find.text('lb · in · fl oz'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(field('Current weight')).controller.text, '202.4');
    expect(find.text('lb'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('progress survives a restart and reopens at the same step', (tester) async {
    await app.pump(tester, session: signedInSession);
    await tester.enterText(field('Current weight'), '91.8');
    await next(tester);
    await next(tester);
    expect(find.text('Your day'), findsOneWidget);

    await app.pump(tester, session: signedInSession);
    expect(find.text('Your day'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(field('Daily calories')).controller.text, '2750');
    await app.dispose(tester);
  });

  testWidgets('Edit on the summary returns to that step and keeps the data', (tester) async {
    await app.pump(tester, session: signedInSession);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(find.text('Check your setup'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Edit Goals'));
    await tester.pumpAndSettle();
    expect(find.text('Your goals'), findsOneWidget);
    expect(tester.widget<EditableText>(field('Daily steps')).controller.text, '8000');
    await app.dispose(tester);
  });
}
