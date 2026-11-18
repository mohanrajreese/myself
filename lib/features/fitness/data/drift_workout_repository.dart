import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/log_stamp.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/workout_math.dart';
import '../domain/workouts.dart';
import 'exercise_seed.dart';

final class DriftWorkoutRepository implements WorkoutRepository {
  DriftWorkoutRepository(
    this._db, {
    required this.clock,
    required this.ids,
    required this.timeZone,
  });

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  static const _uuid = Uuid();

  /// Same id on every phone, so seeded exercises never duplicate on sync.
  static String seedId(String key) =>
      _uuid.v5(Namespace.url.value, 'https://fitbuddy.app/exercise/$key');

  DateTime get _now => clock.now().toUtc();

  Future<void> _sync(String table, String id) => _db.enqueueForSync(table, id, _now);

  static Exercise _toExercise(ExerciseRow r) => Exercise(
    id: r.id,
    name: r.name,
    category: r.category,
    muscleGroup: r.muscleGroup,
    equipment: r.equipment,
    instructions: r.instructions,
    isCustom: r.isCustom,
    measurementKind: MeasurementKind.fromCode(r.measurementKind),
    archived: r.archived,
  );

  static ExerciseSet _toSet(ExerciseSetRow r) => ExerciseSet(
    id: r.id,
    setNumber: r.setNumber,
    reps: r.reps,
    loadG: r.loadG,
    entryUnit: r.entryUnit,
    distanceM: r.distanceM,
    durationS: r.durationS,
    restS: r.restS,
    completedAt: r.completedAt?.toUtc(),
  );

  // ------------------------------------------------------------ exercises

