// Drift check constraints refer to the column being defined; this is the
// documented pattern, not a recursive call at run time.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

import '../converters.dart';
import 'synced_columns.dart';

/// Daily step totals: the only step data that syncs (§6.6).
@DataClassName('StepLogRow')
class StepLogs extends Table with SyncedColumns {
  TextColumn get logDate => text().map(const LocalDateConverter())();
  IntColumn get steps => integer().check(steps.isBiggerOrEqualValue(0))();
  TextColumn get source =>
      text().check(source.isIn(const ['phone_sensor', 'phone_sensor_adjusted', 'manual']))();
  TextColumn get timezone => text()();
  DateTimeColumn get collectedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {logDate},
  ];
}

const measurementKinds = ['weight_reps', 'reps_only', 'duration', 'distance_duration'];

/// Exercise library: seeded reference rows (deterministic ids) and the
/// user's own exercises (C1, C10).
@DataClassName('ExerciseRow')
class Exercises extends Table with SyncedColumns {
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get muscleGroup => text()();
  TextColumn get equipment => text()();
  TextColumn get instructions => text().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  TextColumn get measurementKind => text().check(measurementKind.isIn(measurementKinds))();
  TextColumn get systemKey => text().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

@DataClassName('WorkoutSessionRow')
@TableIndex(name: 'workout_sessions_local_date', columns: {#localDate})
class WorkoutSessions extends Table with SyncedColumns {
  TextColumn get kind => text().check(kind.isIn(const ['gym', 'walk', 'run', 'cycle']))();
  TextColumn get name => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationS => integer().check(durationS.isBetweenValues(0, 86400))();
  TextColumn get localDate => text().map(const LocalDateConverter())();
  TextColumn get tz => text()();
  IntColumn get distanceM =>
      integer().nullable().check(distanceM.isNull() | distanceM.isBetweenValues(0, 500000))();

  /// Informational only; never added to daily step totals (§5.7).
  IntColumn get steps => integer().nullable()();
  TextColumn get entryMode => text().check(entryMode.isIn(const ['manual', 'gps']))();
  BoolColumn get hasRoute => boolean().withDefault(const Constant(false))();
  TextColumn get templateId => text().nullable()();
  TextColumn get notes => text().nullable()();
}

@DataClassName('WorkoutExerciseRow')
@TableIndex(name: 'workout_exercises_session', columns: {#sessionId})
class WorkoutExercises extends Table with SyncedColumns {
  TextColumn get sessionId => text().references(WorkoutSessions, #id)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
}

@DataClassName('ExerciseSetRow')
@TableIndex(name: 'exercise_sets_workout_exercise', columns: {#workoutExerciseId})
class ExerciseSets extends Table with SyncedColumns {
  TextColumn get workoutExerciseId => text().references(WorkoutExercises, #id)();
  IntColumn get setNumber => integer().check(setNumber.isBiggerOrEqualValue(1))();
  IntColumn get reps => integer().nullable().check(reps.isNull() | reps.isBetweenValues(0, 1000))();
  IntColumn get loadG =>
      integer().nullable().check(loadG.isNull() | loadG.isBetweenValues(0, 1000000))();
  TextColumn get entryUnit =>
      text().nullable().check(entryUnit.isNull() | entryUnit.isIn(const ['kg', 'lb']))();
  IntColumn get distanceM =>
      integer().nullable().check(distanceM.isNull() | distanceM.isBetweenValues(0, 500000))();
  IntColumn get durationS =>
      integer().nullable().check(durationS.isNull() | durationS.isBetweenValues(0, 86400))();
  IntColumn get restS =>
      integer().nullable().check(restS.isNull() | restS.isBetweenValues(0, 3600))();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

@DataClassName('WorkoutTemplateRow')
class WorkoutTemplates extends Table with SyncedColumns {
  TextColumn get name => text()();

  /// JSON list of `{exerciseId, sets: [{reps, loadG, durationS, distanceM}]}`.
  TextColumn get exercises => text()();
  IntColumn get useCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
}

/// Raw step-counter readings, phone only (§5.6). Pruned after 60 days.
@DataClassName('StepReadingRow')
@TableIndex(name: 'local_step_readings_time', columns: {#wallTimeUtc})
class LocalStepReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cumulativeSteps => integer()();
  IntColumn get bootCount => integer()();
  IntColumn get elapsedRealtimeMs => integer()();
  DateTimeColumn get wallTimeUtc => dateTime()();
  TextColumn get tz => text()();
  IntColumn get utcOffsetS => integer()();
  TextColumn get source => text().check(
    source.isIn(const ['service', 'worker', 'foreground', 'shutdown', 'boot', 'time_change']),
  )();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {bootCount, elapsedRealtimeMs},
  ];
}

/// Daily step workings, phone only; the source of `step_logs`.
@DataClassName('StepDailyRow')
class LocalStepDaily extends Table {
  TextColumn get localDate => text().map(const LocalDateConverter())();
  IntColumn get sensorSteps => integer().withDefault(const Constant(0))();
  IntColumn get manualAdjustment => integer().withDefault(const Constant(0))();
  IntColumn get uncertainSteps => integer().withDefault(const Constant(0))();
  IntColumn get gapCount => integer().withDefault(const Constant(0))();
  TextColumn get tz => text()();
  DateTimeColumn get lastCollectedAt => dateTime().nullable()();
  DateTimeColumn get computedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {localDate};
}

/// GPS route points, phone only (C3): only distance, time and pace sync.
@DataClassName('RoutePointRow')
@TableIndex(name: 'local_workout_route_points_session', columns: {#sessionId})
class LocalWorkoutRoutePoints extends Table {
  TextColumn get sessionId => text()();
  IntColumn get seq => integer()();
  IntColumn get latE7 => integer()();
  IntColumn get lonE7 => integer()();
  IntColumn get accuracyDm => integer().nullable()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId, seq};
}
