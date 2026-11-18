import 'dart:async';

import 'package:fitbuddy/app/routes.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> start(WidgetTester tester) async {
    await app.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
    );
    await app.pump(tester, session: signedInSession);
    await drain(tester);
  }

  Future<void> go(WidgetTester tester, String path) async {
    unawaited(GoRouter.of(tester.element(find.byType(Scaffold).first)).push(path));
    await drain(tester);
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(f.last);
    await tester.pump();
    await tester.tap(f.last);
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text));

  Future<void> setPin(WidgetTester tester, String pin) async {
    await go(tester, Routes.appLock);
    await tap(tester, find.byType(Switch).first);
    await tester.enterText(find.byType(EditableText).at(0), pin);
    await tester.enterText(find.byType(EditableText).at(1), pin);
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
  }

  testWidgets('Habits "More" lists the lifestyle areas', (tester) async {
    await start(tester);
    await tap(
      tester,
      find.descendant(of: find.byType(NavigationBar), matching: find.text('Habits')),
    );
    await tapText(tester, 'More');
    for (final t in [
      'Hygiene',
      'Medication and supplements',
      'Posture and recovery',
      'Screen time',
      'Private space',
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    await tapText(tester, 'Private space');
    expect(find.text('Set up the app lock first'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a PIN opens the private space; lock asks again; wrong PIN is refused', (
    tester,
  ) async {
    await start(tester);
    await setPin(tester, '2468');
    expect(app.secureWindow.secure, isTrue);
    expect(await app.secrets.read('app_lock_pin'), isNot(contains('2468')));
    await go(tester, Routes.privateSpace);
    expect(find.text('Private habits'), findsOneWidget);
    expect(find.text('Porn'), findsOneWidget);

    await tapText(tester, 'Lock');
    await go(tester, Routes.privateSpace);
    expect(find.text('Enter your PIN'), findsOneWidget);
    for (final d in ['1', '1', '1', '1']) {
      await tap(tester, find.text(d));
    }
    // Digits alone never count as a try.
    expect(find.text('Wrong PIN'), findsNothing);
    await tap(tester, find.bySemanticsLabel('Unlock'));
    expect(find.text('Wrong PIN'), findsOneWidget);
    for (final d in ['2', '4', '6', '8']) {
      await tap(tester, find.text(d));
    }
    await tap(tester, find.bySemanticsLabel('Unlock'));
    expect(find.text('Private habits'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('private habit and bowel records stay out of the sync outbox', (tester) async {
    await start(tester);
    await setPin(tester, '2468');
    await go(tester, Routes.privateSpace);
    await tapText(tester, 'Porn');
    await tapText(tester, 'Record now');
    expect(find.text('1 time'), findsWidgets);

    await go(tester, Routes.bowel);
    await tapText(tester, 'Straining');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('Normal · Straining'), findsOneWidget);

    final outbox = await app.db.select(app.db.syncOutbox).get();
    expect(
      outbox.map((r) => r.entityTable),
      everyElement(isNot(anyOf(contains('private'), contains('bowel'), contains('habit')))),
    );
    await app.dispose(tester);
  });

  testWidgets('medication: add, mark taken; reminder is generic and secret', (tester) async {
    await start(tester);
    await go(tester, Routes.medication);
    expect(find.text('Nothing added yet.'), findsWidgets);
    await go(tester, Routes.medicationEdit('new'));
    await tester.enterText(find.byType(EditableText).at(0), 'Vitamin D');
    await tester.enterText(find.byType(EditableText).at(1), '1 tablet');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('Vitamin D'), findsWidgets);
    await tap(tester, find.widgetWithText(FilledButton, 'Taken'));
    expect(find.textContaining('1 tablet · Taken'), findsOneWidget);

    final requests = app.notifications.pending.values.where((r) => r.secret).toList();
    expect(requests, isNotEmpty);
    for (final r in requests) {
      expect(r.title, 'FitBuddy reminder');
      expect(r.title, isNot(contains('Vitamin')));
    }
    expect(app.notifications.pending.values.any((r) => r.title.contains('Vitamin')), isFalse);
    await app.dispose(tester);
  });

  testWidgets('hygiene: add the standard routines, mark all done', (tester) async {
    await start(tester);
    await go(tester, Routes.hygiene);
    await tapText(tester, 'Add the standard routines');
    expect(find.text('Brush teeth, night'), findsOneWidget);
    expect(find.text('Add the standard routines'), findsNothing);
    await tapText(tester, 'Mark all done');
    expect(find.text('Mark all done'), findsNothing);
    await app.dispose(tester);
  });

  testWidgets('recovery: rest day saved; posture reminder created', (tester) async {
    await start(tester);
    await go(tester, Routes.recovery);
    await tapText(tester, 'Rest day');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Rest day'), findsNWidgets(2));
    await tapText(tester, 'Posture break');
    expect(find.text('Change times'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('screen time: without access, the settings page opens', (tester) async {
    app.usage.access = false;
    await start(tester);
    await go(tester, Routes.screenTime);
    expect(find.text('Usage access is off'), findsOneWidget);
    await tapText(tester, 'Open usage access settings');
    expect(app.usage.settingsOpened, 1);
    await app.dispose(tester);
  });

  testWidgets('screen time: usage shows totals and most used apps', (tester) async {
    app.usage.today = const [
      (packageName: 'com.example.reader', label: 'Reader', foregroundMs: 45 * 60000),
    ];
    await start(tester);
    await go(tester, Routes.screenTime);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await drain(tester);
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('45 min'), findsWidgets);
    await app.dispose(tester);
  });

  testWidgets('private screens meet tap-target, label and contrast guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await start(tester);
    await setPin(tester, '2468');
    for (final path in [
      Routes.privateSpace,
      Routes.bowel,
      Routes.privateActivities,
      Routes.progressPhotos,
      Routes.privateReminders,
      Routes.privateReport,
    ]) {
      await go(tester, path);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: path);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: path);
      await expectLater(tester, meetsGuideline(textContrastGuideline), reason: path);
    }
    handle.dispose();
    await app.dispose(tester);
  });

  testWidgets('private screens hold at double text size on a 320 dp phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await start(tester);
    await setPin(tester, '2468');
    for (final path in [
      Routes.privateSpace,
      Routes.bowel,
      Routes.privateActivities,
      Routes.progressPhotos,
      Routes.privateReminders,
      Routes.privateReport,
    ]) {
      await go(tester, path);
      expect(tester.takeException(), isNull, reason: path);
    }
    await go(tester, Routes.privateSpace);
    await tapText(tester, 'Lock');
    await go(tester, Routes.privateSpace);
    expect(tester.takeException(), isNull, reason: 'lock screen');
    await app.dispose(tester);
  });

  testWidgets("the builder's Private switch stores the activity in the private space", (
    tester,
  ) async {
    await start(tester);
    await go(tester, Routes.newActivity);
    await tester.enterText(find.byType(EditableText).first, 'Journal');
    await tapText(tester, 'Private');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    // Without a PIN the private space asks for one first.
    expect(find.text('Set up the app lock first'), findsOneWidget);
    expect(await app.db.select(app.db.activityDefinitions).get(), isEmpty);
    final outbox = await app.db.select(app.db.syncOutbox).get();
    expect(outbox.where((r) => r.entityTable.contains('activit')), isEmpty);
    await app.dispose(tester);
  });
}
