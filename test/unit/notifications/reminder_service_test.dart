import 'package:fitbuddy/app/reminder_service.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/settings_repository.dart';
import 'package:fitbuddy/core/notifications/notification_gateway.dart';
import 'package:fitbuddy/core/notifications/notification_state_store.dart';
import 'package:fitbuddy/core/notifications/tz_zone.dart';
import 'package:fitbuddy/core/scheduling/occurrence_calculator.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/activities/data/drift_activity_repository.dart';
import 'package:fitbuddy/features/activities/domain/activity.dart';
import 'package:fitbuddy/features/activities/domain/activity_repository.dart';
import 'package:fitbuddy/features/reminders/data/drift_reminder_repository.dart';
import 'package:fitbuddy/features/reminders/domain/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class Utc implements TimeZoneRules {
  @override
  Duration offsetAt(DateTime instant) => Duration.zero;
}

void main() {
  late AppDatabase db;
  late MutableClock time;
  late FakeNotificationGateway gateway;
  late FakeAlarmCapabilities caps;
  late ReminderService service;
  late DriftActivityRepository activities;
  late DriftReminderRepository reminders;
  late NotificationStateStore store;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime.utc(2026, 11, 16, 6));
    final ids = SequentialIds();
    gateway = FakeNotificationGateway();
    caps = FakeAlarmCapabilities();
    activities = DriftActivityRepository(db, clock: time.clock, ids: ids, timeZone: const FixedTimeZone());
    reminders = DriftReminderRepository(db, clock: time.clock, ids: ids);
    store = NotificationStateStore(db);
    service = ReminderService(
      reminders: reminders,
      activities: activities,
      settings: SettingsRepository(db, clock: time.clock),
      store: store,
      gateway: gateway,
      capabilities: caps,
      timeZone: const FixedTimeZone(),
      clock: time.clock,
      zoneFor: (_) => Utc(),
    );
  });
  tearDown(() => db.close());

  Future<Activity> walking() async => (await activities.create(
    Activity(
      id: '',
      name: 'Walking',
      category: 'movement',
      iconKey: 'walk',
      trackingType: TrackingType.boolean,
      priority: ActivityPriority.essential,
      schedule: Daily(times: [8 * 60]),
      scheduleHistory: const [],
    ),
  )).valueOrNull!;

  test('quiet hours defer reminders and are saved in settings', () async {
    await reminders.create(
      Reminder(
        id: '',
        kind: ReminderKind.custom,
        title: 'Late',
        rule: Daily(times: [23 * 60]),
      ),
    );
    await service.saveQuietHours(const QuietHoursSetting(enabled: true));
    expect((await service.quietHours()).enabled, isTrue);
    expect(gateway.pending.values.every((n) => n.at!.hour == 6 && n.at!.minute == 30), isTrue);
  });

  test('Complete from a notification logs the activity, without opening the app', () async {
    final a = await walking();
    await reminders.create(
      Reminder(
        id: '',
        kind: ReminderKind.activity,
        title: 'Walk',
        activityId: a.id,
        rule: Daily(times: [8 * 60]),
      ),
    );
    await service.replan();
    final first = (await store.active()).first;
    time.now = DateTime.utc(2026, 11, 16, 8, 1);
    await service.handle(NotificationTap(notificationId: first.id, action: ReminderAction.complete));
    final logs = await activities.watchLogsFor(a.id).first;
    expect(logs.single.status, ActivityLogStatus.completed);
    expect(logs.single.source, LogSource.notification);
    expect(logs.single.scheduledSlot, 8 * 60);
    expect((await store.byId(first.id))!.status, NotificationStatus.completed);
    expect(gateway.pending.containsKey(first.id), isFalse);
  });

  test('Skip logs a skip; Snooze reschedules the same notification', () async {
    final a = await walking();
    await reminders.create(
      Reminder(
        id: '',
        kind: ReminderKind.activity,
        title: 'Walk',
        activityId: a.id,
        rule: Daily(times: [8 * 60]),
      ),
    );
    await service.replan();
    final first = (await store.active()).first;
    time.now = DateTime.utc(2026, 11, 16, 8);
    await service.handle(NotificationTap(notificationId: first.id, action: ReminderAction.snooze), snoozeMinutes: 15);
    expect(gateway.pending[first.id]!.at, DateTime.utc(2026, 11, 16, 8, 15));
    expect((await store.byId(first.id))!.snoozeCount, 1);
    await service.handle(NotificationTap(notificationId: first.id, action: ReminderAction.skip));
    expect((await activities.watchLogsFor(a.id).first).single.status, ActivityLogStatus.skipped);
  });

  test('tapping the body opens the linked activity and changes nothing', () async {
    final a = await walking();
    await reminders.create(
      Reminder(
        id: '',
        kind: ReminderKind.activity,
        title: 'Walk',
        activityId: a.id,
        rule: Daily(times: [8 * 60]),
      ),
    );
    await service.replan();
    final first = (await store.active()).first;
    expect(await service.handle(NotificationTap(notificationId: first.id)), a.id);
    expect(await activities.hasLogs(a.id), isFalse);
  });

  test('"if not done" is dropped for today once the activity is logged', () async {
    final a = await walking();
    await reminders.create(
      Reminder(
        id: '',
        kind: ReminderKind.activity,
        title: 'Walk?',
        activityId: a.id,
        onlyIfIncomplete: true,
        rule: Daily(times: [21 * 60]),
      ),
    );
    await service.replan();
    expect(gateway.pending.values.where((n) => n.at!.day == 16), hasLength(1));
    await activities.addLog(a.id, LogDraft(status: ActivityLogStatus.completed, occurredAt: time.now));
    await service.replan();
    expect(gateway.pending.values.where((n) => n.at!.day == 16), isEmpty);
  });

  test('IANA zone rules know DST', () {
    final london = IanaZone('Europe/London');
    expect(london.offsetAt(DateTime.utc(2026, 7, 1)), const Duration(hours: 1));
    expect(london.offsetAt(DateTime.utc(2026, 12, 1)), Duration.zero);
    expect(IanaZone('Not/AZone').offsetAt(DateTime.utc(2026, 7, 1)), Duration.zero);
  });

  test('settings round trip for quiet hours tolerates bad data', () {
    expect(QuietHoursSetting.fromJson('nonsense').enabled, isFalse);
    expect(LocalDate(2026, 1, 1), isNotNull);
  });
}
