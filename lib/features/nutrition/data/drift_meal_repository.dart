import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/log_stamp.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/platform/time_zone_source.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../../core/utils/local_date.dart';
import '../domain/meals.dart';
import '../domain/nutrition_math.dart';

final class DriftMealRepository implements MealRepository {
  DriftMealRepository(this._db, {required this.clock, required this.ids, required this.timeZone});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;
  final TimeZoneSource timeZone;

  static const _meals = 'meal_logs';
  static const _items = 'meal_food_items';
  static const _saved = 'saved_meals';

  String? _clean(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

  MealItem _item(MealFoodItemRow r) => MealItem(
    foodItemId: r.foodItemId,
    foodName: r.foodName,
    quantityMilli: r.quantityMilli,
    unit: r.unit,
    servingWeightMg: r.servingWeightMg,
    values: NutritionValues(
      energyKcalMilli: r.energyKcalMilli,
      proteinMg: r.proteinMg,
      carbsMg: r.carbsMg,
      fatMg: r.fatMg,
      fibreMg: r.fibreMg,
    ),
    junk: JunkCategory.fromCode(r.junkCategory),
    notes: r.itemNotes,
  );

  Future<void> _insertItems(String mealId, List<MealItem> items, DateTime now) async {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final id = ids.newId();
      await _db
          .into(_db.mealFoodItems)
          .insert(
            MealFoodItemsCompanion.insert(
              id: id,
              createdAt: now,
              updatedAt: now,
              mealLogId: mealId,
              foodItemId: Value(item.foodItemId),
              foodName: item.foodName.trim(),
              quantityMilli: item.quantityMilli,
              unit: item.unit,
              servingWeightMg: Value(item.servingWeightMg),
              energyKcalMilli: item.values.energyKcalMilli,
              proteinMg: item.values.proteinMg,
              carbsMg: item.values.carbsMg,
              fatMg: item.values.fatMg,
              fibreMg: item.values.fibreMg,
              junkCategory: Value(item.junk?.code),
              itemNotes: Value(_clean(item.notes)),
              sortOrder: Value(i),
            ),
          );
      await _db.enqueueForSync(_items, id, now);
    }
  }

