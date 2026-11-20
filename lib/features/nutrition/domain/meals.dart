import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';
import 'nutrition_math.dart';

/// One food in a meal, with values for the quantity eaten (a snapshot).
@immutable
final class MealItem {
  const MealItem({
    required this.foodName,
    required this.quantityMilli,
    required this.unit,
    required this.values,
    this.foodItemId,
    this.servingWeightMg,
    this.junk,
    this.notes,
  });

  final String? foodItemId;
  final String foodName;
  final int quantityMilli;
  final String unit;
  final int? servingWeightMg;
  final NutritionValues values;
  final JunkCategory? junk;
  final String? notes;

  Map<String, Object?> toJson() => {
    'food_item_id': foodItemId,
    'food_name': foodName,
    'quantity_milli': quantityMilli,
    'unit': unit,
    'serving_weight_mg': servingWeightMg,
    'energy_kcal_milli': values.energyKcalMilli,
    'protein_mg': values.proteinMg,
    'carbs_mg': values.carbsMg,
    'fat_mg': values.fatMg,
    'fibre_mg': values.fibreMg,
    'junk_category': junk?.code,
    'notes': notes,
  };

  factory MealItem.fromJson(Map<String, Object?> j) => MealItem(
    foodItemId: j['food_item_id'] as String?,
    foodName: j['food_name']! as String,
    quantityMilli: j['quantity_milli']! as int,
    unit: j['unit']! as String,
    servingWeightMg: j['serving_weight_mg'] as int?,
    values: NutritionValues(
      energyKcalMilli: j['energy_kcal_milli']! as int,
      proteinMg: j['protein_mg']! as int,
      carbsMg: j['carbs_mg']! as int,
      fatMg: j['fat_mg']! as int,
      fibreMg: j['fibre_mg']! as int,
    ),
    junk: JunkCategory.fromCode(j['junk_category'] as String?),
    notes: j['notes'] as String?,
  );
}

@immutable
final class Meal {
  const Meal({
    required this.id,
    required this.category,
    required this.occurredAt,
    required this.localDate,
    required this.items,
    this.notes,
    this.hasPhoto = false,
  });

  final String id;
  final MealCategory category;
  final DateTime occurredAt;
  final LocalDate localDate;
  final List<MealItem> items;
  final String? notes;
  final bool hasPhoto;

  NutritionValues get total => sumNutrition(items.map((i) => i.values));
}

/// What the meal form produces.
@immutable
final class MealDraft {
  const MealDraft({required this.category, required this.items, this.at, this.notes});

  final MealCategory category;
  final List<MealItem> items;

  /// Wall-clock time eaten; now when null.
  final DateTime? at;
  final String? notes;

  ValidationFailure? validate() {
    if (items.isEmpty) return const ValidationFailure('items', 'required');
    for (final item in items) {
      if (item.foodName.trim().isEmpty) return const ValidationFailure('foodName', 'required');
      if (item.quantityMilli <= 0) return const ValidationFailure('quantityMilli', 'out_of_range');
    }
    return null;
  }
}

@immutable
final class SavedMeal {
  const SavedMeal({required this.id, required this.name, required this.items, this.category, this.useCount = 0});
  final String id;
  final String name;
  final MealCategory? category;
  final List<MealItem> items;
  final int useCount;
}

/// A junk-food item as it appears in history: the same diary item, listed by
/// category. Its calories are already part of the day's totals.
typedef JunkEntry = ({String foodName, JunkCategory category, NutritionValues values, LocalDate date, DateTime at});

abstract interface class MealRepository {
  Future<Result<Meal>> add(MealDraft draft);

  /// Replaces the meal's time, category, note and items.
  Future<Result<void>> update(String id, MealDraft draft);
  Future<Result<void>> delete(String id);

  /// A copy of [id] logged at [at] (now when null), in the same category.
  Future<Result<Meal>> duplicate(String id, {DateTime? at});

  /// Meals of one day in time order, with their items.
  Stream<List<Meal>> watchOn(LocalDate date);

  /// Day totals for days between [from] and [to] that have meals.
  Future<Map<LocalDate, NutritionValues>> totalsBetween(LocalDate from, LocalDate to);

  /// Junk-food items between [from] and [to], newest first.
  Future<List<JunkEntry>> junkBetween(LocalDate from, LocalDate to);

  Future<void> setHasPhoto(String id, bool hasPhoto);

  // Saved meals.
  Future<Result<SavedMeal>> saveAsTemplate(String mealId, String name);
  Future<Result<Meal>> logSaved(String savedMealId, {MealCategory? category, DateTime? at});
  Future<Result<void>> deleteSaved(String savedMealId);
  Stream<List<SavedMeal>> watchSaved();
}
