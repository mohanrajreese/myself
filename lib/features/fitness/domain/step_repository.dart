import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';
import 'step_attribution.dart';

/// A sensor reading with where it came from.
typedef RawStepReading = ({StepReading reading, String tz, String source});

/// One day's steps (05 §B5). The total is the sensor count plus the user's
/// labelled adjustment; workout steps are never added (§5.7).
final class StepDay {
  const StepDay({
    required this.date,
    required this.sensorSteps,
    required this.manualAdjustment,
    required this.uncertainSteps,
    required this.gapCount,
    this.lastCollectedAt,
  });
  final LocalDate date;
  final int sensorSteps;
  final int manualAdjustment;
  final int uncertainSteps;
  final int gapCount;
  final DateTime? lastCollectedAt;

  int get total => sensorSteps + manualAdjustment < 0 ? 0 : sensorSteps + manualAdjustment;
  bool get isUncertain => uncertainSteps > 0 || gapCount > 0;
}

abstract interface class StepRepository {
  /// Stores new readings (duplicates ignored) and recomputes the days they
  /// touch.
  Future<Result<void>> ingest(List<RawStepReading> readings);

  /// Adds [delta] (negative removes) to the user's adjustment for [date].
  Future<Result<void>> adjust(LocalDate date, int delta);

  Stream<StepDay?> watchDay(LocalDate date);
  Stream<List<StepDay>> watchRange(LocalDate from, LocalDate to);
  Future<DateTime?> lastReadingAt();
}
