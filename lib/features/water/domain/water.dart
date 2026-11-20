import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';

@immutable
final class WaterEntry {
  const WaterEntry({required this.id, required this.amountMl, required this.occurredAt, required this.localDate});
  final String id;
  final int amountMl;
  final DateTime occurredAt;
  final LocalDate localDate;
}

ValidationFailure? validateWaterMl(int amountMl) =>
    amountMl < 1 || amountMl > 5000 ? const ValidationFailure('amountMl', 'out_of_range') : null;

abstract interface class WaterRepository {
  /// Records a drink now, or at wall-clock time [at].
  Future<Result<WaterEntry>> add(int amountMl, {DateTime? at});
  Future<Result<void>> remove(String id);

  /// Entries of one day, newest first.
  Stream<List<WaterEntry>> watchOn(LocalDate date);
  Stream<int> watchTotalOn(LocalDate date);

  /// Total per day for days that have entries, [from] to [to] inclusive.
  Future<Map<LocalDate, int>> totalsBetween(LocalDate from, LocalDate to);
}
