import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/outbox.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../nutrition/domain/nutrition_math.dart';
import '../domain/food.dart';

final class DriftFoodRepository implements FoodRepository {
  DriftFoodRepository(this._db, {required this.clock, required this.ids});

  final AppDatabase _db;
  final Clock clock;
  final IdGenerator ids;

  static const _table = 'food_items';

  Food _mine(FoodItemRow r) => Food(
    id: r.id,
    name: r.name,
    brand: r.brand,
    category: r.category,
    servingLabel: r.servingLabel,
    servingQtyMilli: r.servingQtyMilli,
    servingUnit: r.servingUnit,
    servingWeightMg: r.servingWeightMg,
    values: NutritionValues(
      energyKcalMilli: r.energyKcalMilli,
      proteinMg: r.proteinMg,
      carbsMg: r.carbsMg,
      fatMg: r.fatMg,
      fibreMg: r.fibreMg,
    ),
    junk: JunkCategory.fromCode(r.junkCategory),
    source: FoodSources.mine,
    isSaved: r.isSaved,
    useCount: r.useCount,
    catalogueRef: r.catalogueRef,
  );

  Food _catalogue(CatalogueFoodRow r) => Food(
    id: r.id,
    name: r.name,
    category: r.category,
    servingLabel: r.servingLabel,
    // Catalogue values are per 100 g: quantity in thousandths of a gram.
    servingQtyMilli: r.servingWeightMg,
    servingUnit: 'g',
    servingWeightMg: r.servingWeightMg,
    values: NutritionValues(
      energyKcalMilli: r.energyKcalMilli,
      proteinMg: r.proteinMg,
      carbsMg: r.carbsMg,
      fatMg: r.fatMg,
      fibreMg: r.fibreMg,
    ),
    source: r.source,
    isEstimate: r.isEstimate,
    householdLabel: r.householdLabel,
    householdWeightMg: r.householdWeightMg,
    hasConflict: r.hasConflict,
  );

  FoodItemsCompanion _fields(FoodDraft d, DateTime now) => FoodItemsCompanion(
    name: Value(d.name.trim()),
    brand: Value(d.brand == null || d.brand!.trim().isEmpty ? null : d.brand!.trim()),
    category: Value(d.category),
    servingLabel: Value(d.servingLabel.trim()),
    servingQtyMilli: Value(d.servingQtyMilli),
    servingUnit: Value(d.servingUnit),
    servingWeightMg: Value(d.servingWeightMg),
    energyKcalMilli: Value(d.values.energyKcalMilli),
    proteinMg: Value(d.values.proteinMg),
    carbsMg: Value(d.values.carbsMg),
    fatMg: Value(d.values.fatMg),
    fibreMg: Value(d.values.fibreMg),
    junkCategory: Value(d.junk?.code),
    isSaved: Value(d.isSaved),
    updatedAt: Value(now),
  );

