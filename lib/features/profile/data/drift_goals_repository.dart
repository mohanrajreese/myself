import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/goals.dart';
import '../domain/goals_repository.dart';

final class DriftGoalsRepository implements GoalsRepository {
  DriftGoalsRepository(this._db, {required Clock clock, required IdGenerator ids}) : _clock = clock, _ids = ids;

  final AppDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;

  LocalDate get _today => LocalDate.fromDateTime(_clock.now());

  SimpleSelectStatement<$UserGoalsTable, UserGoalRow> _dailyOn(LocalDate date) => _db.select(_db.userGoals)
    ..where((t) => t.effectiveFrom.isSmallerOrEqualValue(date.toString()) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.desc(t.effectiveFrom)])
    ..limit(1);

  SimpleSelectStatement<$NutritionGoalsTable, NutritionGoalRow> _nutritionOn(LocalDate date) =>
      _db.select(_db.nutritionGoals)
        ..where((t) => t.effectiveFrom.isSmallerOrEqualValue(date.toString()) & t.deletedAt.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.effectiveFrom)])
        ..limit(1);

  @override
  Future<DailyGoals?> dailyGoalsOn(LocalDate date) async => _daily(await _dailyOn(date).getSingleOrNull());

  @override
  Future<NutritionTargets?> nutritionGoalsOn(LocalDate date) async =>
      _nutrition(await _nutritionOn(date).getSingleOrNull());

  @override
  Stream<DailyGoals?> watchCurrentDailyGoals() => _dailyOn(_today).watchSingleOrNull().map(_daily);

  @override
  Stream<NutritionTargets?> watchCurrentNutritionGoals() => _nutritionOn(_today).watchSingleOrNull().map(_nutrition);

  @override
  Future<Result<void>> saveDailyGoals(DailyGoals goals) async {
    final failure = goals.validate();
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final now = _clock.now().toUtc();
        final today = _today;
        final existing = await (_db.select(
          _db.userGoals,
        )..where((t) => t.effectiveFrom.equalsValue(today) & t.deletedAt.isNull())).getSingleOrNull();
        final id = existing?.id ?? _ids.newId();
        await _db
            .into(_db.userGoals)
            .insertOnConflictUpdate(
              UserGoalsCompanion.insert(
                id: id,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                effectiveFrom: today,
                targetWeightG: Value(goals.targetWeightG),
                dailySteps: Value(goals.dailySteps),
                dailyWaterMl: Value(goals.dailyWaterMl),
                sleepTargetMin: Value(goals.sleepTargetMin),
                fitnessGoals: Value(jsonEncode(goals.fitnessGoals.map((g) => g.trim()).toList())),
              ),
            );
        await _db.enqueueForSync('user_goals', id, now);
      }),
      onError: (_) => const StorageFailure('goals_write'),
    );
  }

  @override
  Future<Result<void>> saveNutritionGoals(NutritionTargets goals) async {
    final failure = goals.validate();
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final now = _clock.now().toUtc();
        final today = _today;
        final existing = await (_db.select(
          _db.nutritionGoals,
        )..where((t) => t.effectiveFrom.equalsValue(today) & t.deletedAt.isNull())).getSingleOrNull();
        final id = existing?.id ?? _ids.newId();
        await _db
            .into(_db.nutritionGoals)
            .insertOnConflictUpdate(
              NutritionGoalsCompanion.insert(
                id: id,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                effectiveFrom: today,
                energyKcalMilli: Value(goals.energyKcalMilli),
                proteinMg: Value(goals.proteinMg),
                carbsMg: Value(goals.carbsMg),
                fatMg: Value(goals.fatMg),
                fibreMg: Value(goals.fibreMg),
              ),
            );
        await _db.enqueueForSync('nutrition_goals', id, now);
      }),
      onError: (_) => const StorageFailure('goals_write'),
    );
  }

  DailyGoals? _daily(UserGoalRow? row) => row == null
      ? null
      : DailyGoals(
          targetWeightG: row.targetWeightG,
          dailySteps: row.dailySteps,
          dailyWaterMl: row.dailyWaterMl,
          sleepTargetMin: row.sleepTargetMin,
          fitnessGoals: (jsonDecode(row.fitnessGoals) as List<Object?>).cast<String>(),
        );

  NutritionTargets? _nutrition(NutritionGoalRow? row) => row == null
      ? null
      : NutritionTargets(
          energyKcalMilli: row.energyKcalMilli,
          proteinMg: row.proteinMg,
          carbsMg: row.carbsMg,
          fatMg: row.fatMg,
          fibreMg: row.fibreMg,
        );
}
