import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/insights/domain/report.dart';
import 'package:flutter_test/flutter_test.dart';

LocalDate d(int m, int day, [int y = 2026]) => LocalDate(y, m, day);

PeriodReport report(DateRange r, Map<Metric, Map<LocalDate, int>> s) => PeriodReport(range: r, series: s);

void main() {
  group('periods', () {
    test('a week runs Monday to Sunday', () {
      final r = periodRange(ReportPeriod.week, d(11, 18)); // Wednesday
      expect(r.from, d(11, 16));
      expect(r.to, d(11, 22));
      expect(r.days, 7);
    });

    test('months have their real length and step across a year', () {
      final feb = periodRange(ReportPeriod.month, d(2, 10));
      expect(feb.to, d(2, 28));
      final dec = periodRange(ReportPeriod.month, d(12, 31));
      expect(stepPeriod(ReportPeriod.month, dec, 1), (from: d(1, 1, 2027), to: d(1, 31, 2027)));
      expect(stepPeriod(ReportPeriod.month, periodRange(ReportPeriod.month, d(1, 5)), -1).from, d(12, 1, 2025));
    });

    test('the previous period has the same length; a month compares with the previous month', () {
      final custom = (from: d(8, 19), to: d(11, 16));
      expect(custom.days, 90);
      expect(custom.previous, (from: d(5, 21), to: d(8, 18)));
      final mar = periodRange(ReportPeriod.month, d(3, 3));
      expect(previousPeriod(ReportPeriod.month, mar), (from: d(2, 1), to: d(2, 28)));
    });
  });

  group('aggregates', () {
    final week = periodRange(ReportPeriod.week, d(11, 16));

    test('averages use only days with records; a missing day is not zero', () {
      final r = report(week, {
        Metric.kcalMilli: {d(11, 16): 2000000, d(11, 17): 2200000},
      });
      expect(r.average(Metric.kcalMilli), 2100000);
      expect(r.daysWith(Metric.kcalMilli), 2);
    });

    test('an empty period has no average, no latest, zero totals', () {
      final r = report(week, {});
      expect(r.average(Metric.steps), isNull);
      expect(r.latest(Metric.weightG), isNull);
      expect(r.total(Metric.walks), 0);
      expect(r.essentialPercent, isNull);
    });

    test('latest takes the most recent day', () {
      final r = report(week, {
        Metric.weightG: {d(11, 18): 91000, d(11, 16): 91800},
      });
      expect(r.latest(Metric.weightG), 91000);
    });

    test('essential completion is done over scheduled', () {
      final r = report(week, {
        Metric.essentialDone: {d(11, 16): 4, d(11, 17): 5},
        Metric.essentialScheduled: {d(11, 16): 5, d(11, 17): 5},
      });
      expect(r.essentialPercent, 90);
    });
  });

  group('insights', () {
    final now = periodRange(ReportPeriod.week, d(11, 16));
    final before = now.previous;

    test('compares averages with the previous period', () {
      final i = insightsFor(
        report(now, {
          Metric.steps: {d(11, 16): 9000, d(11, 17): 8000},
        }),
        report(before, {
          Metric.steps: {d(11, 9): 7300},
        }),
      );
      expect(i.single.kind, InsightKind.stepsAverage);
      expect(i.single.delta, 1200);
    });

    test('nothing is said about a measure missing from either period', () {
      expect(
        insightsFor(
          report(now, {
            Metric.steps: {d(11, 16): 9000},
          }),
          report(before, {}),
        ),
        isEmpty,
      );
    });

    test('small changes are left out', () {
      final i = insightsFor(
        report(now, {
          Metric.sleepMin: {d(11, 16): 425},
        }),
        report(before, {
          Metric.sleepMin: {d(11, 9): 420},
        }),
      );
      expect(i, isEmpty);
    });

    test('the largest relative changes come first, at most five', () {
      final cur = report(now, {
        Metric.steps: {d(11, 16): 8000},
        Metric.sleepMin: {d(11, 16): 480},
        Metric.waterMl: {d(11, 16): 3000},
        Metric.kcalMilli: {d(11, 16): 2500000},
        Metric.proteinMg: {d(11, 16): 120000},
        Metric.fibreMg: {d(11, 16): 30000},
        Metric.weightG: {d(11, 16): 90000},
      });
      final prev = report(before, {
        Metric.steps: {d(11, 9): 4000},
        Metric.sleepMin: {d(11, 9): 420},
        Metric.waterMl: {d(11, 9): 2000},
        Metric.kcalMilli: {d(11, 9): 2000000},
        Metric.proteinMg: {d(11, 9): 100000},
        Metric.fibreMg: {d(11, 9): 20000},
        Metric.weightG: {d(11, 9): 91000},
      });
      final i = insightsFor(cur, prev);
      expect(i, hasLength(5));
      expect(i.first.kind, InsightKind.stepsAverage); // +100 %
      expect(i.map((x) => x.kind), isNot(contains(InsightKind.weightLatest))); // −1 %, smallest
    });

    test('workouts are compared only when there were some', () {
      expect(insightsFor(report(now, {}), report(before, {})), isEmpty);
      final i = insightsFor(
        report(now, {
          Metric.runs: {d(11, 16): 1},
          Metric.gymSessions: {d(11, 17): 2},
        }),
        report(before, {
          Metric.gymSessions: {d(11, 10): 1},
        }),
      );
      expect(i.single.kind, InsightKind.workouts);
      expect(i.single.current, 3);
    });
  });
}
