import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/activities/domain/activity.dart';
import 'package:fitbuddy/features/activities/domain/activity_day.dart';
import 'package:flutter_test/flutter_test.dart';

int hm(int h, int m) => h * 60 + m;

final mon = LocalDate(2026, 11, 16);

Activity activity({
  TrackingType type = TrackingType.boolean,
  ScheduleRule? rule,
  int? targetMilli,
  List<ChecklistItem> checklist = const [],
  List<ScheduleChange>? history,
}) {
  final r = rule ?? Daily(times: [hm(7, 0)]);
  return Activity(
    id: 'a1',
    name: 'Walking',
    category: 'movement',
    iconKey: 'walk',
    trackingType: type,
    priority: ActivityPriority.essential,
    targetMilli: targetMilli,
    schedule: r,
    scheduleHistory: history ?? [ScheduleChange(from: mon.addDays(-30), rule: r)],
    checklistItems: checklist,
  );
}

ActivityLog log({
  ActivityLogStatus status = ActivityLogStatus.completed,
  LocalDate? date,
  int? slot,
  int? count,
  int? durationS,
  int? numericMilli,
  Set<String>? checked,
}) => ActivityLog(
  id: 'l${DateTime.now().microsecondsSinceEpoch}',
  activityId: 'a1',
  status: status,
  occurredAt: DateTime.utc(2026, 11, 16, 8),
  localDate: date ?? mon,
  scheduledSlot: slot,
  countValue: count,
  durationS: durationS,
  numericValueMilli: numericMilli,
  checklistDone: checked,
  source: LogSource.manual,
);

