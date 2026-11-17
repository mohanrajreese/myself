import '../platform/time_zone_source.dart';
import '../utils/clock.dart';
import '../utils/local_date.dart';

/// When and where (in time) a record was made: the UTC instant, the user's
/// calendar day and the timezone in force.
typedef LogStamp = ({DateTime nowUtc, DateTime occurredAt, LocalDate localDate, String tz});

/// [at] is the user's wall-clock time for the event; it defaults to now.
Future<LogStamp> stampFor(Clock clock, TimeZoneSource timeZone, {DateTime? at}) async {
  final now = clock.now();
  final wall = at ?? now;
  return (
    nowUtc: now.toUtc(),
    occurredAt: wall.toUtc(),
    localDate: LocalDate.fromDateTime(wall.toLocal()),
    tz: await timeZone.currentTimeZoneId(),
  );
}
