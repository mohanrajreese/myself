import 'package:fitbuddy/core/scheduling/reminder_planner.dart';
import 'package:fitbuddy/core/scheduling/occurrence_calculator.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

class Utc implements TimeZoneRules {
  const Utc();
  @override
  Duration offsetAt(DateTime instant) => Duration.zero;
}

int hm(int h, int m) => h * 60 + m;

void main() {
  const planner = ReminderPlanner();
  final now = DateTime.utc(2026, 11, 16, 6); // Monday 06:00
  const quiet = QuietHours(start: 22 * 60 + 30, end: 6 * 60 + 30);

  PlannerReminder r(
    String id,
    ScheduleRule rule, {
    QuietBehaviour quietBehaviour = QuietBehaviour.defer,
    bool alarm = false,
    String? activityId,
    bool onlyIfIncomplete = false,
    LocalDate? start,
    LocalDate? end,
  }) => PlannerReminder(
    id: id,
    rule: rule,
    quietBehaviour: quietBehaviour,
    alarm: alarm,
    activityId: activityId,
    onlyIfIncomplete: onlyIfIncomplete,
    startDate: start,
    endDate: end,
  );

  List<String> plan(
    List<PlannerReminder> reminders, {
    QuietHours? quietHours,
    Set<(String, LocalDate)> done = const {},
    int budget = 400,
    int days = 2,
  }) => [
    for (final o in planner.plan(
      reminders,
      now: now,
      days: days,
      zone: const Utc(),
      quietHours: quietHours,
      done: done,
      budget: budget,
    ))
      '${o.reminderId} ${o.fireAt.toIso8601String().substring(5, 16)}${o.deferred ? ' deferred' : ''}${o.exact ? ' exact' : ''}',
  ];

  test('plans each occurrence in the window, in time order, from now', () {
    expect(
      plan([
        r('a', Daily(times: [hm(5, 0), hm(7, 0)])),
      ]),
      ['a 11-16T07:00', 'a 11-17T05:00', 'a 11-17T07:00', 'a 11-18T05:00'],
    );
  });

  test('quiet hours defer ordinary reminders to the end of the quiet period', () {
    expect(
      plan(
        [
          r('a', Daily(times: [hm(23, 0)])),
        ],
        quietHours: quiet,
        days: 1,
      ),
      ['a 11-16T06:30 deferred'], // Sunday's 23:00, still waiting at 06:00 Monday
    );
  });

  test('quiet hours can drop a reminder instead', () {
    expect(
      plan(
        [
          r('a', Daily(times: [hm(23, 0), hm(8, 0)]), quietBehaviour: QuietBehaviour.suppress),
        ],
        quietHours: quiet,
        days: 1,
      ),
      ['a 11-16T08:00'],
    );
  });

  test('important alarms ring through quiet hours and are exact', () {
    expect(
      plan(
        [
          r('a', Daily(times: [hm(23, 0)]), alarm: true, quietBehaviour: QuietBehaviour.bypass),
        ],
        quietHours: quiet,
        days: 1,
      ),
      ['a 11-16T23:00 exact'],
    );
  });

  test('several deferred occurrences collapse into one', () {
    final rule = Interval(everyMinutes: 30, start: hm(22, 0), end: hm(23, 30));
    expect(plan([r('w', rule)], quietHours: quiet), [
      'w 11-16T06:30 deferred',
      'w 11-16T22:00',
      'w 11-17T06:30 deferred',
      'w 11-17T22:00',
    ]);
  });

  test('an "if not done" reminder is left out on days the activity is done', () {
    final rem = r('s', Daily(times: [hm(21, 45)]), activityId: 'skin', onlyIfIncomplete: true);
    expect(plan([rem], done: {('skin', LocalDate(2026, 11, 16))}), ['s 11-17T21:45']);
  });

  test('start and end dates limit the plan', () {
    final rem = r(
      'x',
      Daily(times: [hm(9, 0)]),
      start: LocalDate(2026, 11, 17),
      end: LocalDate(2026, 11, 17),
    );
    expect(plan([rem], days: 5), ['x 11-17T09:00']);
  });

  test('over budget, interval reminders shrink first but keep 48 hours', () {
    final water = r('w', Interval(everyMinutes: 60, start: hm(8, 0), end: hm(20, 0)));
    final walk = r('k', Daily(times: [hm(8, 0)]));
    final planned = planner.plan([water, walk], now: now, days: 7, zone: const Utc(), budget: 40);
    final waterTimes = planned.where((o) => o.reminderId == 'w').map((o) => o.fireAt);
    expect(
      planned.where((o) => o.reminderId == 'k'),
      hasLength(7),
      reason: 'daily reminders keep their week',
    );
    expect(waterTimes.every((t) => t.isBefore(now.add(const Duration(hours: 48)))), isTrue);
    expect(waterTimes, hasLength(26), reason: '13 a day for the first 48 hours');
    expect(planned.length, lessThanOrEqualTo(40));
  });

  test('if still over budget, the latest occurrences are dropped', () {
    final planned = planner.plan(
      [
        r('a', Daily(times: [hm(7, 0), hm(9, 0)])),
      ],
      now: now,
      days: 7,
      zone: const Utc(),
      budget: 5,
    );
    expect(planned, hasLength(5));
    expect(planned.last.fireAt, DateTime.utc(2026, 11, 18, 7));
  });

  test('every occurrence has a stable key', () {
    final a = planner.plan(
      [
        r('a', Daily(times: [hm(7, 0)])),
      ],
      now: now,
      days: 1,
      zone: const Utc(),
    );
    final b = planner.plan(
      [
        r('a', Daily(times: [hm(7, 0)])),
      ],
      now: now,
      days: 1,
      zone: const Utc(),
    );
    expect(a.single.key, b.single.key);
    expect(a.single.key, 'a@2026-11-16T07:00');
  });
}
