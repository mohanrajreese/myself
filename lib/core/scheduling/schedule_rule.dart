import '../utils/local_date.dart';

/// When something recurs, on the local wall clock (05 §A4). Shared by
/// activities, reminders and medication; stored as JSON.
///
/// Times are minutes after local midnight (0–1439). Weekdays are ISO:
/// Monday = 1 … Sunday = 7.
sealed class ScheduleRule {
  const ScheduleRule();

  /// Machine codes for invalid values; empty when the rule is usable.
  List<String> get problems;

  Map<String, Object?> toJson();

  static ScheduleRule fromJson(Map<String, Object?> json) {
    try {
      return switch (json['type']) {
        'one_time' => OneTime(date: LocalDate.parse(json['date']! as String), time: json['time']! as int),
        'daily' => Daily(times: _ints(json['times'])),
        'weekdays' => Weekdays(weekdays: _ints(json['weekdays']).toSet(), times: _ints(json['times'])),
        'weekly' => Weekly(
          everyWeeks: json['every']! as int,
          anchor: LocalDate.parse(json['anchor']! as String),
          weekdays: _ints(json['weekdays']).toSet(),
          times: _ints(json['times']),
        ),
        'monthly' =>
          json['day'] != null
              ? Monthly.dayOfMonth(json['day']! as int, times: _ints(json['times']))
              : Monthly.nthWeekday(json['nth']! as int, json['weekday']! as int, times: _ints(json['times'])),
        'every_n_days' => EveryNDays(
          days: json['every']! as int,
          anchor: LocalDate.parse(json['anchor']! as String),
          times: _ints(json['times']),
        ),
        'interval' => IntervalRule(
          everyMinutes: json['every']! as int,
          start: json['start']! as int,
          end: json['end']! as int,
          weekdays: json['weekdays'] == null ? null : _ints(json['weekdays']).toSet(),
        ),
        _ => throw FormatException('Unknown schedule type', json['type']),
      };
    } on TypeError catch (e) {
      throw FormatException('Malformed schedule rule: $e');
    }
  }

  static List<int> _ints(Object? value) => [for (final v in value! as List<Object?>) v! as int];
}

List<int> _sortedUnique(Iterable<int> values) => (values.toSet().toList()..sort());

List<String> _timeProblems(List<int> times) => [
  if (times.isEmpty) 'times_empty',
  if (times.any((t) => t < 0 || t >= 1440)) 'time_out_of_range',
];

List<String> _weekdayProblems(Set<int> weekdays) => [
  if (weekdays.isEmpty) 'weekdays_empty',
  if (weekdays.any((d) => d < 1 || d > 7)) 'weekday_out_of_range',
];

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSet(Set<int>? a, Set<int>? b) => a == null || b == null ? a == b : a.length == b.length && a.containsAll(b);

final class OneTime extends ScheduleRule {
  const OneTime({required this.date, required this.time});
  final LocalDate date;
  final int time;

  @override
  List<String> get problems => _timeProblems([time]);

  @override
  Map<String, Object?> toJson() => {'type': 'one_time', 'date': date.toString(), 'time': time};

  @override
  bool operator ==(Object other) => other is OneTime && other.date == date && other.time == time;
  @override
  int get hashCode => Object.hash(date, time);
}

final class Daily extends ScheduleRule {
  Daily({required Iterable<int> times}) : times = _sortedUnique(times);
  final List<int> times;

  @override
  List<String> get problems => _timeProblems(times);

  @override
  Map<String, Object?> toJson() => {'type': 'daily', 'times': times};

  @override
  bool operator ==(Object other) => other is Daily && _sameList(other.times, times);
  @override
  int get hashCode => Object.hashAll(times);
}

final class Weekdays extends ScheduleRule {
  Weekdays({required Set<int> weekdays, required Iterable<int> times})
    : weekdays = Set.unmodifiable(weekdays),
      times = _sortedUnique(times);
  final Set<int> weekdays;
  final List<int> times;

  @override
  List<String> get problems => [..._weekdayProblems(weekdays), ..._timeProblems(times)];

  @override
  Map<String, Object?> toJson() => {'type': 'weekdays', 'weekdays': _sortedUnique(weekdays), 'times': times};

  @override
  bool operator ==(Object other) =>
      other is Weekdays && _sameSet(other.weekdays, weekdays) && _sameList(other.times, times);
  @override
  int get hashCode => Object.hash(Object.hashAllUnordered(weekdays), Object.hashAll(times));
}