  @override
  Future<void> seedExercises() => _db.transaction(() async {
    final now = _now;
    for (final (key, name, category, muscle, equipment, kind) in exerciseSeed) {
      final id = seedId(key);
      final existing = await (_db.select(
        _db.exercises,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (existing != null) continue;
      await _db
          .into(_db.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: id,
              createdAt: now,
              updatedAt: now,
              name: name,
              category: category,
              muscleGroup: muscle,
              equipment: equipment,
              measurementKind: kind,
              systemKey: Value(key),
            ),
          );
      await _sync('exercises', id);
    }
  });

  @override
  Stream<List<Exercise>> watchExercises() =>
      (_db.select(_db.exercises)
            ..where((t) => t.deletedAt.isNull() & t.archived.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.name.collate(Collate.noCase))]))
          .watch()
          .map((rows) => [for (final r in rows) _toExercise(r)]);

  ExercisesCompanion _exerciseFields(Exercise e) => ExercisesCompanion(
    updatedAt: Value(_now),
    name: Value(e.name.trim()),
    category: Value(e.category),
    muscleGroup: Value(e.muscleGroup.trim()),
    equipment: Value(e.equipment.trim()),
    instructions: Value(e.instructions?.trim().isEmpty ?? true ? null : e.instructions!.trim()),
    measurementKind: Value(e.measurementKind.code),
  );

  @override
  Future<Result<Exercise>> createExercise(Exercise draft) async {
    if (draft.problems.isNotEmpty) return Err(ValidationFailure('exercise', draft.problems.first));
    return Result.guard(() async {
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.exercises)
            .insert(
              _exerciseFields(draft)
                  .copyWith(id: Value(id), createdAt: Value(_now), isCustom: const Value(true)),
            );
        await _sync('exercises', id);
      });
      return Exercise(
        id: id,
        name: draft.name.trim(),
        category: draft.category,
        muscleGroup: draft.muscleGroup,
        equipment: draft.equipment,
        instructions: draft.instructions,
        isCustom: true,
        measurementKind: draft.measurementKind,
      );
    }, onError: (_) => const StorageFailure('exercise_write'));
  }

  @override
  Future<Result<void>> updateExercise(Exercise exercise) async {
    if (exercise.problems.isNotEmpty)
      return Err(ValidationFailure('exercise', exercise.problems.first));
    if (!exercise.isCustom) return const Err(ValidationFailure('exercise', 'not_custom'));
    return Result.guard(
      () => _db.transaction(() async {
        await (_db.update(
          _db.exercises,
        )..where((t) => t.id.equals(exercise.id))).write(_exerciseFields(exercise));
        await _sync('exercises', exercise.id);
      }),
      onError: (_) => const StorageFailure('exercise_write'),
    );
  }

  @override
  Future<Result<void>> archiveExercise(String id) => Result.guard(
    () => _db.transaction(() async {
      // Archived, not deleted: past workouts still name it.
      await (_db.update(_db.exercises)..where((t) => t.id.equals(id) & t.isCustom.equals(true)))
          .write(ExercisesCompanion(archived: const Value(true), updatedAt: Value(_now)));
      await _sync('exercises', id);
    }),
    onError: (_) => const StorageFailure('exercise_write'),
  );

  // ------------------------------------------------------------ sessions

  @override
  Future<Result<WorkoutSession>> logCardio({
    required WorkoutKind kind,
    required DateTime start,
    required DateTime end,
    required int distanceM,
    String? notes,
    List<RoutePoint> route = const [],
  }) async {
    final durationS = end.difference(start).inSeconds;
    final problems = cardioProblems(
      distanceM: distanceM,
      durationS: durationS,
      start: start,
      now: clock.now(),
    );
    if (kind == WorkoutKind.gym || problems.isNotEmpty) {
      return Err(ValidationFailure('workout', problems.isEmpty ? 'kind' : problems.first));
    }
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: start);
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.workoutSessions)
            .insert(
              WorkoutSessionsCompanion.insert(
                id: id,
                createdAt: stamp.nowUtc,
                updatedAt: stamp.nowUtc,
                kind: kind.code,
                name: kind.code,
                startedAt: start.toUtc(),
                endedAt: Value(end.toUtc()),
                durationS: durationS,
                localDate: stamp.localDate,
                tz: stamp.tz,
                distanceM: Value(distanceM),
                entryMode: route.isEmpty ? 'manual' : 'gps',
                hasRoute: Value(route.isNotEmpty),
                notes: Value(notes?.trim().isEmpty ?? true ? null : notes!.trim()),
              ),
            );
        for (final (i, p) in route.indexed) {
          await _db
              .into(_db.localWorkoutRoutePoints)
              .insert(
                LocalWorkoutRoutePointsCompanion.insert(
                  sessionId: id,
                  seq: i,
                  latE7: p.latE7,
                  lonE7: p.lonE7,
                  accuracyDm: Value(p.accuracyDm),
                  recordedAt: p.at.toUtc(),
                ),
              );
        }
        await _sync('workout_sessions', id);
      });
      return (await watchSession(id).first)!;
    }, onError: (_) => const StorageFailure('workout_write'));
  }

  @override
  Future<Result<String>> startGym({required String name, String? templateId}) =>
      Result.guard(() async {
        final stamp = await stampFor(clock, timeZone);
        final id = ids.newId();
        await _db.transaction(() async {
          await _db
              .into(_db.workoutSessions)
              .insert(
                WorkoutSessionsCompanion.insert(
                  id: id,
                  createdAt: stamp.nowUtc,
                  updatedAt: stamp.nowUtc,
                  kind: 'gym',
                  name: name.trim(),
                  startedAt: stamp.occurredAt,
                  durationS: 0,
                  localDate: stamp.localDate,
                  tz: stamp.tz,
                  entryMode: 'manual',
                  templateId: Value(templateId),
                ),
              );
          await _sync('workout_sessions', id);
          if (templateId != null) {
            final t = await (_db.select(
              _db.workoutTemplates,
            )..where((x) => x.id.equals(templateId))).getSingleOrNull();
            if (t != null) {
              for (final e in WorkoutTemplate.decode(t.exercises)) {
                final we = await _addExercise(id, e.exerciseId);
                for (final (i, s) in e.sets.indexed) {
                  await _insertSet(we, i + 1, (
                    reps: s.reps,
                    loadG: s.loadG,
                    entryUnit: 'kg',
                    distanceM: s.distanceM,
                    durationS: s.durationS,
                    restS: null,
                    done: false,
                  ));
                }
              }
              await (_db.update(_db.workoutTemplates)..where((x) => x.id.equals(templateId))).write(
                WorkoutTemplatesCompanion(
                  useCount: Value(t.useCount + 1),
                  lastUsedAt: Value(_now),
                  updatedAt: Value(_now),
                ),
              );
              await _sync('workout_templates', templateId);
            }
          }
        });
        return id;
      }, onError: (_) => const StorageFailure('workout_write'));

  @override
  Future<Result<void>> finishGym(String sessionId) => Result.guard(
    () => _db.transaction(() async {
      final s = await (_db.select(
        _db.workoutSessions,
      )..where((t) => t.id.equals(sessionId))).getSingle();
      final end = _now;
      final duration = end.difference(s.startedAt.toUtc()).inSeconds.clamp(0, 86400);
      await (_db.update(_db.workoutSessions)..where((t) => t.id.equals(sessionId))).write(
        WorkoutSessionsCompanion(
          endedAt: Value(end),
          durationS: Value(duration),
          updatedAt: Value(end),
        ),
      );
      await _sync('workout_sessions', sessionId);
    }),
    onError: (_) => const StorageFailure('workout_write'),
  );

  @override
  Future<Result<void>> updateSession(
    String id, {
    String? name,
    String? notes,
    DateTime? start,
    DateTime? end,
    int? distanceM,
  }) async {
    final s = await (_db.select(
      _db.workoutSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (s == null) return const Err(ValidationFailure('workout', 'not_found'));
    final newStart = (start ?? s.startedAt).toUtc();
    final newEnd = (end ?? s.endedAt)?.toUtc();
    final duration = newEnd == null ? s.durationS : newEnd.difference(newStart).inSeconds;
    if (newEnd != null && (duration <= 0 || duration > 86400))
      return const Err(ValidationFailure('workout', 'duration_required'));
    if (distanceM != null && (distanceM < 0 || distanceM > 500000)) {
      return const Err(ValidationFailure('workout', 'distance_out_of_range'));
    }
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: newStart);
      await _db.transaction(() async {
        await (_db.update(_db.workoutSessions)..where((t) => t.id.equals(id))).write(
          WorkoutSessionsCompanion(
            name: name == null ? const Value.absent() : Value(name.trim()),
            notes: notes == null
                ? const Value.absent()
                : Value(notes.trim().isEmpty ? null : notes.trim()),
            startedAt: Value(newStart),
            endedAt: Value(newEnd),
            durationS: Value(duration),
            localDate: Value(stamp.localDate),
            distanceM: distanceM == null ? const Value.absent() : Value(distanceM),
            updatedAt: Value(_now),
          ),
        );
        await _sync('workout_sessions', id);
      });
    }, onError: (_) => const StorageFailure('workout_write'));
  }

  @override
  Future<Result<void>> deleteSession(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = _now;
      final entries = await (_db.select(
        _db.workoutExercises,
      )..where((t) => t.sessionId.equals(id))).get();
      for (final e in entries) {
        final sets = await (_db.select(
          _db.exerciseSets,
        )..where((t) => t.workoutExerciseId.equals(e.id))).get();
        for (final s in sets) {
          await (_db.update(_db.exerciseSets)..where((t) => t.id.equals(s.id))).write(
            ExerciseSetsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
          );
          await _sync('exercise_sets', s.id);
        }
        await (_db.update(_db.workoutExercises)..where((t) => t.id.equals(e.id))).write(
          WorkoutExercisesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
        await _sync('workout_exercises', e.id);
      }
      await (_db.update(_db.workoutSessions)..where((t) => t.id.equals(id))).write(
        WorkoutSessionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await (_db.delete(_db.localWorkoutRoutePoints)..where((t) => t.sessionId.equals(id))).go();
      await _sync('workout_sessions', id);
    }),
    onError: (_) => const StorageFailure('workout_write'),
  );

  @override
  Future<Result<String>> duplicate(String sessionId) async {
    final source = await watchSession(sessionId).first;
    if (source == null || source.kind != WorkoutKind.gym)
      return const Err(ValidationFailure('workout', 'not_found'));
    final started = await startGym(name: source.name);
    final id = started.valueOrNull;
    if (id == null) return started;
    return Result.guard(() async {
      await _db.transaction(() async {
        for (final e in source.entries) {
          final we = await _addExercise(id, e.exercise.id);
          for (final s in e.sets) {
            await _insertSet(we, s.setNumber, (
              reps: s.reps,
              loadG: s.loadG,
              entryUnit: s.entryUnit,
              distanceM: s.distanceM,
              durationS: s.durationS,
              restS: s.restS,
              done: false,
            ));
          }
        }
      });
      return id;
    }, onError: (_) => const StorageFailure('workout_write'));
  }

  // ------------------------------------------------------------ exercises in a session

  Future<String> _addExercise(String sessionId, String exerciseId) async {
    final count = await (_db.select(
      _db.workoutExercises,
    )..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull())).get();
    final id = ids.newId();
    await _db
        .into(_db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            id: id,
            createdAt: _now,
            updatedAt: _now,
            sessionId: sessionId,
            exerciseId: exerciseId,
            sortOrder: Value(count.length),
          ),
        );
    await _sync('workout_exercises', id);
    return id;
  }

  @override
  Future<Result<String>> addExercise(String sessionId, String exerciseId) => Result.guard(
    () => _db.transaction(() => _addExercise(sessionId, exerciseId)),
    onError: (_) => const StorageFailure('workout_write'),
  );

  @override
  Future<Result<void>> removeExercise(String workoutExerciseId) => Result.guard(
    () => _db.transaction(() async {
      final now = _now;
      for (final s
          in await (_db.select(
                _db.exerciseSets,
              )..where((t) => t.workoutExerciseId.equals(workoutExerciseId) & t.deletedAt.isNull()))
              .get()) {
        await (_db.update(_db.exerciseSets)..where((t) => t.id.equals(s.id))).write(
          ExerciseSetsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
        );
        await _sync('exercise_sets', s.id);
      }
      await (_db.update(_db.workoutExercises)..where((t) => t.id.equals(workoutExerciseId))).write(
        WorkoutExercisesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await _sync('workout_exercises', workoutExerciseId);
    }),
    onError: (_) => const StorageFailure('workout_write'),
  );

  @override
  Future<Result<void>> reorderExercises(String sessionId, List<String> orderedIds) => Result.guard(
    () => _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        final n =
            await (_db.update(_db.workoutExercises)
                  ..where((t) => t.id.equals(orderedIds[i]) & t.sortOrder.equals(i).not()))
                .write(WorkoutExercisesCompanion(sortOrder: Value(i), updatedAt: Value(_now)));
        if (n > 0) await _sync('workout_exercises', orderedIds[i]);
      }
    }),
    onError: (_) => const StorageFailure('workout_write'),
  );

  Failure? _invalidSet(SetDraft d) {
    bool out(int? v, int max) => v != null && (v < 0 || v > max);
    if (out(d.reps, 1000) ||
        out(d.loadG, 1000000) ||
        out(d.distanceM, 500000) ||
        out(d.durationS, 86400) ||
        out(d.restS, 3600)) {
      return const ValidationFailure('set', 'out_of_range');
    }
    return null;
  }

  ExerciseSetsCompanion _setFields(SetDraft d, {DateTime? completedAt}) => ExerciseSetsCompanion(
    updatedAt: Value(_now),
    reps: Value(d.reps),
    loadG: Value(d.loadG),
    entryUnit: Value(d.loadG == null ? null : (d.entryUnit ?? 'kg')),
    distanceM: Value(d.distanceM),
    durationS: Value(d.durationS),
    restS: Value(d.restS),
    completedAt: Value(d.done ? (completedAt ?? _now) : null),
  );

  Future<String> _insertSet(String workoutExerciseId, int number, SetDraft d) async {
    final id = ids.newId();
    await _db
        .into(_db.exerciseSets)
        .insert(
          _setFields(d).copyWith(
            id: Value(id),
            createdAt: Value(_now),
            workoutExerciseId: Value(workoutExerciseId),
            setNumber: Value(number),
          ),
        );
    await _sync('exercise_sets', id);
    return id;
  }

  @override
  Future<Result<String>> addSet(String workoutExerciseId, SetDraft draft) async {
    final failure = _invalidSet(draft);
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final existing =
            await (_db.select(_db.exerciseSets)..where(
                  (t) => t.workoutExerciseId.equals(workoutExerciseId) & t.deletedAt.isNull(),
                ))
                .get();
        return _insertSet(workoutExerciseId, existing.length + 1, draft);
      }),
      onError: (_) => const StorageFailure('workout_write'),
    );
  }

  @override
  Future<Result<void>> updateSet(String setId, SetDraft draft) async {
    final failure = _invalidSet(draft);
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final current = await (_db.select(
          _db.exerciseSets,
        )..where((t) => t.id.equals(setId))).getSingle();
        await (_db.update(_db.exerciseSets)..where((t) => t.id.equals(setId))).write(
          _setFields(draft, completedAt: current.completedAt),
        );
        await _sync('exercise_sets', setId);
      }),
      onError: (_) => const StorageFailure('workout_write'),
    );
  }

  @override
  Future<Result<void>> removeSet(String setId) => Result.guard(
    () => _db.transaction(() async {
      final s = await (_db.select(_db.exerciseSets)..where((t) => t.id.equals(setId))).getSingle();
      await (_db.update(_db.exerciseSets)..where((t) => t.id.equals(setId))).write(
        ExerciseSetsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
      );
      await _sync('exercise_sets', setId);
      // Renumber the rest so set numbers stay 1, 2, 3…
      final rest =
          await (_db.select(_db.exerciseSets)
                ..where(
                  (t) => t.workoutExerciseId.equals(s.workoutExerciseId) & t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm(expression: t.setNumber)]))
              .get();
      for (final (i, r) in rest.indexed) {
        if (r.setNumber != i + 1) {
          await (_db.update(_db.exerciseSets)..where((t) => t.id.equals(r.id))).write(
            ExerciseSetsCompanion(setNumber: Value(i + 1), updatedAt: Value(_now)),
          );
          await _sync('exercise_sets', r.id);
        }
      }
    }),
    onError: (_) => const StorageFailure('workout_write'),
  );

  // ------------------------------------------------------------ reads

  Future<WorkoutSession> _assemble(WorkoutSessionRow r) async {
    final entries = <WorkoutEntry>[];
    if (r.kind == 'gym') {
      final rows =
          await (_db.select(_db.workoutExercises).join([
                  innerJoin(
                    _db.exercises,
                    _db.exercises.id.equalsExp(_db.workoutExercises.exerciseId),
                  ),
                ])
                ..where(
                  _db.workoutExercises.sessionId.equals(r.id) &
                      _db.workoutExercises.deletedAt.isNull(),
                )
                ..orderBy([OrderingTerm(expression: _db.workoutExercises.sortOrder)]))
              .get();
      for (final row in rows) {
        final we = row.readTable(_db.workoutExercises);
        final sets =
            await (_db.select(_db.exerciseSets)
                  ..where((t) => t.workoutExerciseId.equals(we.id) & t.deletedAt.isNull())
                  ..orderBy([(t) => OrderingTerm(expression: t.setNumber)]))
                .get();
        entries.add(
          WorkoutEntry(
            id: we.id,
            exercise: _toExercise(row.readTable(_db.exercises)),
            sets: [for (final s in sets) _toSet(s)],
            notes: we.notes,
          ),
        );
      }
    }
    return WorkoutSession(
      id: r.id,
      kind: WorkoutKind.fromCode(r.kind),
      name: r.name,
      startedAt: r.startedAt.toUtc(),
      endedAt: r.endedAt?.toUtc(),
      localDate: r.localDate,
      durationS: r.durationS,
      distanceM: r.distanceM,
      entryMode: r.entryMode,
      hasRoute: r.hasRoute,
      templateId: r.templateId,
      notes: r.notes,
      entries: entries,
    );
  }

  /// Any change to sessions, their exercises or sets refreshes the readers.
  Stream<void> get _changes => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.workoutSessions,
      _db.workoutExercises,
      _db.exerciseSets,
      _db.exercises,
    ]),
  );

  Stream<T> _live<T>(Future<T> Function() read) async* {
    yield await read();
    await for (final _ in _changes) {
      yield await read();
    }
  }

  @override
  Stream<List<WorkoutSession>> watchSessions({WorkoutKind? kind, int limit = 100}) =>
      _live(() async {
        final rows =
            await (_db.select(_db.workoutSessions)
                  ..where(
                    (t) =>
                        t.deletedAt.isNull() &
                        (kind == null ? const Constant(true) : t.kind.equals(kind.code)),
                  )
                  ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)])
                  ..limit(limit))
                .get();
        return [for (final r in rows) await _assemble(r)];
      });

  @override
  Stream<WorkoutSession?> watchSession(String id) => _live(() async {
    final r = await (_db.select(
      _db.workoutSessions,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return r == null ? null : await _assemble(r);
  });

  @override
  Stream<List<WorkoutSession>> watchBetween(LocalDate from, LocalDate to) => _live(() async {
    final rows =
        await (_db.select(_db.workoutSessions)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.localDate.isBetweenValues(from.toString(), to.toString()),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.startedAt)]))
            .get();
    return [for (final r in rows) await _assemble(r)];
  });

  // ------------------------------------------------------------ templates

  @override
  Future<Result<String>> saveTemplate(String sessionId, String name) async {
    if (name.trim().isEmpty) return const Err(ValidationFailure('template', 'name_required'));
    final s = await watchSession(sessionId).first;
    if (s == null) return const Err(ValidationFailure('template', 'not_found'));
    return Result.guard(() async {
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.workoutTemplates)
            .insert(
              WorkoutTemplatesCompanion.insert(
                id: id,
                createdAt: _now,
                updatedAt: _now,
                name: name.trim(),
                exercises: WorkoutTemplate.encode([
                  for (final e in s.entries)
                    (
                      exerciseId: e.exercise.id,
                      sets: [
                        for (final x in e.sets)
                          (
                            reps: x.reps,
                            loadG: x.loadG,
                            durationS: x.durationS,
                            distanceM: x.distanceM,
                          ),
                      ],
                    ),
                ]),
              ),
            );
        await _sync('workout_templates', id);
      });
      return id;
    }, onError: (_) => const StorageFailure('template_write'));
  }

  @override
  Stream<List<WorkoutTemplate>> watchTemplates() =>
      (_db.select(_db.workoutTemplates)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.name.collate(Collate.noCase))]))
          .watch()
          .map(
            (rows) => [
              for (final r in rows)
                WorkoutTemplate(
                  id: r.id,
                  name: r.name,
                  exercises: WorkoutTemplate.decode(r.exercises),
                  useCount: r.useCount,
                ),
            ],
          );

  @override
  Future<Result<void>> deleteTemplate(String id) => Result.guard(
    () => _db.transaction(() async {
      await (_db.update(_db.workoutTemplates)..where((t) => t.id.equals(id))).write(
        WorkoutTemplatesCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
      );
      await _sync('workout_templates', id);
    }),
    onError: (_) => const StorageFailure('template_write'),
  );

  // ------------------------------------------------------------ records and routes

  @override
  Future<List<({String sessionId, DateTime at, ExerciseSet set})>> completedSets(
    String exerciseId,
  ) async {
    final rows =
        await (_db.select(_db.exerciseSets).join([
                innerJoin(
                  _db.workoutExercises,
                  _db.workoutExercises.id.equalsExp(_db.exerciseSets.workoutExerciseId),
                ),
                innerJoin(
                  _db.workoutSessions,
                  _db.workoutSessions.id.equalsExp(_db.workoutExercises.sessionId),
                ),
              ])
              ..where(
                _db.workoutExercises.exerciseId.equals(exerciseId) &
                    _db.exerciseSets.completedAt.isNotNull() &
                    _db.exerciseSets.deletedAt.isNull() &
                    _db.workoutExercises.deletedAt.isNull() &
                    _db.workoutSessions.deletedAt.isNull(),
              )
              ..orderBy([OrderingTerm(expression: _db.exerciseSets.completedAt)]))
            .get();
    return [
      for (final r in rows)
        (
          sessionId: r.readTable(_db.workoutSessions).id,
          at: r.readTable(_db.exerciseSets).completedAt!.toUtc(),
          set: _toSet(r.readTable(_db.exerciseSets)),
        ),
    ];
  }

  @override
  Future<List<RoutePoint>> route(String sessionId) async => [
    for (final p
        in await (_db.select(_db.localWorkoutRoutePoints)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
            .get())
      (latE7: p.latE7, lonE7: p.lonE7, accuracyDm: p.accuracyDm, at: p.recordedAt.toUtc()),
  ];
}
