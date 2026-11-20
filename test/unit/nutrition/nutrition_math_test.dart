import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/nutrition/domain/nutrition_math.dart';
import 'package:flutter_test/flutter_test.dart';

const dal = NutritionValues(energyKcalMilli: 230000, proteinMg: 12000, carbsMg: 30000, fatMg: 6000, fibreMg: 8000);

void main() {
  group('scaling a food to the quantity eaten', () {
    test('one and a half servings', () {
      final eaten = scaleToQuantity(dal, servingQtyMilli: 1000, quantityMilli: 1500);
      expect(eaten.energyKcalMilli, 345000);
      expect(eaten.proteinMg, 18000);
      expect(eaten.fibreMg, 12000);
    });

    test('a food defined per 100 g, 250 g eaten', () {
      const per100g = NutritionValues(
        energyKcalMilli: 116000,
        proteinMg: 9020,
        carbsMg: 20130,
        fatMg: 380,
        fibreMg: 7900,
      );
      final eaten = scaleToQuantity(per100g, servingQtyMilli: 100000, quantityMilli: 250000);
      expect(eaten.energyKcalMilli, 290000);
      expect(eaten.proteinMg, 22550);
      expect(eaten.fatMg, 950);
    });

    test('rounds to the nearest unit instead of truncating', () {
      const food = NutritionValues(energyKcalMilli: 100, proteinMg: 1, carbsMg: 2, fatMg: 0, fibreMg: 0);
      final eaten = scaleToQuantity(food, servingQtyMilli: 3000, quantityMilli: 2000);
      expect(eaten.energyKcalMilli, 67);
      expect(eaten.proteinMg, 1);
      expect(eaten.carbsMg, 1);
    });
  });

  test('totals add exactly, with no drift over a thousand items', () {
    const item = NutritionValues(energyKcalMilli: 100100, proteinMg: 3333, carbsMg: 1, fatMg: 7, fibreMg: 0);
    final total = sumNutrition(List.filled(1000, item));
    expect(total.energyKcalMilli, 100100000);
    expect(total.proteinMg, 3333000);
    expect(total.carbsMg, 1000);
    expect(sumNutrition(const []), NutritionValues.zero);
  });

  test('calories remaining against a target, never hidden when over', () {
    expect(remainingKcalMilli(targetKcalMilli: 2750000, eatenKcalMilli: 1120000), 1630000);
    expect(remainingKcalMilli(targetKcalMilli: 2000000, eatenKcalMilli: 2300000), -300000);
    expect(remainingKcalMilli(targetKcalMilli: null, eatenKcalMilli: 500000), isNull);
  });

  test('progress fraction is clamped and safe without a target', () {
    expect(progressFraction(eaten: 48000, target: 110000), closeTo(0.436, 0.001));
    expect(progressFraction(eaten: 200, target: 100), 1);
    expect(progressFraction(eaten: 50, target: null), 0);
    expect(progressFraction(eaten: 50, target: 0), 0);
  });

  test('share of calories by meal, in meal order, omitting empty meals', () {
    final shares = caloriesByMeal({
      MealCategory.lunch: 540000,
      MealCategory.breakfast: 420000,
      MealCategory.eveningSnack: 160000,
      MealCategory.dinner: 0,
    });
    expect(shares.map((s) => s.category), [MealCategory.breakfast, MealCategory.lunch, MealCategory.eveningSnack]);
    expect(shares.map((s) => s.percent), [38, 48, 14]);
    expect(shares.fold<int>(0, (a, s) => a + s.percent), 100);
    expect(caloriesByMeal(const {}), isEmpty);
  });

  test('daily average counts only days that have meals', () {
    final average = dailyAverage({
      LocalDate(2026, 11, 10): const NutritionValues(
        energyKcalMilli: 2000000,
        proteinMg: 80000,
        carbsMg: 0,
        fatMg: 0,
        fibreMg: 0,
      ),
      LocalDate(2026, 11, 11): const NutritionValues(
        energyKcalMilli: 2500000,
        proteinMg: 90000,
        carbsMg: 0,
        fatMg: 0,
        fibreMg: 0,
      ),
      LocalDate(2026, 11, 12): const NutritionValues(
        energyKcalMilli: 2401000,
        proteinMg: 91000,
        carbsMg: 0,
        fatMg: 0,
        fibreMg: 0,
      ),
    });
    expect(average.days, 3);
    expect(average.values.energyKcalMilli, 2300333);
    expect(average.values.proteinMg, 87000);
    expect(dailyAverage(const {}).days, 0);
  });

  test('the default meal follows the time of day', () {
    MealCategory at(int hour, [int minute = 0]) => mealCategoryForTime(hour, minute);
    expect(at(5, 30), MealCategory.earlyMorning);
    expect(at(8), MealCategory.breakfast);
    expect(at(11), MealCategory.midMorning);
    expect(at(13, 10), MealCategory.lunch);
    expect(at(17, 30), MealCategory.eveningSnack);
    expect(at(20), MealCategory.dinner);
    expect(at(23, 30), MealCategory.lateNight);
    expect(at(2), MealCategory.lateNight);
  });

  test('junk food is a view of diary items; its calories are not added again', () {
    final items = [
      (values: dal, junk: null),
      (
        values: const NutritionValues(energyKcalMilli: 160000, proteinMg: 3000, carbsMg: 0, fatMg: 0, fibreMg: 0),
        junk: JunkCategory.friedSnacks,
      ),
      (
        values: const NutritionValues(energyKcalMilli: 140000, proteinMg: 0, carbsMg: 0, fatMg: 0, fibreMg: 0),
        junk: JunkCategory.sugaryDrinks,
      ),
    ];
    final dayTotal = sumNutrition(items.map((i) => i.values));
    final junk = sumNutrition(items.where((i) => i.junk != null).map((i) => i.values));
    expect(dayTotal.energyKcalMilli, 530000);
    expect(junk.energyKcalMilli, 300000);
  });

  test('category codes match the database', () {
    expect(MealCategory.values.map((c) => c.code), [
      'early_morning',
      'breakfast',
      'mid_morning',
      'lunch',
      'evening_snack',
      'dinner',
      'late_night',
      'other',
    ]);
    expect(JunkCategory.fromCode('sweets'), JunkCategory.sweets);
    expect(JunkCategory.fromCode(null), isNull);
    expect(MealCategory.fromCode('lunch'), MealCategory.lunch);
  });
}
