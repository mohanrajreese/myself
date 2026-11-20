import 'package:meta/meta.dart';

/// A calendar day with no time and no timezone (the user's local day).
@immutable
final class LocalDate implements Comparable<LocalDate> {
  factory LocalDate(int year, int month, int day) {
    final utc = DateTime.utc(year, month, day);
    if (utc.year != year || utc.month != month || utc.day != day) {
      throw ArgumentError('Not a calendar date: $year-$month-$day');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  /// The calendar day shown by a wall-clock [dateTime].
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate._(dateTime.year, dateTime.month, dateTime.day);

  /// The local day of [instant] for a zone that is [utcOffset] ahead of UTC.
  factory LocalDate.ofInstant(DateTime instant, Duration utcOffset) =>
      LocalDate.fromDateTime(instant.toUtc().add(utcOffset));

  /// Parses `YYYY-MM-DD`.
  factory LocalDate.parse(String text) {
    final match = _iso.firstMatch(text);
    if (match == null) throw FormatException('Expected YYYY-MM-DD', text);
    try {
      return LocalDate(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
    } on ArgumentError {
      throw FormatException('Not a calendar date', text);
    }
  }

  static final _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  DateTime get _utc => DateTime.utc(year, month, day);

  /// ISO weekday, Monday = 1 … Sunday = 7.
  int get weekday => _utc.weekday;

  LocalDate addDays(int days) => LocalDate.fromDateTime(_utc.add(Duration(days: days)));

  /// Whole days from [other] to this date (negative when this is earlier).
  int daysSince(LocalDate other) => _utc.difference(other._utc).inDays;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
