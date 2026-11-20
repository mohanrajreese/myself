import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/location_tracker.dart';
import '../core/platform/step_counter.dart';
import '../core/utils/local_date.dart';
import '../features/fitness/data/drift_step_repository.dart';
import '../features/fitness/data/drift_workout_repository.dart';
import '../features/fitness/domain/step_repository.dart';
import '../features/fitness/domain/workout_math.dart';
import '../features/fitness/domain/workouts.dart';
import 'providers.dart';
import 'step_service.dart';

final stepCounterProvider = Provider<StepCounter>((ref) => DeviceStepCounter());
final locationTrackerProvider = Provider<LocationTracker>((ref) => DeviceLocationTracker());

final stepRepositoryProvider = Provider<StepRepository>(
  (ref) => DriftStepRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => DriftWorkoutRepository(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    timeZone: ref.watch(timeZoneSourceProvider),
  ),
);

final stepServiceProvider = Provider<StepService>(
  (ref) => StepService(counter: ref.watch(stepCounterProvider), steps: ref.watch(stepRepositoryProvider)),
);

final stepStatusProvider = FutureProvider<StepStatus>((ref) => ref.watch(stepServiceProvider).status());

/// Pulls new readings in without blocking the screen.
void syncSteps(WidgetRef ref) =>
    unawaited(ref.read(stepServiceProvider).sync().then((_) => ref.invalidate(stepStatusProvider), onError: (_) {}));

final stepDayProvider = StreamProvider.family<StepDay?, LocalDate>(
  (ref, d) => ref.watch(stepRepositoryProvider).watchDay(d),
);

final stepRangeProvider = StreamProvider.family<List<StepDay>, ({LocalDate from, LocalDate to})>(
  (ref, r) => ref.watch(stepRepositoryProvider).watchRange(r.from, r.to),
);

final exercisesProvider = StreamProvider<List<Exercise>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchExercises(),
);

final workoutsProvider = StreamProvider.family<List<WorkoutSession>, WorkoutKind?>(
  (ref, kind) => ref.watch(workoutRepositoryProvider).watchSessions(kind: kind),
);

final workoutProvider = StreamProvider.family<WorkoutSession?, String>(
  (ref, id) => ref.watch(workoutRepositoryProvider).watchSession(id),
);

final workoutsBetweenProvider = StreamProvider.family<List<WorkoutSession>, ({LocalDate from, LocalDate to})>(
  (ref, r) => ref.watch(workoutRepositoryProvider).watchBetween(r.from, r.to),
);

final templatesProvider = StreamProvider<List<WorkoutTemplate>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchTemplates(),
);

/// The unfinished gym workout, if any.
final activeGymProvider = Provider<WorkoutSession?>(
  (ref) => ref.watch(workoutsProvider(WorkoutKind.gym)).value?.where((s) => s.inProgress).firstOrNull,
);

typedef ExerciseProgress = ({List<PersonalRecord> records, List<({DateTime at, int value})> series});

/// Records and the heaviest (or longest) set per workout for one exercise.
final exerciseProgressProvider = FutureProvider.family<ExerciseProgress, Exercise>((ref, exercise) async {
  ref.watch(workoutsProvider(WorkoutKind.gym));
  final sets = await ref.watch(workoutRepositoryProvider).completedSets(exercise.id);
  final records = strengthRecords([
    for (final s in sets)
      SetRecordInput(
        sessionId: s.sessionId,
        at: s.at,
        loadG: s.set.loadG,
        reps: s.set.reps,
        durationS: s.set.durationS,
        distanceM: s.set.distanceM,
      ),
  ]);
  final bySession = <String, ({DateTime at, int value})>{};
  for (final s in sets) {
    final v = switch (exercise.measurementKind) {
      MeasurementKind.weightReps => (s.set.reps ?? 0) >= 1 ? s.set.loadG : null,
      MeasurementKind.repsOnly => s.set.reps,
      MeasurementKind.duration => s.set.durationS,
      MeasurementKind.distanceDuration => s.set.distanceM,
    };
    if (v == null) continue;
    final current = bySession[s.sessionId];
    if (current == null || v > current.value) bySession[s.sessionId] = (at: s.at, value: v);
  }
  final series = bySession.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  return (records: records, series: series);
});

final cardioRecordsProvider = Provider.family<List<PersonalRecord>, CardioKind>((ref, kind) {
  final sessions = ref.watch(workoutsProvider(null)).value ?? const [];
  return cardioRecords(kind, [
    for (final s in sessions)
      if (s.kind.cardio != null)
        CardioSession(kind: s.kind.cardio!, at: s.startedAt, distanceM: s.distanceM ?? 0, durationS: s.durationS),
  ]);
});
