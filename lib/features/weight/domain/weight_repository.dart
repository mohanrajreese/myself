import '../../../core/errors/result.dart';
import '../../../core/units/units.dart';
import '../../../core/utils/local_date.dart';
import 'weight_entry.dart';

abstract interface class WeightRepository {
  /// Records a weight taken now.
  Future<Result<WeightEntry>> add({
    required int weightG,
    required MassUnit entryUnit,
    String? notes,
  });

  /// The most recent entry, or null when there is none.
  Future<WeightEntry?> latest();
  Stream<WeightEntry?> watchLatest();

  /// Entries recorded on [date], oldest first.
  Stream<List<WeightEntry>> watchOn(LocalDate date);

  /// Changes an entry's value, time or note. [occurredAt] is wall-clock time.
  Future<Result<void>> update(
    String id, {
    required int weightG,
    DateTime? occurredAt,
    String? notes,
  });

  /// One page of history, newest first. Pass the last entry's time as
  /// [before] to load the next page.
  Future<List<WeightEntry>> page({int limit = 30, DateTime? before});

  /// Entries from [from] onwards plus the last one before it (the baseline
  /// for a change calculation), oldest first.
  Stream<List<WeightEntry>> watchSince(LocalDate from);

  Future<Result<void>> delete(String id);
}
