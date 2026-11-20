import 'dart:convert';

import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';
import 'workout_math.dart';

enum MeasurementKind {
  weightReps('weight_reps'),
  repsOnly('reps_only'),
  duration('duration'),
  distanceDuration('distance_duration');

  const MeasurementKind(this.code);
  final String code;
  static MeasurementKind fromCode(String code) => values.firstWhere((k) => k.code == code);
}

final class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.muscleGroup,
    required this.equipment,
    required this.measurementKind,
    this.instructions,
    this.isCustom = false,
    this.archived = false,
  });
  final String id;
  final String name;
  final String category;
  final String muscleGroup;
  final String equipment;
  final String? instructions;
  final bool isCustom;
  final MeasurementKind measurementKind;
  final bool archived;

  List<String> get problems => [if (name.trim().isEmpty) 'name_required', if (name.trim().length > 80) 'name_too_long'];
}

enum WorkoutKind {
  gym('gym'),
  walk('walk'),
  run('run'),
  cycle('cycle');

  const WorkoutKind(this.code);
  final String code;
  static WorkoutKind fromCode(String code) => values.firstWhere((k) => k.code == code);

  CardioKind? get cardio => switch (this) {
    WorkoutKind.walk => CardioKind.walk,
    WorkoutKind.run => CardioKind.run,
    WorkoutKind.cycle => CardioKind.cycle,
    WorkoutKind.gym => null,
  };
}

final class ExerciseSet {
  const ExerciseSet({
    required this.id,
    required this.setNumber,
    this.reps,
    this.loadG,
    this.entryUnit,
    this.distanceM,
    this.durationS,
    this.restS,
    this.completedAt,
  });
  final String id;
  final int setNumber;
  final int? reps;
  final int? loadG;
  final String? entryUnit;
  final int? distanceM;
  final int? durationS;
  final int? restS;
  final DateTime? completedAt;

  bool get done => completedAt != null;
}

final class WorkoutEntry {
  const WorkoutEntry({required this.id, required this.exercise, required this.sets, this.notes});
  final String id;
  final Exercise exercise;
  final List<ExerciseSet> sets;
  final String? notes;
}

final class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.kind,
    required this.name,
    required this.startedAt,
    required this.localDate,
    required this.durationS,
    required this.entryMode,
    this.endedAt,
    this.distanceM,
    this.hasRoute = false,
    this.templateId,
    this.notes,
    this.entries = const [],
  });
  final String id;
  final WorkoutKind kind;
  final String name;
  final DateTime startedAt;
  final DateTime? endedAt;
  final LocalDate localDate;
  final int durationS;
  final int? distanceM;
  final String entryMode;
  final bool hasRoute;
  final String? templateId;
  final String? notes;
  final List<WorkoutEntry> entries;

  bool get inProgress => kind == WorkoutKind.gym && endedAt == null;
  int get setCount => entries.fold(0, (n, e) => n + e.sets.where((s) => s.done).length);
}

/// A planned set in a template.
typedef PlannedSet = ({int? reps, int? loadG, int? durationS, int? distanceM});

final class WorkoutTemplate {
  const WorkoutTemplate({required this.id, required this.name, required this.exercises, this.useCount = 0});
  final String id;
  final String name;
  final List<({String exerciseId, List<PlannedSet> sets})> exercises;
  final int useCount;

  static String encode(List<({String exerciseId, List<PlannedSet> sets})> list) => jsonEncode([
    for (final e in list)
      {
        'exerciseId': e.exerciseId,
        'sets': [
          for (final s in e.sets)
            {'reps': s.reps, 'loadG': s.loadG, 'durationS': s.durationS, 'distanceM': s.distanceM},
        ],
      },
  ]);

  static List<({String exerciseId, List<PlannedSet> sets})> decode(String json) => [
    for (final e in jsonDecode(json) as List<Object?>)
      if (e case {'exerciseId': final String id, 'sets': final List<Object?> sets})
        (
          exerciseId: id,
          sets: [
            for (final s in sets)
              if (s case final Map<String, Object?> m)
                (
                  reps: m['reps'] as int?,
                  loadG: m['loadG'] as int?,
                  durationS: m['durationS'] as int?,
                  distanceM: m['distanceM'] as int?,
                ),
          ],
        ),
  ];
}

/// A GPS fix, stored on the phone only (C3).
typedef RoutePoint = ({int latE7, int lonE7, int? accuracyDm, DateTime at});

typedef SetDraft = ({int? reps, int? loadG, String? entryUnit, int? distanceM, int? durationS, int? restS, bool done});

abstract interface class WorkoutRepository {
  /// Adds or refreshes the bundled exercise list (deterministic ids).
  Future<void> seedExercises();
  Stream<List<Exercise>> watchExercises();
  Future<Result<Exercise>> createExercise(Exercise draft);
  Future<Result<void>> updateExercise(Exercise exercise);
  Future<Result<void>> archiveExercise(String id);

  /// A finished walk, run or ride, entered by hand or from GPS.
  Future<Result<WorkoutSession>> logCardio({
    required WorkoutKind kind,
    required DateTime start,
    required DateTime end,
    required int distanceM,
    String? notes,
    List<RoutePoint> route = const [],
  });

  Future<Result<String>> startGym({required String name, String? templateId});
  Future<Result<void>> finishGym(String sessionId);
  Future<Result<void>> updateSession(
    String id, {
    String? name,
    String? notes,
    DateTime? start,
    DateTime? end,
    int? distanceM,
  });
  Future<Result<void>> deleteSession(String id);

  /// Copies a workout's exercises and sets into a new, unfinished gym session.
  Future<Result<String>> duplicate(String sessionId);

  Future<Result<String>> addExercise(String sessionId, String exerciseId);
  Future<Result<void>> removeExercise(String workoutExerciseId);
  Future<Result<void>> reorderExercises(String sessionId, List<String> orderedIds);
  Future<Result<String>> addSet(String workoutExerciseId, SetDraft draft);
  Future<Result<void>> updateSet(String setId, SetDraft draft);
  Future<Result<void>> removeSet(String setId);

  Stream<List<WorkoutSession>> watchSessions({WorkoutKind? kind, int limit = 100});
  Stream<WorkoutSession?> watchSession(String id);
  Stream<List<WorkoutSession>> watchBetween(LocalDate from, LocalDate to);

  Future<Result<String>> saveTemplate(String sessionId, String name);
  Stream<List<WorkoutTemplate>> watchTemplates();
  Future<Result<void>> deleteTemplate(String id);

  /// Completed sets of one exercise, oldest first, with when they were done.
  Future<List<({String sessionId, DateTime at, ExerciseSet set})>> completedSets(String exerciseId);
  Future<List<RoutePoint>> route(String sessionId);
}
