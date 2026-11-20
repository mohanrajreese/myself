import 'package:fitbuddy/features/food_database/domain/food.dart';
import 'package:fitbuddy/features/nutrition/application/meal_draft_item.dart';
import 'package:fitbuddy/features/nutrition/domain/meals.dart';
import 'package:fitbuddy/features/nutrition/domain/nutrition_math.dart';
import 'package:flutter_test/flutter_test.dart';

const idli = Food(
  id: 'indb:ASC144',
  name: 'Idli',
  category: 'Indian dishes',
  servingLabel: '100 g',
  servingQtyMilli: 100000,
  servingUnit: 'g',
  servingWeightMg: 100000,
  values: NutritionValues(energyKcalMilli: 137535, proteinMg: 4637, carbsMg: 28178, fatMg: 333, fibreMg: 2309),
  source: FoodSources.indb,
  isEstimate: true,
  householdLabel: '1 idli',
  householdWeightMg: 25063,
);

const homeDal = Food(
  id: 'f1',
  name: 'Dal (home)',
  category: 'other',
  servingLabel: '1 bowl',
  servingQtyMilli: 1000,
  servingUnit: 'serving',
  servingWeightMg: 250000,
  values: NutritionValues(energyKcalMilli: 230000, proteinMg: 12000, carbsMg: 30000, fatMg: 6000, fibreMg: 8000),
  source: FoodSources.mine,
);

void main() {
  test('a catalogue dish offers its household serving first, then grams', () {
    final portions = portionsFor(idli);
    expect(portions.map((p) => p.unit), ['idli', 'g']);
    final three = DraftItem.fromFood(idli, portions.first, 3000);
    expect(three.quantityText, '3 idli');
    // One idli (25.063 g) is 34.470 kcal after rounding; three are 103.410 kcal.
    expect(three.values.energyKcalMilli, 103410);
    final grams = DraftItem.fromFood(idli, portions.last, 75189);
    expect(grams.values.energyKcalMilli, closeTo(103410, 10));
  });

  test('your own food offers its serving and, with a weight, grams', () {
    final portions = portionsFor(homeDal);
    expect(portions.map((p) => p.unit), ['bowl', 'g']);
    final item = DraftItem.fromFood(homeDal, portions.first, 1500);
    expect(item.quantityText, '1.5 bowl');
    expect(item.values.energyKcalMilli, 345000);
    expect(item.foodItemId, 'f1');
    final grams = DraftItem.fromFood(homeDal, portions.last, 125000);
    expect(grams.values.proteinMg, 6000);
  });

  test('a saved item rescales in its own unit', () {
    final item = DraftItem.fromMealItem(
      const MealItem(
        foodName: 'Rice',
        quantityMilli: 1500,
        unit: 'cup',
        values: NutritionValues(energyKcalMilli: 310000, proteinMg: 6000, carbsMg: 0, fatMg: 0, fibreMg: 0),
      ),
    );
    expect(item.copyWith(qtyMilli: 3000).values.energyKcalMilli, 620000);
    expect(item.toMealItem().unit, 'cup');
  });
}
