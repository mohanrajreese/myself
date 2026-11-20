import '../../../core/utils/local_date.dart';

/// Inclusive calendar range.
typedef DateRange = ({LocalDate from, LocalDate to});

extension DateRangeMath on DateRange {
  int get days => to.daysSince(from) + 1;

  /// The period of the same length just before this one.
  DateRange get previous => (from: from.addDays(-days), to: from.addDays(-1));

  Iterable<LocalDate> get dates sync* {
    for (var d = from; !d.isAfter(to); d = d.addDays(1)) {
      yield d;
    }
  }

  bool contains(LocalDate d) => !d.isBefore(from) && !d.isAfter(to);
}

enum ReportPeriod { day, week, month, custom }

/// The day, week (Monday–Sunday) or calendar month containing [anchor].
DateRange periodRange(ReportPeriod p, LocalDate anchor) => switch (p) {
  ReportPeriod.day || ReportPeriod.custom => (from: anchor, to: anchor),
  ReportPeriod.week => (
    from: anchor.addDays(1 - anchor.weekday),
    to: anchor.addDays(7 - anchor.weekday),
  ),
  ReportPeriod.month => (
    from: _monthStart(anchor.year, anchor.month),
    to: _monthStart(anchor.year, anchor.month + 1).addDays(-1),
  ),
};

/// First day of a month; [month] may run past 12 or below 1.
LocalDate _monthStart(int year, int month) => LocalDate.fromDateTime(DateTime.utc(year, month));

/// The next (`by` = 1) or earlier (`by` = -1) period of the same kind.
DateRange stepPeriod(ReportPeriod p, DateRange r, int by) => switch (p) {
  ReportPeriod.month => periodRange(p, _monthStart(r.from.year, r.from.month + by)),
  _ => (from: r.from.addDays(by * r.days), to: r.to.addDays(by * r.days)),
};

/// For a calendar month, the previous calendar month; otherwise the same
/// number of days just before.
DateRange previousPeriod(ReportPeriod p, DateRange r) =>
    p == ReportPeriod.month ? stepPeriod(p, r, -1) : r.previous;

/// Everything a report shows, as one integer per day per measure in base
/// units. A missing day means no records, never zero.
enum Metric {
  steps,
  weightG,
  kcalMilli,
  proteinMg,
  carbsMg,
  fatMg,
  fibreMg,
  waterMl,
  sleepMin,
  moodMilli,
  energyMilli,
  stressMilli,
  wellnessMilli,
  junkItems,
  screenMs,
  walkM,
  runM,
  cycleM,
  walks,
  runs,
  rides,
  gymSessions,
  essentialDone,
  essentialScheduled,
}

final class PeriodReport {
  const PeriodReport({
    required this.range,
    required this.series,
    this.measurements = const {},
    this.newRecords = 0,
  });
  final DateRange range;
  final Map<Metric, Map<LocalDate, int>> series;

  /// Latest value per measurement type on or before the end of the range.
  final Map<String, int> measurements;

  /// Personal records first reached during the range.
  final int newRecords;

  Map<LocalDate, int> of(Metric m) => series[m] ?? const {};

  int daysWith(Metric m) => of(m).length;

  /// Mean over the days that have records, rounded; null with none.
  int? average(Metric m) {
    final v = of(m);
    if (v.isEmpty) return null;
    return (v.values.fold(0, (a, b) => a + b) / v.length).round();
  }

  int total(Metric m) => of(m).values.fold(0, (a, b) => a + b);

  /// Value on the latest day with a record.
  int? latest(Metric m) {
    final v = of(m);
    if (v.isEmpty) return null;
    final last = v.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    return v[last];
  }

  int get workouts =>
      total(Metric.walks) + total(Metric.runs) + total(Metric.rides) + total(Metric.gymSessions);

  /// Share of scheduled essential occurrences that were done, 0–100.
  int? get essentialPercent {
    final s = total(Metric.essentialScheduled);
    return s == 0 ? null : (total(Metric.essentialDone) * 100 / s).round();
  }
}

/// A descriptive comparison with the previous period (§5.20). Never causal.
enum InsightKind {
  stepsAverage,
  sleepAverage,
  weightLatest,
  waterAverage,
  kcalAverage,
  proteinAverage,
  fibreAverage,
  workouts,
  essentialPercent,
  screenAverage,
}

final class Insight {
  const Insight(this.kind, {required this.current, required this.previous});
  final InsightKind kind;
  final int current;
  final int previous;
  int get delta => current - previous;
}

/// Changes worth a sentence, most notable first, at most [limit]. A measure
/// needs records in both periods; small changes are left out.
List<Insight> insightsFor(PeriodReport now, PeriodReport before, {int limit = 5}) {
  final out = <(Insight, double)>[];
  void add(InsightKind k, int? cur, int? prev, int minDelta) {
    if (cur == null || prev == null) return;
    final d = (cur - prev).abs();
    if (d < minDelta) return;
    out.add((Insight(k, current: cur, previous: prev), prev == 0 ? 1 : d / prev.abs()));
  }

  add(InsightKind.stepsAverage, now.average(Metric.steps), before.average(Metric.steps), 300);
  add(InsightKind.sleepAverage, now.average(Metric.sleepMin), before.average(Metric.sleepMin), 10);
  add(InsightKind.weightLatest, now.latest(Metric.weightG), before.latest(Metric.weightG), 200);
  add(InsightKind.waterAverage, now.average(Metric.waterMl), before.average(Metric.waterMl), 200);
  add(
    InsightKind.kcalAverage,
    now.average(Metric.kcalMilli),
    before.average(Metric.kcalMilli),
    100000,
  );
  add(
    InsightKind.proteinAverage,
    now.average(Metric.proteinMg),
    before.average(Metric.proteinMg),
    5000,
  );
  add(InsightKind.fibreAverage, now.average(Metric.fibreMg), before.average(Metric.fibreMg), 3000);
  add(InsightKind.essentialPercent, now.essentialPercent, before.essentialPercent, 5);
  add(
    InsightKind.screenAverage,
    now.average(Metric.screenMs),
    before.average(Metric.screenMs),
    10 * 60000,
  );
  if (now.workouts > 0 || before.workouts > 0) {
    add(InsightKind.workouts, now.workouts, before.workouts, 1);
  }
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (i, _) in out.take(limit)) i];
}
