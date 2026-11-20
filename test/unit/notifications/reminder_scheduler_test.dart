import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/notifications/notification_state_store.dart';
import 'package:fitbuddy/core/notifications/reminder_scheduler.dart';
import 'package:fitbuddy/core/scheduling/occurrence_calculator.dart';
import 'package:fitbuddy/core/scheduling/reminder_planner.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class Zone implements TimeZoneRules {
  Zone(this.hours);
  int hours;
  @override
  Duration offsetAt(DateTime instant) => Duration(hours: hours);
}

int hm(int h, int m) => h * 60 + m;

void main() {
  late AppDatabase db;
  late MutableClock time;
  late FakeNotificationGateway gateway;
  late NotificationStateStore store;
  late ReminderScheduler scheduler;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime.utc(2026, 11, 16, 6));
    gateway = FakeNotificationGateway();
    store = NotificationStateStore(db);
    scheduler = ReminderScheduler(store: store, gateway: gateway, clock: time.clock);
  });
  tearDown(() => db.close());

  SchedulableReminder reminder(
    String id,
    ScheduleRule rule, {
    bool alarm = false,
    String? activityId,
    bool ifIncomplete = false,
  }) => SchedulableReminder(
    plan: PlannerReminder(id: id, rule: rule, alarm: alarm, activityId: activityId, onlyIfIncomplete: ifIncomplete),
    channelId: 'routines_v1',
    title: 'Walk',
  );

  test('schedules the week once; running again changes nothing', () async {
    final rs = [
      reminder('a', Daily(times: [hm(8, 0)])),
    ];
    final first = await scheduler.run(rs, zone: Zone(0));
    expect(first.scheduled, 7);
    expect(gateway.pending, hasLength(7));
    final ids = gateway.pending.keys.toSet();
    final second = await scheduler.run(rs, zone: Zone(0));
    expect(second, (scheduled: 0, cancelled: 0, moved: 0, expired: 0));
    expect(gateway.pending.keys.toSet(), ids, reason: 'ids are stable');
  });

  test('removing or disabling a reminder cancels its notifications', () async {
    await scheduler.run([
      reminder('a', Daily(times: [hm(8, 0)])),
    ], zone: Zone(0));
    final r = await scheduler.run(const [], zone: Zone(0));
    expect(r.cancelled, 7);
    expect(gateway.pending, isEmpty);
  });

  test('a timezone change moves notifications to the same wall-clock time, without duplicates', () async {
    final rs = [
      reminder('a', Daily(times: [hm(8, 0)])),
    ];
    final zone = Zone(0);
    await scheduler.run(rs, zone: zone);
    zone.hours = 5;
    final r = await scheduler.run(rs, zone: zone);
    // 08:00 today has already passed in the new zone; next Monday enters the window.
    expect((r.cancelled, r.scheduled, r.moved), (1, 1, 6));
    expect(gateway.pending, hasLength(7));
    expect(gateway.pending.values.map((n) => n.at!.hour).toSet(), {3});
  });

  test('without exact-alarm access, alarms are scheduled inexactly', () async {
    await scheduler.run(
      [
        reminder('a', Daily(times: [hm(8, 0)]), alarm: true),
      ],
      zone: Zone(0),
      exactAllowed: false,
    );
    expect(gateway.pending.values.every((n) => !n.exact), isTrue);
    await scheduler.run([
      reminder('a', Daily(times: [hm(8, 0)]), alarm: true),
    ], zone: Zone(0));
    expect(gateway.pending.values.every((n) => n.exact), isTrue, reason: 'granted later: moved to exact');
  });

  test('completing the activity cancels today\'s "if not done" reminder', () async {
    final rs = [
      reminder('s', Daily(times: [hm(21, 45)]), activityId: 'skin', ifIncomplete: true),
    ];
    await scheduler.run(rs, zone: Zone(0), days: 1);
    expect(gateway.pending, hasLength(1));
    await scheduler.run(rs, zone: Zone(0), days: 1, done: {('skin', LocalDate(2026, 11, 16))});
    expect(gateway.pending, isEmpty);
  });

  test('a notification acted on is not scheduled again; a passed one expires', () async {
    final rs = [
      reminder('a', Daily(times: [hm(8, 0)])),
    ];
    await scheduler.run(rs, zone: Zone(0), days: 1);
    final first = (await store.active()).single;
    await store.setStatus(first.id, NotificationStatus.completed, actedAt: time.now);
    gateway.pending.clear();
    await scheduler.run(rs, zone: Zone(0), days: 1);
    expect(gateway.pending, isEmpty);

    final db2 = memoryDatabase();
    addTearDown(db2.close);
    final s2 = ReminderScheduler(store: NotificationStateStore(db2), gateway: gateway, clock: time.clock);
    await s2.run(rs, zone: Zone(0), days: 1);
    time.now = DateTime.utc(2026, 11, 16, 9);
    final r = await s2.run(rs, zone: Zone(0), days: 1);
    expect(r.expired, 1);
  });

  test('a snoozed notification survives a re-plan', () async {
    final rs = [
      reminder('a', Daily(times: [hm(8, 0)])),
    ];
    await scheduler.run(rs, zone: Zone(0), days: 1);
    final rec = (await store.active()).single;
    await store.snooze(rec.id, DateTime.utc(2026, 11, 16, 8, 10));
    final r = await scheduler.run(rs, zone: Zone(0), days: 1);
    expect(r.scheduled, 0);
    expect((await store.byId(rec.id))!.status, NotificationStatus.snoozed);
  });
}