  /// Tombstones every live item of a meal.
  Future<void> _removeItems(String mealId, DateTime now) async {
    final live = await (_db.select(
      _db.mealFoodItems,
    )..where((t) => t.mealLogId.equals(mealId) & t.deletedAt.isNull())).get();
    for (final row in live) {
      await (_db.update(_db.mealFoodItems)..where((t) => t.id.equals(row.id))).write(
        MealFoodItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await _db.enqueueForSync(_items, row.id, now);
    }
  }

  Future<Meal?> _load(String id) async {
    final row = await (_db.select(
      _db.mealLogs,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return null;
    return (await _assemble([row])).single;
  }

  Future<List<Meal>> _assemble(List<MealLogRow> rows) async {
    if (rows.isEmpty) return const [];
    final items =
        await (_db.select(_db.mealFoodItems)
              ..where((t) => t.mealLogId.isIn(rows.map((r) => r.id)) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
    final byMeal = <String, List<MealItem>>{};
    for (final item in items) {
      byMeal.putIfAbsent(item.mealLogId, () => []).add(_item(item));
    }
    return [
      for (final r in rows)
        Meal(
          id: r.id,
          category: MealCategory.fromCode(r.mealCategory),
          occurredAt: r.occurredAt,
          localDate: r.localDate,
          items: byMeal[r.id] ?? const [],
          notes: r.notes,
          hasPhoto: r.hasPhoto,
        ),
    ];
  }

  @override
  Future<Result<Meal>> add(MealDraft draft) async {
    final failure = draft.validate();
    if (failure != null) return Err(failure);
    if (draft.at != null && draft.at!.isAfter(clock.now())) {
      return const Err(ValidationFailure('occurredAt', 'in_future'));
    }
    return Result.guard(() async {
      final stamp = await stampFor(clock, timeZone, at: draft.at);
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.mealLogs)
            .insert(
              MealLogsCompanion.insert(
                id: id,
                createdAt: stamp.nowUtc,
                updatedAt: stamp.nowUtc,
                mealCategory: draft.category.code,
                occurredAt: stamp.occurredAt,
                localDate: stamp.localDate,
                tz: stamp.tz,
                notes: Value(_clean(draft.notes)),
              ),
            );
        await _db.enqueueForSync(_meals, id, stamp.nowUtc);
        await _insertItems(id, draft.items, stamp.nowUtc);
      });
      return (await _load(id))!;
    }, onError: (_) => const StorageFailure('meal_write'));
  }

  @override
  Future<Result<void>> update(String id, MealDraft draft) async {
    final failure = draft.validate();
    if (failure != null) return Err(failure);
    return Result.guard(
      () => _db.transaction(() async {
        final now = clock.now().toUtc();
        final at = draft.at;
        final changed =
            await (_db.update(
              _db.mealLogs,
            )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(
              MealLogsCompanion(
                mealCategory: Value(draft.category.code),
                notes: Value(_clean(draft.notes)),
                occurredAt: at == null ? const Value.absent() : Value(at.toUtc()),
                localDate: at == null
                    ? const Value.absent()
                    : Value(LocalDate.fromDateTime(at.toLocal())),
                updatedAt: Value(now),
              ),
            );
        if (changed == 0) throw StateError('missing');
        await _db.enqueueForSync(_meals, id, now);
        await _removeItems(id, now);
        await _insertItems(id, draft.items, now);
      }),
      onError: (_) => const StorageFailure('meal_write'),
    );
  }

  @override
  Future<Result<void>> delete(String id) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed =
          await (_db.update(_db.mealLogs)..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
              .write(MealLogsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed == 0) return;
      await _db.enqueueForSync(_meals, id, now);
      await _removeItems(id, now);
    }),
    onError: (_) => const StorageFailure('meal_write'),
  );

  @override
  Future<Result<Meal>> duplicate(String id, {DateTime? at}) async {
    final meal = await _load(id);
    if (meal == null) return const Err(StorageFailure('meal_missing'));
    return add(MealDraft(category: meal.category, items: meal.items, at: at, notes: meal.notes));
  }

  @override
  Stream<List<Meal>> watchOn(LocalDate date) =>
      (_db.select(_db.mealLogs)
            ..where((t) => t.localDate.equalsValue(date) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
          .watch()
          .combineWithItems(_db, _assemble);

  @override
  Future<Map<LocalDate, NutritionValues>> totalsBetween(LocalDate from, LocalDate to) async {
    final rows = await _db
        .customSelect(
          'SELECT m.local_date AS d, sum(i.energy_kcal_milli) AS kcal, sum(i.protein_mg) AS p, '
          'sum(i.carbs_mg) AS c, sum(i.fat_mg) AS f, sum(i.fibre_mg) AS fi '
          'FROM meal_logs m JOIN meal_food_items i ON i.meal_log_id = m.id '
          'WHERE m.deleted_at IS NULL AND i.deleted_at IS NULL AND m.local_date BETWEEN ? AND ? '
          'GROUP BY m.local_date',
          variables: [Variable.withString(from.toString()), Variable.withString(to.toString())],
          readsFrom: {_db.mealLogs, _db.mealFoodItems},
        )
        .get();
    return {
      for (final r in rows)
        LocalDate.parse(r.read<String>('d')): NutritionValues(
          energyKcalMilli: r.read<int>('kcal'),
          proteinMg: r.read<int>('p'),
          carbsMg: r.read<int>('c'),
          fatMg: r.read<int>('f'),
          fibreMg: r.read<int>('fi'),
        ),
    };
  }

  @override
  Future<List<JunkEntry>> junkBetween(LocalDate from, LocalDate to) async {
    final query =
        _db.select(_db.mealFoodItems).join([
            innerJoin(_db.mealLogs, _db.mealLogs.id.equalsExp(_db.mealFoodItems.mealLogId)),
          ])
          ..where(
            _db.mealFoodItems.junkCategory.isNotNull() &
                _db.mealFoodItems.deletedAt.isNull() &
                _db.mealLogs.deletedAt.isNull() &
                _db.mealLogs.localDate.isBiggerOrEqualValue(from.toString()) &
                _db.mealLogs.localDate.isSmallerOrEqualValue(to.toString()),
          )
          ..orderBy([OrderingTerm.desc(_db.mealLogs.occurredAt)]);
    return [
      for (final row in await query.get())
        (
          foodName: row.readTable(_db.mealFoodItems).foodName,
          category: JunkCategory.fromCode(row.readTable(_db.mealFoodItems).junkCategory)!,
          values: _item(row.readTable(_db.mealFoodItems)).values,
          date: row.readTable(_db.mealLogs).localDate,
          at: row.readTable(_db.mealLogs).occurredAt,
        ),
    ];
  }

  @override
  Future<void> setHasPhoto(String id, bool hasPhoto) => _db.transaction(() async {
    final now = clock.now().toUtc();
    final changed = await (_db.update(_db.mealLogs)..where((t) => t.id.equals(id))).write(
      MealLogsCompanion(hasPhoto: Value(hasPhoto), updatedAt: Value(now)),
    );
    if (changed > 0) await _db.enqueueForSync(_meals, id, now);
  });

  SavedMeal _savedMeal(SavedMealRow r) => SavedMeal(
    id: r.id,
    name: r.name,
    category: r.mealCategory == null ? null : MealCategory.fromCode(r.mealCategory!),
    items: [
      for (final j in (jsonDecode(r.items) as List<Object?>).cast<Map<String, Object?>>())
        MealItem.fromJson(j),
    ],
    useCount: r.useCount,
  );

  @override
  Future<Result<SavedMeal>> saveAsTemplate(String mealId, String name) async {
    if (name.trim().isEmpty) return const Err(ValidationFailure('name', 'required'));
    final meal = await _load(mealId);
    if (meal == null) return const Err(StorageFailure('meal_missing'));
    return Result.guard(() async {
      final now = clock.now().toUtc();
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.savedMeals)
            .insert(
              SavedMealsCompanion.insert(
                id: id,
                createdAt: now,
                updatedAt: now,
                name: name.trim(),
                mealCategory: Value(meal.category.code),
                items: jsonEncode([for (final i in meal.items) i.toJson()]),
              ),
            );
        await _db.enqueueForSync(_saved, id, now);
      });
      return _savedMeal(
        await (_db.select(_db.savedMeals)..where((t) => t.id.equals(id))).getSingle(),
      );
    }, onError: (_) => const StorageFailure('saved_meal_write'));
  }

