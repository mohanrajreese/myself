import 'package:meta/meta.dart';

import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';
import 'sleep_math.dart';

@immutable
final class SleepEntry {
  const SleepEntry({required this.id, required this.period, this.quality, this.notes});
  final String id;

  /// Start and end in the user's wall-clock time.
  final SleepPeriod period;

  /// 1 (poor) to 5 (very good).
  final int? quality;
  final String? notes;
}

abstract interface class SleepRepository {
  /// [start] and [end] are wall-clock times as the user entered them.
  Future<Result<SleepEntry>> add({
    required SleepKind kind,
    required DateTime start,
    required DateTime end,
    int? quality,
    String? notes,
  });
  Future<Result<void>> update(
    String id, {
    required SleepKind kind,
    required DateTime start,
    required DateTime end,
    int? quality,
    String? notes,
  });
  Future<Result<void>> delete(String id);

  /// Records whose wake-up day is between [from] and [to], newest first.
  Stream<List<SleepEntry>> watchBetween(LocalDate from, LocalDate to);
}
