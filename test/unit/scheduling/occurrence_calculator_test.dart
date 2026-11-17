import 'package:fitbuddy/core/scheduling/occurrence_calculator.dart';
import 'package:fitbuddy/core/scheduling/schedule_rule.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

/// A zone at UTC+1 that moves to UTC+2 at 01:00 UTC on the last Sunday of
/// March and back at 01:00 UTC on the last Sunday of October (EU rules).
class EuZone implements TimeZoneRules {
  const EuZone();

  static DateTime _lastSunday(int year, int month) {
    var d = DateTime.utc(year, month + 1, 0);
    while (d.weekday != DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d.add(const Duration(hours: 1));
  }

  @override
  Duration offsetAt(DateTime instant) {
    final y = instant.toUtc().year;
    final summer = !instant.isBefore(_lastSunday(y, 3)) && instant.isBefore(_lastSunday(y, 10));
    return Duration(hours: summer ? 2 : 1);
  }
}

class FixedZone implements TimeZoneRules {
  const FixedZone(this.offset);
  final Duration offset;
  @override
  Duration offsetAt(DateTime instant) => offset;
}

int hm(int h, int m) => h * 60 + m;

void main() {
  const calc = OccurrenceCalculator();
  final mon = LocalDate(2026, 11, 16); // a Monday

  List<String> at(ScheduleRule rule, LocalDate from, LocalDate to) => [
    for (final o in calc.between(rule, from, to)) o.toString(),
  ];

  group('rules on the local calendar', () {
    test('one-time fires once on its date only', () {
      final rule = OneTime(date: mon.addDays(2), time: hm(9, 0));
      expect(at(rule, mon, mon.addDays(6)), ['2026-11-18 09:00']);
      expect(at(rule, mon, mon.addDays(1)), isEmpty);
    });

    test('daily with several times, sorted and without duplicates', () {
      final rule = Daily(times: [hm(21, 30), hm(7, 0), hm(7, 0)]);
      expect(at(rule, mon, mon.addDays(1)), [
        '2026-11-16 07:00',
        '2026-11-16 21:30',
        '2026-11-17 07:00',
        '2026-11-17 21:30',
      ]);
    });

    test('selected weekdays', () {
      final rule = Weekdays(weekdays: {1, 3, 5}, times: [hm(18, 30)]);
      expect(at(rule, mon, mon.addDays(6)), [
        '2026-11-16 18:30',
        '2026-11-18 18:30',
        '2026-11-20 18:30',
      ]);
      expect(calc.isScheduledOn(rule, mon.addDays(1)), isFalse);
      expect(calc.isScheduledOn(rule, mon.addDays(2)), isTrue);
    });

    test('weekly every two weeks counts from the anchor week', () {
      final rule = Weekly(
        everyWeeks: 2,
        anchor: LocalDate(2026, 11, 18), // a Wednesday in the week of 16 Nov
        weekdays: {6},
        times: [hm(10, 0)],
      );
      expect(at(rule, mon, mon.addDays(27)), ['2026-11-21 10:00', '2026-12-05 10:00']);
    });

    test('monthly on a day of the month uses the last day in shorter months', () {
      final rule = Monthly.dayOfMonth(31, times: [hm(9, 0)]);
      expect(at(rule, LocalDate(2027, 1, 1), LocalDate(2027, 4, 30)), [
        '2027-01-31 09:00',
        '2027-02-28 09:00',
        '2027-03-31 09:00',
        '2027-04-30 09:00',
      ]);
    });

    test('monthly on the nth or last weekday', () {
      final second = Monthly.nthWeekday(2, DateTime.tuesday, times: [hm(8, 0)]);
      expect(at(second, LocalDate(2026, 11, 1), LocalDate(2026, 12, 31)), [
        '2026-11-10 08:00',
        '2026-12-08 08:00',
      ]);
      final last = Monthly.nthWeekday(-1, DateTime.friday, times: [hm(8, 0)]);
      expect(at(last, LocalDate(2026, 11, 1), LocalDate(2026, 11, 30)), ['2026-11-27 08:00']);
    });

    test('every N days from an anchor, including dates before the anchor', () {
      final rule = EveryNDays(days: 3, anchor: mon.addDays(1), times: [hm(6, 0)]);
      expect(at(rule, mon.addDays(-3), mon.addDays(7)), [
        '2026-11-14 06:00',
        '2026-11-17 06:00',
        '2026-11-20 06:00',
        '2026-11-23 06:00',
      ]);
    });

    test('interval between a start and end time, end included', () {
      final rule = Interval(everyMinutes: 90, start: hm(8, 0), end: hm(12, 30));
      expect(at(rule, mon, mon), [
        '2026-11-16 08:00',
        '2026-11-16 09:30',
        '2026-11-16 11:00',
        '2026-11-16 12:30',
      ]);
    });

    test('interval limited to weekdays', () {
      final rule = Interval(everyMinutes: 240, start: hm(9, 0), end: hm(17, 0), weekdays: {6});
      expect(at(rule, mon, mon.addDays(6)), [
        '2026-11-21 09:00',
        '2026-11-21 13:00',
        '2026-11-21 17:00',
      ]);
    });

    test('an empty range or a range backwards gives nothing', () {
      expect(at(Daily(times: [hm(7, 0)]), mon.addDays(1), mon), isEmpty);
    });
  });

  group('validation', () {
    test('rejects impossible values', () {
      expect(Daily(times: const []).problems, contains('times_empty'));
      expect(Daily(times: [1440]).problems, contains('time_out_of_range'));
      expect(Weekdays(weekdays: const {}, times: [0]).problems, contains('weekdays_empty'));
      expect(Weekdays(weekdays: {8}, times: [0]).problems, contains('weekday_out_of_range'));
      expect(EveryNDays(days: 0, anchor: mon, times: [0]).problems, contains('every_out_of_range'));
      expect(
        Interval(everyMinutes: 60, start: hm(10, 0), end: hm(9, 0)).problems,
        contains('end_before_start'),
      );
      expect(Interval(everyMinutes: 4, start: 0, end: 60).problems, contains('every_out_of_range'));
      expect(Monthly.dayOfMonth(32, times: [0]).problems, contains('day_out_of_range'));
      expect(Daily(times: [hm(7, 0)]).problems, isEmpty);
    });
  });

  group('JSON', () {
    final rules = <ScheduleRule>[
      OneTime(date: mon, time: hm(9, 0)),
      Daily(times: [hm(7, 0), hm(21, 0)]),
      Weekdays(weekdays: {1, 5}, times: [hm(6, 30)]),
      Weekly(everyWeeks: 2, anchor: mon, weekdays: {6}, times: [hm(10, 0)]),
      Monthly.dayOfMonth(15, times: [hm(9, 0)]),
      Monthly.nthWeekday(-1, 5, times: [hm(9, 0)]),
      EveryNDays(days: 3, anchor: mon, times: [hm(6, 0)]),
      Interval(everyMinutes: 90, start: hm(8, 0), end: hm(20, 0), weekdays: {1, 2}),
    ];
    for (final rule in rules) {
      test('round-trips ${rule.runtimeType}', () {
        expect(ScheduleRule.fromJson(rule.toJson()), rule);
      });
    }

    test('unknown type is a format error', () {
      expect(() => ScheduleRule.fromJson({'type': 'yearly'}), throwsFormatException);
    });
  });

  group('wall-clock time to instants', () {
    test('a fixed zone subtracts its offset', () {
      final rule = Daily(times: [hm(7, 0)]);
      final instants = calc.instants(
        rule,
        from: DateTime.utc(2026, 11, 16),
        to: DateTime.utc(2026, 11, 18),
        zone: const FixedZone(Duration(hours: 5, minutes: 30)),
      );
      expect(instants, [DateTime.utc(2026, 11, 16, 1, 30), DateTime.utc(2026, 11, 17, 1, 30)]);
    });

    test('07:00 stays 07:00 on both sides of a DST change', () {
      final rule = Daily(times: [hm(7, 0)]);
      final instants = calc.instants(
        rule,
        from: DateTime.utc(2027, 3, 27),
        to: DateTime.utc(2027, 3, 29, 12),
        zone: const EuZone(),
      );
      // 27 Mar: UTC+1; 28 and 29 Mar: UTC+2.
      expect(instants, [
        DateTime.utc(2027, 3, 27, 6),
        DateTime.utc(2027, 3, 28, 5),
        DateTime.utc(2027, 3, 29, 5),
      ]);
    });

    test('a time skipped by the spring change moves to the next valid minute', () {
      // On 28 Mar 2027 the clock jumps from 02:00 to 03:00.
      final rule = OneTime(date: LocalDate(2027, 3, 28), time: hm(2, 30));
      final instants = calc.instants(
        rule,
        from: DateTime.utc(2027, 3, 27),
        to: DateTime.utc(2027, 3, 29),
        zone: const EuZone(),
      );
      expect(instants, [DateTime.utc(2027, 3, 28, 1)]); // 03:00 local
    });

    test('a time repeated by the autumn change fires once, at the first', () {
      // On 31 Oct 2027 the clock goes back from 03:00 to 02:00.
      final rule = OneTime(date: LocalDate(2027, 10, 31), time: hm(2, 30));
      final instants = calc.instants(
        rule,
        from: DateTime.utc(2027, 10, 30),
        to: DateTime.utc(2027, 11, 1),
        zone: const EuZone(),
      );
      expect(instants, [DateTime.utc(2027, 10, 31, 0, 30)]);
    });

    test('only instants inside the range are returned', () {
      final rule = Daily(times: [hm(7, 0), hm(20, 0)]);
      final instants = calc.instants(
        rule,
        from: DateTime.utc(2026, 11, 16, 12),
        to: DateTime.utc(2026, 11, 17, 12),
        zone: const FixedZone(Duration.zero),
      );
      expect(instants, [DateTime.utc(2026, 11, 16, 20), DateTime.utc(2026, 11, 17, 7)]);
    });
  });
}