  @override
  Future<Result<Meal>> logSaved(String savedMealId, {MealCategory? category, DateTime? at}) async {
    final row = await (_db.select(
      _db.savedMeals,
    )..where((t) => t.id.equals(savedMealId) & t.deletedAt.isNull())).getSingleOrNull();
    if (row == null) return const Err(StorageFailure('saved_meal_missing'));
    final saved = _savedMeal(row);
    final wall = at ?? clock.now();
    final result = await add(
      MealDraft(
        category: category ?? saved.category ?? mealCategoryForTime(wall.hour, wall.minute),
        items: saved.items,
        at: at,
      ),
    );
    if (result.isOk) {
      final now = clock.now().toUtc();
      await _db.transaction(() async {
        await (_db.update(_db.savedMeals)..where((t) => t.id.equals(savedMealId))).write(
          SavedMealsCompanion(
            useCount: Value(row.useCount + 1),
            lastUsedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        await _db.enqueueForSync(_saved, savedMealId, now);
      });
    }
    return result;
  }

  @override
  Future<Result<void>> deleteSaved(String savedMealId) => Result.guard(
    () => _db.transaction(() async {
      final now = clock.now().toUtc();
      final changed =
          await (_db.update(_db.savedMeals)
                ..where((t) => t.id.equals(savedMealId) & t.deletedAt.isNull()))
              .write(SavedMealsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
      if (changed > 0) await _db.enqueueForSync(_saved, savedMealId, now);
    }),
    onError: (_) => const StorageFailure('saved_meal_write'),
  );

  @override
  Stream<List<SavedMeal>> watchSaved() =>
      (_db.select(_db.savedMeals)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.useCount), (t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map((rows) => rows.map(_savedMeal).toList());
}

extension on Stream<List<MealLogRow>> {
  /// Re-reads items whenever meals or items change.
  Stream<List<Meal>> combineWithItems(
    AppDatabase db,
    Future<List<Meal>> Function(List<MealLogRow>) assemble,
  ) {
    final itemChanges = db.tableUpdates(TableUpdateQuery.onTable(db.mealFoodItems));
    late List<MealLogRow> latest;
    return Stream<Future<List<Meal>>>.multi((controller) {
      var started = false;
      final mealSub = listen((rows) {
        latest = rows;
        started = true;
        controller.add(assemble(rows));
      }, onError: controller.addError);
      final itemSub = itemChanges.listen((_) {
        if (started) controller.add(assemble(latest));
      });
      controller.onCancel = () async {
        await mealSub.cancel();
        await itemSub.cancel();
      };
    }).asyncMap((future) => future);
  }
}
