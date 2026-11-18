import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';

typedef AppMinutes = ({String packageName, String label, int foregroundMs});

final class ScreenTimeDay {
  const ScreenTimeDay({required this.date, required this.totalMs, required this.isPartial});
  final LocalDate date;
  final int totalMs;

  /// Today, still counting.
  final bool isPartial;
}

/// Totals and per-app usage, stored on the phone only (§5.17).
abstract interface class ScreenTimeRepository {
  /// Stores [apps] as the usage of [date] (replaces earlier values).
  Future<Result<void>> store(LocalDate date, List<AppMinutes> apps, {required bool partial});
  Stream<List<ScreenTimeDay>> watchDays({required LocalDate from, required LocalDate to});

  /// Apps for the days [from] to [to], summed, most used first.
  Stream<List<AppMinutes>> watchApps({required LocalDate from, required LocalDate to});
}
