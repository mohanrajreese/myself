import 'package:meta/meta.dart';

import '../../../core/units/decimal_text.dart';
import '../../../core/utils/local_date.dart';

/// Meal slots in the order they occur through the day (PRD §5.4).
enum MealCategory {
  earlyMorning('early_morning'),
  breakfast('breakfast'),
  midMorning('mid_morning'),
  lunch('lunch'),
  eveningSnack('evening_snack'),
  dinner('dinner'),
  lateNight('late_night'),
  other('other');

  const MealCategory(this.code);
  final String code;

  static MealCategory fromCode(String code) =>
      values.firstWhere((c) => c.code == code, orElse: () => MealCategory.other);
}

enum JunkCategory {
  fastFood('fast_food'),
  friedSnacks('fried_snacks'),
  sweets('sweets'),
  sugaryDrinks('sugary_drinks'),
  packagedSnacks('packaged_snacks'),
  other('other');

  const JunkCategory(this.code);
  final String code;

  static JunkCategory? fromCode(String? code) =>
      code == null ? null : values.where((c) => c.code == code).firstOrNull;
}

/// Energy and macronutrients in integer base units
/// (thousandths of a kilocalorie, milligrams).
@immutable
final class NutritionValues {
  const NutritionValues({
    required this.energyKcalMilli,
    required this.proteinMg,
    required this.carbsMg,
    required this.fatMg,
    required this.fibreMg,
  });

  static const zero = NutritionValues(
    energyKcalMilli: 0,
    proteinMg: 0,
    carbsMg: 0,
    fatMg: 0,
    fibreMg: 0,
  );

  final int energyKcalMilli;
  final int proteinMg;
  final int carbsMg;
  final int fatMg;
  final int fibreMg;

  NutritionValues operator +(NutritionValues other) => NutritionValues(
    energyKcalMilli: energyKcalMilli + other.energyKcalMilli,
    proteinMg: proteinMg + other.proteinMg,
    carbsMg: carbsMg + other.carbsMg,
    fatMg: fatMg + other.fatMg,
    fibreMg: fibreMg + other.fibreMg,
  );

  NutritionValues _map(int Function(int value) f) => NutritionValues(
    energyKcalMilli: f(energyKcalMilli),
    proteinMg: f(proteinMg),
    carbsMg: f(carbsMg),
    fatMg: f(fatMg),
    fibreMg: f(fibreMg),
  );

  @override
  bool operator ==(Object other) =>
      other is NutritionValues &&
      other.energyKcalMilli == energyKcalMilli &&
      other.proteinMg == proteinMg &&
      other.carbsMg == carbsMg &&
      other.fatMg == fatMg &&
      other.fibreMg == fibreMg;

  @override
  int get hashCode => Object.hash(energyKcalMilli, proteinMg, carbsMg, fatMg, fibreMg);
}

/// Values for [quantityMilli] of a food whose [perServing] values describe
/// [servingQtyMilli] of the same unit. Each value is rounded to the nearest
/// base unit once, here; totals are then exact integer sums.
NutritionValues scaleToQuantity(
  NutritionValues perServing, {
  required int servingQtyMilli,
  required int quantityMilli,
}) => perServing._map((value) => divRound(value * quantityMilli, servingQtyMilli));

NutritionValues sumNutrition(Iterable<NutritionValues> items) =>
    items.fold(NutritionValues.zero, (total, item) => total + item);

/// Negative when the target has been passed; null without a target.
int? remainingKcalMilli({required int? targetKcalMilli, required int eatenKcalMilli}) =>
    targetKcalMilli == null ? null : targetKcalMilli - eatenKcalMilli;

/// 0 to 1 for a progress bar.
double progressFraction({required int eaten, required int? target}) =>
    target == null || target <= 0 ? 0 : (eaten / target).clamp(0, 1).toDouble();

typedef MealShare = ({MealCategory category, int kcalMilli, int percent});

/// Each meal's share of the day's calories, in meal order. Percentages are
/// whole numbers that add up to exactly 100.
List<MealShare> caloriesByMeal(Map<MealCategory, int> kcalMilliByMeal) {
  final entries = [
    for (final category in MealCategory.values)
      if ((kcalMilliByMeal[category] ?? 0) > 0) (category, kcalMilliByMeal[category]!),
  ];
  final total = entries.fold<int>(0, (sum, e) => sum + e.$2);
  if (total == 0) return const [];

  // Largest-remainder rounding.
  final floors = [for (final e in entries) e.$2 * 100 ~/ total];
  final remainders = [for (final e in entries) e.$2 * 100 % total];
  var missing = 100 - floors.fold<int>(0, (a, b) => a + b);
  final order = List.generate(entries.length, (i) => i)
    ..sort((a, b) => remainders[b].compareTo(remainders[a]));
  for (final index in order) {
    if (missing == 0) break;
    floors[index]++;
    missing--;
  }
  return [
    for (var i = 0; i < entries.length; i++)
      (category: entries[i].$1, kcalMilli: entries[i].$2, percent: floors[i]),
  ];
}

/// Average over the days that have at least one meal logged. Days with
/// nothing logged are left out rather than counted as zero.
({int days, NutritionValues values}) dailyAverage(Map<LocalDate, NutritionValues> totalsByDay) {
  if (totalsByDay.isEmpty) return (days: 0, values: NutritionValues.zero);
  final days = totalsByDay.length;
  return (days: days, values: sumNutrition(totalsByDay.values)._map((v) => divRound(v, days)));
}

/// The meal slot suggested for a wall-clock time. The user can change it.
MealCategory mealCategoryForTime(int hour, int minute) {
  final minutes = hour * 60 + minute;
  if (minutes < 4 * 60) return MealCategory.lateNight;
  if (minutes < 7 * 60) return MealCategory.earlyMorning;
  if (minutes < 10 * 60 + 30) return MealCategory.breakfast;
  if (minutes < 12 * 60) return MealCategory.midMorning;
  if (minutes < 15 * 60 + 30) return MealCategory.lunch;
  if (minutes < 18 * 60 + 30) return MealCategory.eveningSnack;
  if (minutes < 22 * 60) return MealCategory.dinner;
  return MealCategory.lateNight;
}
