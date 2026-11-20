import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/profile/data/drift_goals_repository.dart';
import 'package:fitbuddy/features/profile/domain/goals.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftGoalsRepository goals;

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 9));
    goals = DriftGoalsRepository(db, clock: time.clock, ids: SequentialIds());
  });
  tearDown(() => db.close());

  test('no goals before any are saved', () async {
    expect(await goals.dailyGoalsOn(LocalDate(2026, 11, 16)), isNull);
    expect(await goals.nutritionGoalsOn(LocalDate(2026, 11, 16)), isNull);
  });

  test('a goal change does not alter how earlier days are judged', () async {
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 8000, dailyWaterMl: 2500));
    time.now = DateTime(2026, 11, 20, 9);
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 10000, dailyWaterMl: 3000));

    expect((await goals.dailyGoalsOn(LocalDate(2026, 11, 18)))!.dailySteps, 8000);
    expect((await goals.dailyGoalsOn(LocalDate(2026, 11, 20)))!.dailySteps, 10000);
    expect((await goals.dailyGoalsOn(LocalDate(2026, 12, 1)))!.dailyWaterMl, 3000);
    expect(await goals.dailyGoalsOn(LocalDate(2026, 11, 15)), isNull);
  });

  test('editing goals twice on one day keeps a single row for that day', () async {
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 8000));
    time.now = DateTime(2026, 11, 16, 21);
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 9000));

    final rows = await db.select(db.userGoals).get();
    expect(rows, hasLength(1));
    expect(rows.single.dailySteps, 9000);
  });

  test('every save queues the row for sync, once', () async {
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 8000));
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 9000));
    await goals.saveNutritionGoals(const NutritionTargets(proteinMg: 120000));
    expect(await outboxEntries(db), [
      (table: 'user_goals', id: 'id-1'),
      (table: 'nutrition_goals', id: 'id-2'),
    ]);
  });

  test('nutrition goals are optional field by field and effective-dated', () async {
    await goals.saveNutritionGoals(const NutritionTargets(proteinMg: 120000));
    final today = await goals.nutritionGoalsOn(LocalDate(2026, 11, 16));
    expect(today!.proteinMg, 120000);
    expect(today.energyKcalMilli, isNull);
  });

  test('rejects negative and impossible targets without writing', () async {
    final result = await goals.saveDailyGoals(const DailyGoals(dailySteps: -5));
    expect(result.failureOrNull?.code, 'out_of_range');
    final sleep = await goals.saveDailyGoals(const DailyGoals(sleepTargetMin: 2000));
    expect(sleep.failureOrNull?.code, 'out_of_range');
    expect(await db.select(db.userGoals).get(), isEmpty);
    expect(await outboxEntries(db), isEmpty);
  });

  test('watching current goals emits after a save', () async {
    final stream = goals.watchCurrentDailyGoals();
    final expectation = expectLater(
      stream,
      emitsInOrder([isNull, predicate<DailyGoals?>((g) => g?.dailySteps == 8000)]),
    );
    await Future<void>.delayed(Duration.zero);
    await goals.saveDailyGoals(const DailyGoals(dailySteps: 8000));
    await expectation;
  });
}
