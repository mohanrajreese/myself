import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses and formats ISO dates', () {
    final date = LocalDate.parse('2026-11-16');
    expect(date, LocalDate(2026, 11, 16));
    expect(date.toString(), '2026-11-16');
    expect(LocalDate(2026, 3, 5).toString(), '2026-03-05');
  });

  test('rejects malformed and impossible dates', () {
    expect(() => LocalDate.parse('2026-13-01'), throwsFormatException);
    expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
    expect(() => LocalDate.parse('16/11/2026'), throwsFormatException);
    expect(() => LocalDate(2025, 2, 29), throwsArgumentError);
  });

  test('takes the calendar day of a wall-clock DateTime', () {
    expect(LocalDate.fromDateTime(DateTime(2026, 11, 16, 23, 59, 59)), LocalDate(2026, 11, 16));
    expect(LocalDate.fromDateTime(DateTime(2026, 11, 17)), LocalDate(2026, 11, 17));
  });

  test('derives the local day of an instant from a UTC offset', () {
    final instant = DateTime.utc(2026, 11, 16, 20, 0); // 01:30 next day at +05:30
    expect(
      LocalDate.ofInstant(instant, const Duration(hours: 5, minutes: 30)),
      LocalDate(2026, 11, 17),
    );
    expect(LocalDate.ofInstant(instant, const Duration(hours: -8)), LocalDate(2026, 11, 16));
  });

  test('adds days across month, year and leap-day boundaries', () {
    expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
    expect(LocalDate(2028, 2, 28).addDays(1), LocalDate(2028, 2, 29));
    expect(LocalDate(2026, 3, 1).addDays(-1), LocalDate(2026, 2, 28));
    expect(LocalDate(2026, 1, 1).addDays(365), LocalDate(2027, 1, 1));
  });

  test('counts whole days between dates regardless of DST', () {
    expect(LocalDate(2026, 11, 16).daysSince(LocalDate(2026, 11, 9)), 7);
    expect(LocalDate(2026, 3, 30).daysSince(LocalDate(2026, 3, 28)), 2);
    expect(LocalDate(2026, 1, 1).daysSince(LocalDate(2026, 1, 2)), -1);
  });

  test('orders, compares and reports the ISO weekday', () {
    expect(LocalDate(2026, 11, 16).compareTo(LocalDate(2026, 11, 17)), isNegative);
    expect(LocalDate(2026, 11, 16).isBefore(LocalDate(2026, 11, 17)), isTrue);
    expect(LocalDate(2026, 11, 16).isAfter(LocalDate(2026, 11, 16)), isFalse);
    expect(LocalDate(2026, 11, 16).weekday, DateTime.monday);
    expect({LocalDate(2026, 1, 1), LocalDate(2026, 1, 1)}, hasLength(1));
  });
}
