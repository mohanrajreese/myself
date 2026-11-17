import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/weight/domain/weight_trend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final points = [
    (date: LocalDate(2026, 10, 10), weightG: 93000),
    (date: LocalDate(2026, 11, 2), weightG: 92100),
    (date: LocalDate(2026, 11, 9), weightG: 91800),
    (date: LocalDate(2026, 11, 16), weightG: 91200),
  ];
  final today = LocalDate(2026, 11, 16);

  test('change over a range compares the latest entry with the one at or before the start', () {
    expect(weightChangeG(points, today: today, days: 7), -600);
    expect(weightChangeG(points, today: today, days: 30), -1800); // baseline: 10 Oct
  });

  test('with no entry before the range, the first entry inside it is the baseline', () {
    final recent = points.sublist(1);
    expect(weightChangeG(recent, today: today, days: 30), -900);
  });

  test('no change can be stated from fewer than two entries', () {
    expect(weightChangeG(points.sublist(3), today: today, days: 7), isNull);
    expect(weightChangeG(const [], today: today, days: 7), isNull);
  });

  test('several entries on one day: the last one of the day is used', () {
    final sameDay = [
      (date: LocalDate(2026, 11, 9), weightG: 91800),
      (date: LocalDate(2026, 11, 16), weightG: 91500),
      (date: LocalDate(2026, 11, 16), weightG: 91200),
    ];
    expect(weightChangeG(sameDay, today: today, days: 7), -600);
  });

  test('range start is inclusive of the day N days ago', () {
    expect(rangeStart(today, 7), LocalDate(2026, 11, 9));
    expect(rangeStart(today, 365), LocalDate(2025, 11, 16));
  });
}
