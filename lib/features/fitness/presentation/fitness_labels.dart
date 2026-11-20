import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/utils/local_date.dart';
import '../domain/workout_math.dart';
import '../domain/workouts.dart';

String workoutKindName(AppLocalizations l, WorkoutKind k) => switch (k) {
  WorkoutKind.gym => l.kindGym,
  WorkoutKind.walk => l.kindWalk,
  WorkoutKind.run => l.kindRun,
  WorkoutKind.cycle => l.kindRide,
};

IconData workoutIcon(WorkoutKind k) => switch (k) {
  WorkoutKind.gym => Icons.fitness_center_rounded,
  WorkoutKind.walk => Icons.directions_walk_rounded,
  WorkoutKind.run => Icons.directions_run_rounded,
  WorkoutKind.cycle => Icons.directions_bike_rounded,
};

String km(BuildContext context, int metres) => context.l10n.valueKm((metres / 1000).toStringAsFixed(2));

String paceLabel(BuildContext context, int secondsPerKm) =>
    context.l10n.pacePerKm('${secondsPerKm ~/ 60}:${(secondsPerKm % 60).toString().padLeft(2, '0')}');

String speedLabel(BuildContext context, int metresPerHour) =>
    context.l10n.speedKmh((metresPerHour / 1000).toStringAsFixed(1));

String clockLabel(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String kgLabel(BuildContext context, int grams) {
  final kg = grams / 1000;
  return context.l10n.valueKg(kg == kg.roundToDouble() ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1));
}

/// One line describing a session for lists.
String workoutSummary(BuildContext context, WorkoutSession s) {
  final l = context.l10n;
  final duration = context.duration(Duration(seconds: s.durationS));
  if (s.kind == WorkoutKind.gym) {
    return [
      if (s.inProgress) l.inProgress else duration,
      l.exercisesCount(s.entries.length),
      l.setsCount(s.setCount),
    ].join(' · ');
  }
  final pace = paceSecondsPerKm(distanceM: s.distanceM ?? 0, durationS: s.durationS);
  final speed = speedMetresPerHour(distanceM: s.distanceM ?? 0, durationS: s.durationS);
  return [
    km(context, s.distanceM ?? 0),
    duration,
    if (s.kind == WorkoutKind.cycle && speed != null) speedLabel(context, speed),
    if (s.kind != WorkoutKind.cycle && pace != null) paceLabel(context, pace),
    if (s.entryMode == 'gps') l.gpsTag,
  ].join(' · ');
}

String measurementName(AppLocalizations l, MeasurementKind k) => switch (k) {
  MeasurementKind.weightReps => l.measureWeightReps,
  MeasurementKind.repsOnly => l.measureReps,
  MeasurementKind.duration => l.measureDuration,
  MeasurementKind.distanceDuration => l.measureDistance,
};

String recordName(AppLocalizations l, RecordKind k, {String? load}) => switch (k) {
  RecordKind.highestLoad => l.recordHighestLoad,
  RecordKind.mostRepsAtLoad => l.recordRepsAt(load ?? ''),
  RecordKind.longestDuration => l.recordLongestDuration,
  RecordKind.longestDistance => l.recordLongestDistance,
  RecordKind.fastestPace => l.recordFastestPace,
};

/// The phone's calendar day of an instant.
extension LocalDateFrom on LocalDate {
  static LocalDate instant(DateTime at) => LocalDate.fromDateTime(at.toLocal());
}
