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

  Future<Result<void>> delete(String id);
}