  @override
  Future<Result<Food>> create(FoodDraft draft) async {
    final failure = draft.validate();
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final now = clock.now().toUtc();
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.foodItems)
            .insert(_fields(draft, now).copyWith(id: Value(id), createdAt: Value(now)));
        await _db.enqueueForSync(_table, id, now);
      });
      return _mine(await (_db.select(_db.foodItems)..where((t) => t.id.equals(id))).getSingle());
    }, onError: (_) => const StorageFailure('food_write'));
  }

  @override
  Future<Result<void>> update(String id, FoodDraft draft) async {
    final failure = draft.validate();
    if (failure != null) return Err(failure);
    return _write(id, (now) => _fields(draft, now));
  }

  @override
  Future<Result<void>> setSaved(String id, bool saved) =>
      _write(id, (now) => FoodItemsCompanion(isSaved: Value(saved), updatedAt: Value(now)));

  @override
  Future<Result<void>> delete(String id) =>
      _write(id, (now) => FoodItemsCompanion(deletedAt: Value(now), updatedAt: Value(now)));

  Future<Result<void>> _write(String id, FoodItemsCompanion Function(DateTime now) change) =>
      Result.guard(
        () => _db.transaction(() async {
          final now = clock.now().toUtc();
          final changed = await (_db.update(
            _db.foodItems,
          )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).write(change(now));
          if (changed == 0) throw StateError('missing');
          await _db.enqueueForSync(_table, id, now);
        }),
        onError: (_) => const StorageFailure('food_write'),
      );

  Future<FoodItemRow?> _copyOf(String catalogueId) =>
      (_db.select(_db.foodItems)
            ..where((t) => t.catalogueRef.equals(catalogueId) & t.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  Future<Result<Food>> _createCopy(String catalogueId, FoodDraft draft) async {
    final failure = draft.validate();
    if (failure != null) return Err(failure);
    return Result.guard(() async {
      final now = clock.now().toUtc();
      final id = ids.newId();
      await _db.transaction(() async {
        await _db
            .into(_db.foodItems)
            .insert(
              _fields(
                draft,
                now,
              ).copyWith(id: Value(id), createdAt: Value(now), catalogueRef: Value(catalogueId)),
            );
        await _db.enqueueForSync(_table, id, now);
      });
      return _mine(await (_db.select(_db.foodItems)..where((t) => t.id.equals(id))).getSingle());
    }, onError: (_) => const StorageFailure('food_write'));
  }

  @override
  Future<Result<Food>> adopt(Food catalogueFood) async {
    if (catalogueFood.isMine) return Ok(catalogueFood);
    final existing = await _copyOf(catalogueFood.id);
    if (existing != null) return Ok(_mine(existing));
    return _createCopy(catalogueFood.id, FoodDraft.from(catalogueFood));
  }

  @override
  Future<Result<Food>> edit(Food food, FoodDraft draft) async {
    if (food.isMine) {
      final result = await update(food.id, draft);
      if (!result.isOk) return Err(result.failureOrNull!);
      return Ok(
        _mine(await (_db.select(_db.foodItems)..where((t) => t.id.equals(food.id))).getSingle()),
      );
    }
    final existing = await _copyOf(food.id);
    if (existing == null) return _createCopy(food.id, draft);
    final result = await update(existing.id, draft);
    if (!result.isOk) return Err(result.failureOrNull!);
    return Ok(
      _mine(await (_db.select(_db.foodItems)..where((t) => t.id.equals(existing.id))).getSingle()),
    );
  }

  @override
  Future<void> markUsed(String id, DateTime at) => _db.transaction(() async {
    final now = clock.now().toUtc();
    final changed = await _db.customUpdate(
      'UPDATE food_items SET use_count = use_count + 1, last_used_at = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      variables: [
        Variable.withDateTime(at.toUtc()),
        Variable.withDateTime(now),
        Variable.withString(id),
      ],
      updates: {_db.foodItems},
    );
    if (changed > 0) await _db.enqueueForSync(_table, id, now);
  });

  @override
  Future<List<Food>> search(
    String query, {
    FoodFilter filter = FoodFilter.all,
    int limit = 50,
  }) async {
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    Expression<bool> matches(GeneratedColumn<String> name) => words.fold<Expression<bool>>(
      const Constant(true),
      (all, word) => all & name.lower().like('%${_escape(word)}%', escapeChar: r'\'),
    );

    final mineQuery = _db.select(_db.foodItems)
      ..where((t) {
        var where = t.deletedAt.isNull() & matches(t.name);
        if (filter == FoodFilter.saved) where = where & t.isSaved.equals(true);
        if (filter == FoodFilter.recent) where = where & t.lastUsedAt.isNotNull();
        return where;
      })
      ..orderBy([
        (t) => filter == FoodFilter.recent
            ? OrderingTerm.desc(t.lastUsedAt)
            : OrderingTerm.desc(t.useCount),
        (t) => OrderingTerm.asc(t.name),
      ])
      ..limit(limit);
    final mine = (await mineQuery.get()).map(_mine).toList();

    if (filter != FoodFilter.all || words.isEmpty || mine.length >= limit) return mine;

    // Catalogue foods the user has their own copy of are shown as that copy.
    final replaced = _db.selectOnly(_db.foodItems)
      ..addColumns([_db.foodItems.catalogueRef])
      ..where(_db.foodItems.catalogueRef.isNotNull() & _db.foodItems.deletedAt.isNull());
    final catalogue =
        await (_db.select(_db.localFoodCatalogue)
              ..where((t) => matches(t.name) & t.id.isNotInQuery(replaced))
              ..orderBy([(t) => OrderingTerm.asc(t.name.length), (t) => OrderingTerm.asc(t.name)])
              ..limit(limit - mine.length))
            .get();
    return [...mine, ...catalogue.map(_catalogue)];
  }

  static String _escape(String word) =>
      word.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
