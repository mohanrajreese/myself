import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';

/// One check-in. Each score is 1 (low) to 5 (high) (PRD §5.10).
@immutable
final class WellnessScores {
  const WellnessScores({
    required this.energy,
    required this.mood,
    required this.stress,
    required this.wellness,
  });
  final int energy;
  final int mood;
  final int stress;
  final int wellness;

  ValidationFailure? validate() {
    for (final (field, value) in [
      ('energy', energy),
      ('mood', mood),
      ('stress', stress),
      ('wellness', wellness),
    ]) {
      if (value < 1 || value > 5) return ValidationFailure(field, 'out_of_range');
    }
    return null;
  }
}

@immutable
final class WellnessCheckin {
  const WellnessCheckin({
    required this.id,
    required this.scores,
    required this.occurredAt,
    required this.localDate,
    this.notes,
  });
  final String id;
  final WellnessScores scores;
  final DateTime occurredAt;
  final LocalDate localDate;
  final String? notes;
}

abstract interface class WellnessRepository {
  Future<Result<WellnessCheckin>> add(WellnessScores scores, {String? notes});
  Future<Result<void>> delete(String id);

  /// Check-ins between [from] and [to] inclusive, newest first. A day can
  /// have several.
  Stream<List<WellnessCheckin>> watchBetween(LocalDate from, LocalDate to);
}

/// Mean of each score per day, for trend charts. Values are tenths
/// (35 means 3.5) to stay in integers.
Map<LocalDate, ({int energy, int mood, int stress, int wellness})> dailyMeansTenths(
  Iterable<WellnessCheckin> checkins,
) {
  final byDay = <LocalDate, List<WellnessScores>>{};
  for (final c in checkins) {
    byDay.putIfAbsent(c.localDate, () => []).add(c.scores);
  }
  int mean(List<WellnessScores> day, int Function(WellnessScores s) pick) =>
      (day.fold<int>(0, (sum, s) => sum + pick(s)) * 10 / day.length).round();
  return {
    for (final entry in byDay.entries)
      entry.key: (
        energy: mean(entry.value, (s) => s.energy),
        mood: mean(entry.value, (s) => s.mood),
        stress: mean(entry.value, (s) => s.stress),
        wellness: mean(entry.value, (s) => s.wellness),
      ),
  };
}
