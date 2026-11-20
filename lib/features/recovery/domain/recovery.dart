import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';

/// Rest day and recovery ratings for one day (§5.19).
final class RecoveryLog {
  const RecoveryLog({
    required this.date,
    this.isRestDay = false,
    this.soreness,
    this.recovery,
    this.notes,
  });
  final LocalDate date;
  final bool isRestDay;

  /// 1 none – 5 very sore.
  final int? soreness;

  /// 1 poor – 5 fully recovered.
  final int? recovery;
  final String? notes;
}

abstract interface class RecoveryRepository {
  Future<Result<void>> save(RecoveryLog log);
  Stream<RecoveryLog?> watchDay(LocalDate date);
  Stream<List<RecoveryLog>> watchRecent({int limit = 30});
}
