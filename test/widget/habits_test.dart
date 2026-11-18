import 'package:fitbuddy/core/notifications/notification_state_store.dart';
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

  Future<void> tap(WidgetTester tester, Finder finder, {bool last = false}) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last,
      );
    }
    final f = last ? finder.last : finder.first;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) =>
      tap(tester, find.text(text), last: true);

  /// Lets background re-planning finish (it runs without scheduling frames).
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openHabits(WidgetTester tester) =>
      tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('Habits')));

  /// Habits → + Activity → fill in → Save. Lands on the activity's detail.
  Future<void> createActivity(
    WidgetTester tester, {
    required String name,
    String type = 'Yes/no',
    String? target,
    bool remind = false,
    List<String> unselectDays = const [],
    bool selectedDays = false,
  }) async {
    await openHabits(tester);
    await tap(tester, find.widgetWithText(FilledButton, 'Activity'));
    expect(find.text('New activity'), findsOneWidget);
    await tester.enterText(field('Name'), name);
    await tapText(tester, type);
    if (target != null) await tester.enterText(field('Target'), target);
    if (selectedDays) {
      await tapText(tester, 'Selected days');
      for (final d in unselectDays) {
        await tapText(tester, d);
      }
    }
    if (remind) await tapText(tester, 'Remind me at these times');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await drain(tester);
  }

  Future<void> backToHabits(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  testWidgets('an empty Habits tab offers to create an activity', (tester) async {
    await start(tester);
    await openHabits(tester);
    expect(
      find.text('No activities yet. Create one for each routine you want to track.'),
      findsOneWidget,
    );
    await tapText(tester, 'Create an activity');
    expect(find.text('New activity'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a count activity is created, then +1 twice reaches its target', (tester) async {
    await start(tester);
    await createActivity(tester, name: 'Water before breakfast', type: 'Count', target: '2');
    expect(find.text('Activity saved'), findsOneWidget);
    expect(await app.db.select(app.db.activityDefinitions).get(), hasLength(1));
    await backToHabits(tester);
    expect(find.text('Water before breakfast'), findsOneWidget);
    expect(find.text('0 of 2'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Add one to Water before breakfast'));
    expect(find.text('1 of 2'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Add one to Water before breakfast'));
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Done'), findsWidgets);
    expect(find.text('1 of 1 done'), findsOneWidget);
    expect(await app.db.select(app.db.activityLogs).get(), hasLength(2));
    await app.dispose(tester);
  });

  testWidgets('a passed time reads "Not logged", never as a failure, and Done logs it', (
    tester,
  ) async {
    await start(tester);
    await createActivity(tester, name: 'Morning brushing');
    await backToHabits(tester);
    expect(find.textContaining('Not logged at'), findsOneWidget);
    await tapText(tester, 'Done');
    expect(find.text('Morning brushing logged'), findsOneWidget);
    expect(find.text('1 of 1 done'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a day the activity is not scheduled is shown as not scheduled, not missed', (
    tester,
  ) async {
    await start(tester);
    // 16 Nov 2026 is a Monday: keep only the other weekdays.
    await createActivity(tester, name: 'Gym', selectedDays: true, unselectDays: ['M']);
    await backToHabits(tester);
    expect(find.text('Not scheduled today'), findsOneWidget);
    expect(find.textContaining('Not logged'), findsNothing);
    await tapText(tester, 'Log anyway');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Logged once today'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('Home lists essential activities with Done, Snooze and open', (tester) async {
    await start(tester);
    await createActivity(tester, name: 'Vitamin D');
    await backToHabits(tester);
    await tap(tester, find.descendant(of: find.byType(NavigationBar), matching: find.text('Home')));
    await tester.scrollUntilVisible(find.text('Vitamin D'), 200);
    expect(find.text('Vitamin D'), findsOneWidget);
    await tap(tester, find.byTooltip('Snooze'));
    await tapText(tester, '10 min');
    await drain(tester);
    expect(find.text('Reminder in 10 min'), findsOneWidget);
    expect(app.notifications.pending, hasLength(1));
    await tapText(tester, 'Done');
    expect(await app.db.select(app.db.activityLogs).get(), hasLength(1));
    await tap(tester, find.text('Vitamin D'));
    expect(find.text('Last 4 weeks'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('archive, restore and delete from the activity list', (tester) async {
    await start(tester);
    await createActivity(tester, name: 'Skincare');
    await backToHabits(tester);
    await tapText(tester, 'Activities');
    await tap(tester, find.byTooltip('More actions for Skincare'));
    await tapText(tester, 'Archive');
    expect(find.text('Archived (1)'), findsOneWidget);
    await tapText(tester, 'Archived (1)');
    await tap(tester, find.byTooltip('More actions for Skincare'));
    await tapText(tester, 'Restore');
    await tapText(tester, 'Active (1)');
    await tap(tester, find.byTooltip('More actions for Skincare'));
    await tapText(tester, 'Delete');
    expect(find.text('Delete this activity?'), findsOneWidget);
    await tapText(tester, 'Delete');
    expect(find.text('Active (0)'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('turning on reminders for an activity schedules a week of notifications', (
    tester,
  ) async {
    await start(tester);
    await createActivity(tester, name: 'Walking', remind: true);
    await tester.pumpAndSettle();
    expect(await app.db.select(app.db.reminders).get(), hasLength(1));
    expect(
      app.notifications.pending,
      hasLength(7),
      reason: '08:00 today has passed; Tuesday to next Monday remain',
    );
    final states = await app.db.select(app.db.localNotificationState).get();
    expect(states.every((s) => s.status == NotificationStatus.scheduled.code), isTrue);
    await app.dispose(tester);
  });

  testWidgets('a water reminder is created from its preset and can be switched off', (
    tester,
  ) async {
    await start(tester);
    await openHabits(tester);
    await tapText(tester, 'Reminders');
    expect(
      find.text('No reminders yet. Add one, or turn on "Remind me" in an activity.'),
      findsOneWidget,
    );
    await tap(tester, find.widgetWithText(FilledButton, 'Reminder'));
    await tapText(tester, 'Water');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Reminder saved'), findsOneWidget);
    expect(find.text('Drink water'), findsOneWidget);
    await drain(tester);
    expect(app.notifications.pending, isNotEmpty);
    await tap(tester, find.byType(Switch).last);
    await drain(tester);
    expect(app.notifications.pending, isEmpty);
    await app.dispose(tester);
  });

  testWidgets('with notifications off, saving a reminder explains and then asks', (tester) async {
    await start(tester);
    app.notifications.allowed = false;
    app.notifications.grantOnRequest = false;
    await openHabits(tester);
    await tapText(tester, 'Reminders');
    await tap(tester, find.widgetWithText(FilledButton, 'Reminder'));
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Allow notifications?'), findsOneWidget);
    await tapText(tester, 'Allow');
    expect(app.notifications.requests, 1);
    expect(app.alarms.opened, contains('notifications'), reason: 'denied: the settings page opens');
    expect(find.text('Notifications are off, so reminders cannot appear.'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('notification settings show status, open exact-alarm access and save quiet hours', (
    tester,
  ) async {
    await start(tester);
    app.alarms.exact = false;
    await tap(tester, find.byTooltip('Profile and settings'));
    await tapText(tester, 'Notifications and reminders');
    expect(find.text('Without it, reminders can be a few minutes late.'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, 'Allow').first);
    expect(find.text('Allow exact alarms?'), findsOneWidget);
    await tapText(tester, 'Open settings');
    expect(app.alarms.opened, contains('exact'));
    await tester.scrollUntilVisible(find.text('Quiet hours').last, 200);
    await tap(tester, find.byType(Switch).first);
    await drain(tester);
    expect(find.text('10:30 PM'), findsOneWidget);
    await tap(tester, find.bySemanticsLabel('Test the Hydration sound'));
    expect(app.alarms.opened, contains('sound:hydration_v1'));
    await app.dispose(tester);
  });

  testWidgets('the stopwatch logs its time when finished, and nothing when cancelled', (
    tester,
  ) async {
    await start(tester);
    await openHabits(tester);
    await tap(tester, find.widgetWithText(FilledButton, 'Activity'));
    await tester.enterText(field('Name'), 'Walking');
    await tapText(tester, 'Duration');
    await tapText(tester, 'Offer a stopwatch');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    // A running stopwatch redraws every second, so frames are pumped by hand.
    Future<void> press(String text) async {
      await tester.tap(find.text(text).last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tapText(tester, 'Start stopwatch');
    await press('Start');
    await drain(tester);
    app.time.now = app.time.now.add(const Duration(minutes: 12));
    await tester.pump(const Duration(seconds: 1));
    await press('Pause');
    await drain(tester);
    expect(find.text('paused'), findsOneWidget);
    await press('Resume');
    await drain(tester);
    await tester.tap(find.textContaining('Finish now and log'));
    await drain(tester);
    final logs = await app.db.select(app.db.activityLogs).get();
    expect(logs.single.durationS, 720);
    expect(logs.single.source, 'timer');

    await press('Start stopwatch');
    await press('Start');
    await drain(tester);
    await press('Cancel');
    await press('Cancel');
    await drain(tester);
    expect(await app.db.select(app.db.activityLogs).get(), hasLength(1));
    await app.dispose(tester);
  });

  testWidgets('a checklist needs at least one tick or a skip', (tester) async {
    await start(tester);
    await openHabits(tester);
    await tap(tester, find.widgetWithText(FilledButton, 'Activity'));
    await tester.enterText(field('Name'), 'Evening skincare');
    await tapText(tester, 'Checklist');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.text('Add at least one checklist step.'), findsOneWidget);
    await tapText(tester, 'Add a step');
    await tester.enterText(field('Step 1'), 'Cleanser');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await tapText(tester, 'Log');
    await tap(tester, find.widgetWithText(FilledButton, 'Save · 0 of 1'));
    expect(find.text('Tick at least one step, or choose Skip.'), findsOneWidget);
    await tapText(tester, 'Skip');
    expect(find.text('Skip saved'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('changing to a tracking type that breaks the history is refused', (tester) async {
    await start(tester);
    await createActivity(tester, name: 'Reading');
    await tapText(tester, 'Log');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.text('Edit'));
    await drain(tester);
    await tester.pumpAndSettle();
    await tapText(tester, 'Checklist');
    await tapText(tester, 'Add a step');
    await tester.enterText(field('Step 1'), 'Chapter');
    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('Your history does not fit that tracking type'), findsOneWidget);
    await app.dispose(tester);
  });

  testWidgets('a reminder can use a phone sound or a sound file, each on its own channel', (
    tester,
  ) async {
    await start(tester);
    await openHabits(tester);
    await tapText(tester, 'Reminders');
    await tap(tester, find.widgetWithText(FilledButton, 'Reminder'));
    await tapText(tester, 'Default · tap to choose');
    await drain(tester);
    await tapText(tester, 'Chime');
    expect(app.sounds.played, ['content://media/internal/audio/media/11']);
    await tapText(tester, 'Done');
    expect(find.text('Chime · tap to choose'), findsOneWidget);

    await tapText(tester, 'Chime · tap to choose');
    await drain(tester);
    await tapText(tester, 'Choose a sound file');
    await drain(tester);
    expect(find.text('my tone'), findsOneWidget);
    await tapText(tester, 'Done');

    await tap(tester, find.widgetWithText(FilledButton, 'Save'));
    await drain(tester);
    final stored = (await app.db.select(app.db.reminders).get()).single;
    expect(stored.soundKey, 'content://com.mysticstack.fitbuddy.sounds/sounds/my_tone.mp3');
    final sent = app.notifications.pending.values.first;
    expect(sent.soundUri, stored.soundKey);
    expect(sent.channelId, startsWith('routines_s'));
    await app.dispose(tester);
  });
}
