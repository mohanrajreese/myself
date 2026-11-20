import 'package:fitbuddy/core/platform/location_tracker.dart';
import 'package:fitbuddy/features/onboarding/application/setup_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_harness.dart';
import 'onboarding_test.dart' show field;

void main() {
  late AppHarness app;
  setUp(() => app = AppHarness());

  Future<void> start(WidgetTester tester) async {
    await app.completeOnboarding(
      draft: const SetupDraft(name: 'Asha Rao', weightText: '91.8'),
    );
    await app.pump(tester, session: signedInSession);
  }

  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder, {bool last = false, bool settle = true}) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last,
      );
    }
    final f = last ? finder.last : finder.first;
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    if (settle) {
      await drain(tester);
      await tester.pumpAndSettle();
    }
  }

  Future<void> tapText(WidgetTester tester, String text) => tap(tester, find.text(text), last: true);

  Future<void> openFitness(WidgetTester tester) async {
    await tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('Fitness')));
  }

  testWidgets('steps: explains, asks, then shows the dashboard', (tester) async {
    app.stepCounter.permission = false;
    await start(tester);
    await openFitness(tester);
    expect(find.text('Tap to turn on step counting'), findsOneWidget);
    await tapText(tester, 'Steps today');
    expect(find.text('Count steps with your phone'), findsOneWidget);
    await tapText(tester, 'Continue');
    expect(app.stepCounter.snapshotsScheduled, greaterThan(0));
    expect(find.text('Continuous counting'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('steps: a refused permission keeps manual logging available', (tester) async {
    app.stepCounter.permission = false;
    app.stepCounter.grant = false;
    await start(tester);
    await openFitness(tester);
    await tapText(tester, 'Steps today');
    await tapText(tester, 'Continue');
    expect(
      find.text('Physical activity access was refused. You can still log walks and runs by hand.'),
      findsOneWidget,
    );
    await app.dispose(tester);
  });

  testWidgets('steps: a phone without a sensor says so', (tester) async {
    app.stepCounter.sensor = false;
    await start(tester);
    await openFitness(tester);
    expect(find.text('No step sensor on this phone'), findsOneWidget);
    await tapText(tester, 'Steps today');
    expect(find.text('This phone has no step counter'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('steps: buffered readings become today\'s total; an adjustment is labelled', (tester) async {
    final now = DateTime(2026, 11, 16, 9).toUtc();
    app.stepCounter.buffer.addAll([
      (
        id: 1,
        cumulativeSteps: 1000,
        bootCount: 1,
        elapsedRealtimeMs: 1000,
        wallTimeUtc: now.subtract(const Duration(hours: 2)),
        tz: 'UTC',
        utcOffsetS: DateTime(2026, 11, 16).timeZoneOffset.inSeconds,
        source: 'worker',
      ),
      (
        id: 2,
        cumulativeSteps: 4430,
        bootCount: 1,
        elapsedRealtimeMs: 7201000,
        wallTimeUtc: now,
        tz: 'UTC',
        utcOffsetS: DateTime(2026, 11, 16).timeZoneOffset.inSeconds,
        source: 'worker',
      ),
    ]);
    await start(tester);
    await drain(tester);
    await openFitness(tester);
    await tapText(tester, 'Steps today');
    expect(find.text('3,430'), findsWidgets);
    expect(app.stepCounter.buffer, isEmpty, reason: 'acknowledged after ingest');
    await tapText(tester, 'Adjust today');
    await tester.enterText(field('Steps'), '1200');
    await tester.pump();
    await tapText(tester, 'Save adjustment');
    await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('Adjusted by you: +1,200'), findsOneWidget);
    expect(find.text('4,630'), findsWidgets);
    final log = (await app.db.select(app.db.stepLogs).get()).single;
    expect(log.steps, 4630);
    expect(log.source, 'phone_sensor_adjusted');
    await app.dispose(tester);
  });

  testWidgets('a run is logged by hand with its pace, and never asks for location', (tester) async {
    await start(tester);
    await openFitness(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Run'));
    await tester.enterText(field('Distance'), '5.2');
    await tester.pump();
    expect(find.text('5:46 /km'), findsOneWidget); // 5.2 km in the default 30 min
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Workout saved'), findsOneWidget);
    final s = (await app.db.select(app.db.workoutSessions).get()).single;
    expect(s.kind, 'run');
    expect(s.distanceM, 5200);
    expect(s.entryMode, 'manual');
    expect(app.location.current, LocationAccess.granted, reason: 'untouched');
    await app.dispose(tester);
  });

  testWidgets('GPS asks for location after explaining; refusal keeps manual entry', (tester) async {
    app.location.current = LocationAccess.denied;
    app.location.onRequest = LocationAccess.denied;
    await start(tester);
    await openFitness(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Walk'));
    await tapText(tester, 'Start');
    expect(find.text('Use your location for this workout?'), findsOneWidget);
    await tapText(tester, 'Continue');
    expect(find.text('Location access was refused. You can still log by hand.'), findsOneWidget);
    expect(find.text('Log a Walk'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('GPS tracking records distance from fixes and saves the route locally', (tester) async {
    await start(tester);
    await openFitness(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Ride'));
    await tap(tester, find.text('Start'), last: true, settle: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final t0 = app.time.now.toUtc();
    for (var i = 0; i < 3; i++) {
      app.location.fixes.add((latE7: 129700000 + i * 10000, lonE7: 775900000, accuracyDm: 50, at: t0));
      await tester.pump(const Duration(milliseconds: 100));
    }
    app.time.now = app.time.now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Finish'));
    await drain(tester);
    final s = (await app.db.select(app.db.workoutSessions).get()).single;
    expect(s.kind, 'cycle');
    expect(s.entryMode, 'gps');
    expect(s.distanceM, closeTo(222, 3));
    expect(await app.db.select(app.db.localWorkoutRoutePoints).get(), hasLength(3));
    await app.dispose(tester);
  });

  testWidgets('a gym workout: add an exercise, fill and complete sets, finish, save as template', (tester) async {
    await start(tester);
    await drain(tester);
    await openFitness(tester);
    await tap(tester, find.widgetWithText(FilledButton, 'Gym workout'), settle: false);
    await drain(tester);
    await tester.pump();
    await tap(tester, find.text('Add exercise'), last: true, settle: false);
    await drain(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField).last, 'bench');
    await tester.pump();
    await tester.tap(find.text('Bench press').last);
    await drain(tester);
    await tester.pump(const Duration(seconds: 1));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '40');
    await tester.enterText(fields.at(1), '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await drain(tester);
    await tester.tap(find.bySemanticsLabel('Set 1 done'));
    await drain(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Rest'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await drain(tester);
    await tester.pump(const Duration(seconds: 1));
    final sets = await app.db.select(app.db.exerciseSets).get();
    expect(sets.single.loadG, 40000);
    expect(sets.single.reps, 12);
    expect(sets.single.completedAt, isNotNull);
    final session = (await app.db.select(app.db.workoutSessions).get()).single;
    expect(session.endedAt, isNotNull);
    await app.dispose(tester);
  });

  testWidgets('a custom exercise is created in the library and marked as yours', (tester) async {
    await start(tester);
    await drain(tester);
    await openFitness(tester);
    await tapText(tester, 'Exercise library');
    await tap(tester, find.widgetWithText(FilledButton, 'New'));
    await tester.enterText(field('Name'), 'Cable fly');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Cable fly (yours)'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('history lists workouts; records appear after a run', (tester) async {
    await start(tester);
    await openFitness(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Run'));
    await tester.enterText(field('Distance'), '5');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await tapText(tester, 'History');
    expect(find.text('Run'), findsWidgets);
    await tester.pageBack();
    await drain(tester);
    await tester.pumpAndSettle();
    await tapText(tester, 'Personal records');
    expect(find.text('Fastest pace'), findsOneWidget);
    expect(find.textContaining('6:00 /km'), findsOneWidget);
    await app.dispose(tester);
  });
}
