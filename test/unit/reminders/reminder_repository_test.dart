import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/core/scheduling/reminder_planner.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/reminders/data/drift_reminder_repository.dart';
import 'package:fitbuddy/features/reminders/domain/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late DriftReminderRepository repo;
  final today = LocalDate(2026, 11, 16);

  setUp(() {
    db = memoryDatabase();
    repo = DriftReminderRepository(db, clock: MutableClock(DateTime(2026, 11, 16, 9)).clock, ids: SequentialIds());
  });
  tearDown(() => db.close());

  test('presets start from sensible schedules on the right channel', () {
    final water = reminderPreset(ReminderKind.water, title: 'Drink water', today: today);
    expect(water.rule, isA<IntervalRule>());
    expect(water.channel, NotificationChannelKey.hydration);
    expect(reminderPreset(ReminderKind.sleep, title: 'Bedtime', today: today).channel, NotificationChannelKey.sleep);
    expect(
      reminderPreset(ReminderKind.workout, title: 'Gym', today: today).copyWith(alarm: true).channel,
      NotificationChannelKey.alarms,
    );
  });

  test('a reminder is saved, listed, edited, switched off and deleted, each queued for sync', () async {
    final r = (await repo.create(reminderPreset(ReminderKind.water, title: 'Drink water', today: today))).valueOrNull!;
    expect((await repo.watchAll().first).single.title, 'Drink water');
    await repo.update(r.copyWith(title: 'Water', quietBehaviour: QuietBehaviour.suppress, snoozeMinutes: 15));
    final edited = (await repo.byId(r.id))!;
    expect(edited.quietBehaviour, QuietBehaviour.suppress);
    expect(edited.snoozeMinutes, 15);
    expect(edited.rule, r.rule);
    await repo.setEnabled(r.id, enabled: false);
    expect(await repo.enabled(), isEmpty);
    await repo.delete(r.id);
    expect(await repo.watchAll().first, isEmpty);
    final outbox = await db.select(db.syncOutbox).get();
    expect(outbox.single.entityTable, 'reminders');
  });

  test('invalid reminders are refused', () async {
    final noTitle = await repo.create(reminderPreset(ReminderKind.custom, title: ' ', today: today));
    expect(noTitle.failureOrNull, isA<ValidationFailure>());
    final ifNotDone = reminderPreset(ReminderKind.custom, title: 'x', today: today).copyWith(onlyIfIncomplete: true);
    expect((await repo.create(ifNotDone)).failureOrNull, isA<ValidationFailure>());
    expect(await db.select(db.reminders).get(), isEmpty);
  });
}
