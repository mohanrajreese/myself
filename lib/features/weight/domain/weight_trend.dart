import '../../../core/utils/local_date.dart';

typedef WeightPoint = ({LocalDate date, int weightG});

/// First day of a range that ends [today] and reaches back [days] days.
LocalDate rangeStart(LocalDate today, int days) => today.addDays(-days);

/// Change in grams from the start of the range to the latest entry.
///
/// The baseline is the last entry on or before the range start; if there is
/// none, the first entry inside the range. [points] must be oldest first.
/// Null when fewer than two entries can be compared. This describes the
/// difference between two readings; it says nothing about fat or muscle.
int? weightChangeG(List<WeightPoint> points, {required LocalDate today, required int days}) {
  if (points.length < 2) return null;
  final start = rangeStart(today, days);
  final latest = points.last;

  var baselineIndex = 0;
  for (var i = 0; i < points.length; i++) {
    if (!points[i].date.isAfter(start)) baselineIndex = i;
  }
  if (baselineIndex == points.length - 1) return null;
  return latest.weightG - points[baselineIndex].weightG;
}
