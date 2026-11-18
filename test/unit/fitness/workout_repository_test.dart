import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/errors/failure.dart';
import 'package:fitbuddy/features/fitness/data/drift_workout_repository.dart';
import 'package:fitbuddy/features/fitness/data/exercise_seed.dart';
import 'package:fitbuddy/features/fitness/domain/workouts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftWorkoutRepository repo;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 18, 30));
    repo = DriftWorkoutRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
  });
  tearDown(() => db.close());

  SetDraft set(int reps, int kg, {bool done = true}) => (
    reps: reps,
    loadG: kg * 1000,
    entryUnit: 'kg',
    distanceM: null,
    durationS: null,
    restS: 90,
    done: done,
  );

  test('the exercise list is seeded once, with the same ids on every phone', () async {
    await repo.seedExercises();
    await repo.seedExercises();
    final list = await repo.watchExercises().first;
    expect(list, hasLength(exerciseSeed.length));
    expect(
      list.firstWhere((e) => e.name == 'Bench press').id,
      DriftWorkoutRepository.seedId('bench_press'),
    );
    expect(
      DriftWorkoutRepository.seedId('bench_press'),
      DriftWorkoutRepository.seedId('bench_press'),
    );
  });

  test(
    'custom exercises can be created, edited and archived; seeded ones cannot be edited',
    () async {
      await repo.seedExercises();
      final mine = (await repo.createExercise(
        const Exercise(
          id: '',
          name: 'Cable fly',
          category: 'strength',
          muscleGroup: 'chest',
          equipment: 'cable',
          measurementKind: MeasurementKind.weightReps,
        ),
      )).valueOrNull!;
      expect(mine.isCustom, isTrue);
      final seeded = (await repo.watchExercises().first).firstWhere((e) => e.name == 'Squat');
      expect((await repo.updateExercise(seeded)).failureOrNull, isA<ValidationFailure>());
      await repo.archiveExercise(mine.id);
      expect((await repo.watchExercises().first).any((e) => e.id == mine.id), isFalse);
    },
  );

  test('a gym workout: exercises, sets, reorder, remove a set, finish', () async {
    await repo.seedExercises();
    final bench = DriftWorkoutRepository.seedId('bench_press');
    final ohp = DriftWorkoutRepository.seedId('overhead_press');
    final id = (await repo.startGym(name: 'Push day')).valueOrNull!;
    final a = (await repo.addExercise(id, bench)).valueOrNull!;
    final b = (await repo.addExercise(id, ohp)).valueOrNull!;
    await repo.addSet(a, set(12, 40));
    final second = (await repo.addSet(a, set(10, 40))).valueOrNull!;
    await repo.addSet(a, set(8, 45));
    await repo.removeSet(second);
    await repo.reorderExercises(id, [b, a]);
    time.now = time.now.add(const Duration(minutes: 48));
    await repo.finishGym(id);
    final s = (await repo.watchSession(id).first)!;
    expect(s.entries.map((e) => e.exercise.name), ['Overhead press', 'Bench press']);
    expect(s.entries.last.sets.map((x) => (x.setNumber, x.reps)), [(1, 12), (2, 8)]);
    expect(s.durationS, 48 * 60);
    expect(s.inProgress, isFalse);
    expect(s.setCount, 2);
  });

  test(
    'duplicate copies exercises and sets as not yet done; templates start new workouts',
    () async {
      await repo.seedExercises();
      final id = (await repo.startGym(name: 'Legs')).valueOrNull!;
      final we = (await repo.addExercise(id, DriftWorkoutRepository.seedId('squat'))).valueOrNull!;
      await repo.addSet(we, set(5, 60));
      await repo.finishGym(id);
      final copy = (await repo.duplicate(id)).valueOrNull!;
      final c = (await repo.watchSession(copy).first)!;
      expect(c.entries.single.sets.single.loadG, 60000);
      expect(c.entries.single.sets.single.done, isFalse);
      final t = (await repo.saveTemplate(id, 'Leg day')).valueOrNull!;
      final fromTemplate = (await repo.startGym(name: 'Leg day', templateId: t)).valueOrNull!;
      final f = (await repo.watchSession(fromTemplate).first)!;
      expect(f.entries.single.exercise.name, 'Squat');
      expect((await repo.watchTemplates().first).single.useCount, 1);
    },
  );

  test('cardio by hand, with checks; a GPS route stays local', () async {
    final start = DateTime(2026, 11, 16, 6, 40);
    final run = (await repo.logCardio(
      kind: WorkoutKind.run,
      start: start,
      end: start.add(const Duration(minutes: 32)),
      distanceM: 5200,
      route: [(latE7: 129716000, lonE7: 775946000, accuracyDm: 50, at: start.toUtc())],
    )).valueOrNull!;
    expect(run.entryMode, 'gps');
    expect(run.hasRoute, isTrue);
    expect(await repo.route(run.id), hasLength(1));
    final bad = await repo.logCardio(
      kind: WorkoutKind.walk,
      start: start,
      end: start,
      distanceM: 100,
    );
    expect(bad.failureOrNull, isA<ValidationFailure>());
    final outbox = {for (final r in await db.select(db.syncOutbox).get()) r.entityTable};
    expect(outbox.contains('local_workout_route_points'), isFalse);
  });

  test('deleting a workout removes it with its sets', () async {
    await repo.seedExercises();
    final id = (await repo.startGym(name: 'x')).valueOrNull!;
    final we = (await repo.addExercise(id, DriftWorkoutRepository.seedId('squat'))).valueOrNull!;
    await repo.addSet(we, set(5, 60));
    await repo.deleteSession(id);
    expect(await repo.watchSessions().first, isEmpty);
    expect(await repo.completedSets(DriftWorkoutRepository.seedId('squat')), isEmpty);
  });

  test('completed sets for records come oldest first', () async {
    await repo.seedExercises();
    final bench = DriftWorkoutRepository.seedId('bench_press');
    final id = (await repo.startGym(name: 'x')).valueOrNull!;
    final we = (await repo.addExercise(id, bench)).valueOrNull!;
    await repo.addSet(we, set(12, 40));
    time.now = time.now.add(const Duration(minutes: 3));
    await repo.addSet(we, set(8, 45));
    await repo.addSet(we, set(6, 50, done: false));
    final sets = await repo.completedSets(bench);
    expect(sets.map((s) => s.set.loadG), [40000, 45000]);
  });
}
