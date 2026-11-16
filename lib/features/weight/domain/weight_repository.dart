import '../../../core/errors/result.dart';
import '../../../core/units/units.dart';
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

  Future<Result<void>> delete(String id);
}