/// Every [everyWeeks] weeks, counted from the week (Monday to Sunday) that
/// contains [anchor].
final class Weekly extends ScheduleRule {
  Weekly({required this.everyWeeks, required this.anchor, required Set<int> weekdays, required Iterable<int> times})
    : weekdays = Set.unmodifiable(weekdays),
      times = _sortedUnique(times);
  final int everyWeeks;
  final LocalDate anchor;
  final Set<int> weekdays;
  final List<int> times;

  @override
  List<String> get problems => [
    if (everyWeeks < 1 || everyWeeks > 52) 'every_out_of_range',
    ..._weekdayProblems(weekdays),
    ..._timeProblems(times),
  ];

  @override
  Map<String, Object?> toJson() => {
    'type': 'weekly',
    'every': everyWeeks,
    'anchor': anchor.toString(),
    'weekdays': _sortedUnique(weekdays),
    'times': times,
  };

  @override
  bool operator ==(Object other) =>
      other is Weekly &&
      other.everyWeeks == everyWeeks &&
      other.anchor == anchor &&
      _sameSet(other.weekdays, weekdays) &&
      _sameList(other.times, times);
  @override
  int get hashCode => Object.hash(everyWeeks, anchor, Object.hashAllUnordered(weekdays), Object.hashAll(times));
}

/// On a day of the month (the month's last day when it is shorter), or on
/// the nth weekday of the month ([nth] 1–4, or -1 for the last).
final class Monthly extends ScheduleRule {
  Monthly.dayOfMonth(int this.day, {required Iterable<int> times})
    : nth = null,
      weekday = null,
      times = _sortedUnique(times);
  Monthly.nthWeekday(int this.nth, int this.weekday, {required Iterable<int> times})
    : day = null,
      times = _sortedUnique(times);

  final int? day;
  final int? nth;
  final int? weekday;
  final List<int> times;

  @override
  List<String> get problems => [
    if (day != null && (day! < 1 || day! > 31)) 'day_out_of_range',
    if (nth != null && !(nth == -1 || (nth! >= 1 && nth! <= 4))) 'nth_out_of_range',
    if (weekday != null && (weekday! < 1 || weekday! > 7)) 'weekday_out_of_range',
    ..._timeProblems(times),
  ];

  @override
  Map<String, Object?> toJson() => {
    'type': 'monthly',
    if (day != null) 'day': day,
    if (nth != null) 'nth': nth,
    if (weekday != null) 'weekday': weekday,
    'times': times,
  };

  @override
  bool operator ==(Object other) =>
      other is Monthly &&
      other.day == day &&
      other.nth == nth &&
      other.weekday == weekday &&
      _sameList(other.times, times);
  @override
  int get hashCode => Object.hash(day, nth, weekday, Object.hashAll(times));
}

/// Every [days] days on the dates that are a whole number of periods from
/// [anchor], before or after it.
final class EveryNDays extends ScheduleRule {
  EveryNDays({required this.days, required this.anchor, required Iterable<int> times}) : times = _sortedUnique(times);
  final int days;
  final LocalDate anchor;
  final List<int> times;

  @override
  List<String> get problems => [if (days < 1 || days > 366) 'every_out_of_range', ..._timeProblems(times)];

  @override
  Map<String, Object?> toJson() => {'type': 'every_n_days', 'every': days, 'anchor': anchor.toString(), 'times': times};

  @override
  bool operator ==(Object other) =>
      other is EveryNDays && other.days == days && other.anchor == anchor && _sameList(other.times, times);
  @override
  int get hashCode => Object.hash(days, anchor, Object.hashAll(times));
}

/// Every [everyMinutes] from [start] to [end] (included when it falls on the
/// step), on [weekdays] or every day when null.
final class IntervalRule extends ScheduleRule {
  IntervalRule({required this.everyMinutes, required this.start, required this.end, Set<int>? weekdays})
    : weekdays = weekdays == null ? null : Set.unmodifiable(weekdays);
  final int everyMinutes;
  final int start;
  final int end;
  final Set<int>? weekdays;

  @override
  List<String> get problems => [
    if (everyMinutes < 5 || everyMinutes > 720) 'every_out_of_range',
    ..._timeProblems([start, end]),
    if (end < start) 'end_before_start',
    if (weekdays != null) ..._weekdayProblems(weekdays!),
  ];

  @override
  Map<String, Object?> toJson() => {
    'type': 'interval',
    'every': everyMinutes,
    'start': start,
    'end': end,
    if (weekdays != null) 'weekdays': _sortedUnique(weekdays!),
  };

  @override
  bool operator ==(Object other) =>
      other is IntervalRule &&
      other.everyMinutes == everyMinutes &&
      other.start == start &&
      other.end == end &&
      _sameSet(other.weekdays, weekdays);
  @override
  int get hashCode =>
      Object.hash(everyMinutes, start, end, weekdays == null ? null : Object.hashAllUnordered(weekdays!));
}