void main() {
  group('slot status', () {
    test('a day without a scheduled time is not scheduled, never missed', () {
      final a = activity(
        rule: Weekdays(weekdays: {1}, times: [hm(7, 0)]),
      );
      final day = ActivityDay.of(a, mon.addDays(1), const [], now: (date: mon.addDays(5), minute: 0));
      expect(day.scheduled, isFalse);
      expect(day.slots, isEmpty);
      expect(day.summary, DayState.notScheduled);
    });

    test('a passed time without a log is not logged; a later one is due', () {
      final a = activity(rule: Daily(times: [hm(7, 0), hm(21, 0)]));
      final day = ActivityDay.of(a, mon, const [], now: (date: mon, minute: hm(12, 0)));
      expect(day.slots.map((s) => s.state), [SlotState.missed, SlotState.due]);
    });

    test('a past day with nothing logged is not logged; a future day is due', () {
      final a = activity();
      expect(
        ActivityDay.of(a, mon, const [], now: (date: mon.addDays(1), minute: 0)).slots.single.state,
        SlotState.missed,
      );
      expect(
        ActivityDay.of(a, mon.addDays(1), const [], now: (date: mon, minute: 0)).slots.single.state,
        SlotState.due,
      );
    });

    test('logs answer their own slot first, then the earliest open slot', () {
      final a = activity(rule: Daily(times: [hm(7, 0), hm(13, 0), hm(19, 0)]));
      final day = ActivityDay.of(a, mon, [log(slot: hm(13, 0)), log()], now: (date: mon, minute: hm(20, 0)));
      expect(day.slots.map((s) => s.state), [SlotState.done, SlotState.done, SlotState.missed]);
      expect(day.doneCount, 2);
    });

    test('a skip is its own state', () {
      final day = ActivityDay.of(
        activity(),
        mon,
        [log(status: ActivityLogStatus.skipped)],
        now: (date: mon, minute: hm(9, 0)),
      );
      expect(day.slots.single.state, SlotState.skipped);
      expect(day.summary, DayState.skipped);
    });

    test('logging on an unscheduled day is kept as extra, not as a slot', () {
      final a = activity(
        rule: Weekdays(weekdays: {1}, times: [hm(7, 0)]),
      );
      final tue = mon.addDays(1);
      final day = ActivityDay.of(a, tue, [log(date: tue)], now: (date: tue, minute: hm(9, 0)));
      expect(day.slots, isEmpty);
      expect(day.extraLogs, hasLength(1));
      expect(day.summary, DayState.notScheduled);
    });
  });

  group('targets', () {
    test('counts add up across logs until the target is reached', () {
      final a = activity(type: TrackingType.count, targetMilli: 2000);
      var day = ActivityDay.of(a, mon, [log(count: 1)], now: (date: mon, minute: hm(6, 0)));
      expect(day.slots.single.state, SlotState.due);
      expect(day.slots.single.progressMilli, 1000);
      day = ActivityDay.of(a, mon, [log(count: 1), log(count: 1)], now: (date: mon, minute: hm(6, 0)));
      expect(day.slots.single.state, SlotState.done);
    });

    test('a duration below target is partial and reads as not logged once the time passes', () {
      final a = activity(type: TrackingType.duration, targetMilli: 1800 * 1000);
      final day = ActivityDay.of(a, mon, [log(durationS: 600)], now: (date: mon, minute: hm(23, 0)));
      expect(day.slots.single.state, SlotState.partial);
      expect(day.slots.single.progressMilli, 600000);
    });

    test('a checklist is done when every item is ticked', () {
      final items = [const ChecklistItem('c', 'Cleanser'), const ChecklistItem('m', 'Moisturiser')];
      final a = activity(type: TrackingType.checklist, checklist: items);
      expect(
        ActivityDay.of(
          a,
          mon,
          [
            log(checked: {'c'}),
          ],
          now: (date: mon, minute: 0),
        ).slots.single.state,
        SlotState.due,
      );
      expect(
        ActivityDay.of(
          a,
          mon,
          [
            log(checked: {'c', 'm'}),
          ],
          now: (date: mon, minute: 0),
        ).slots.single.state,
        SlotState.done,
      );
    });
  });

  group('schedule history', () {
    test('past days use the rule that was in force then', () {
      final weekdays = Weekdays(weekdays: {1, 2, 3, 4, 5}, times: [hm(7, 0)]);
      final weekends = Weekdays(weekdays: {6, 7}, times: [hm(9, 0)]);
      final a = activity(
        rule: weekends,
        history: [
          ScheduleChange(from: mon.addDays(-14), rule: weekdays),
          ScheduleChange(from: mon.addDays(3), rule: weekends),
        ],
      );
      expect(a.ruleOn(mon), weekdays);
      expect(a.ruleOn(mon.addDays(5)), weekends);
      expect(a.ruleOn(mon.addDays(-20)), isNull);
      // Monday was scheduled under the old rule.
      expect(ActivityDay.of(a, mon, const [], now: (date: mon.addDays(6), minute: 0)).scheduled, isTrue);
      // Saturday before the change: not scheduled.
      expect(ActivityDay.of(a, mon.addDays(-2), const [], now: (date: mon, minute: 0)).scheduled, isFalse);
    });

    test('rescheduling from a day keeps earlier rules and replaces same-day ones', () {
      final a = activity();
      final next = Daily(times: [hm(8, 0)]);
      final moved = a.rescheduled(next, from: mon);
      expect(moved.schedule, next);
      expect(moved.scheduleHistory.map((c) => c.from), [mon.addDays(-30), mon]);
      final again = moved.rescheduled(Daily(times: [hm(9, 0)]), from: mon);
      expect(again.scheduleHistory, hasLength(2));
      expect(again.ruleOn(mon), Daily(times: [hm(9, 0)]));
    });

    test('history survives a JSON round trip', () {
      final a = activity();
      final json = ScheduleChange.listToJson(a.scheduleHistory);
      expect(ScheduleChange.listFromJson(json), a.scheduleHistory);
    });
  });

  group('tracking type changes', () {
    test('any change is allowed with no history', () {
      expect(canChangeTrackingType(TrackingType.boolean, TrackingType.checklist, hasLogs: false), isTrue);
    });

    test('only changes that keep past logs meaningful are allowed with history', () {
      bool ok(TrackingType a, TrackingType b) => canChangeTrackingType(a, b, hasLogs: true);
      expect(ok(TrackingType.count, TrackingType.numeric), isTrue);
      expect(ok(TrackingType.duration, TrackingType.stopwatch), isTrue);
      expect(ok(TrackingType.stopwatch, TrackingType.duration), isTrue);
      expect(ok(TrackingType.boolean, TrackingType.eventLog), isTrue);
      expect(ok(TrackingType.eventLog, TrackingType.boolean), isTrue);
      expect(ok(TrackingType.numeric, TrackingType.count), isFalse);
      expect(ok(TrackingType.boolean, TrackingType.duration), isFalse);
      expect(ok(TrackingType.checklist, TrackingType.boolean), isFalse);
    });
  });

  group('validation', () {
    test('name, schedule, target and checklist are checked', () {
      expect(activity().problems, isEmpty);
      expect(activity().copyWith(name: '  ').problems, contains('name_required'));
      expect(activity(rule: Daily(times: const [])).problems, contains('times_empty'));
      expect(activity(type: TrackingType.count, targetMilli: 0).problems, contains('target_out_of_range'));
      expect(activity(type: TrackingType.checklist).problems, contains('checklist_empty'));
    });
  });
}
