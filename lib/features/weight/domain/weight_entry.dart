import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/units/units.dart';
import '../../../core/utils/local_date.dart';

const minWeightG = 1000;
const maxWeightG = 700000;

ValidationFailure? validateWeightG(int grams) =>
    grams < minWeightG || grams > maxWeightG ? const ValidationFailure('weightG', 'out_of_range') : null;

@immutable
final class WeightEntry {
  const WeightEntry({
    required this.id,
    required this.weightG,
    required this.entryUnit,
    required this.occurredAt,
    required this.localDate,
    required this.tz,
    this.notes,
  });

  final String id;
  final int weightG;

  /// The unit the user typed, so the value is shown back as entered.
  final MassUnit entryUnit;
  final DateTime occurredAt;
  final LocalDate localDate;
  final String tz;
  final String? notes;
}
