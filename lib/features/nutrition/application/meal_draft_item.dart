import 'package:meta/meta.dart';

import '../../../core/units/decimal_text.dart';
import '../../food_database/domain/food.dart';
import '../domain/meals.dart';
import '../domain/nutrition_math.dart';

/// One way to measure a food: grams, the food's own serving, or a household
/// serving such as "idli". [baseValues] are the values for [baseQtyMilli]
/// of [unit].
@immutable
final class Portion {
  const Portion({required this.unit, required this.baseQtyMilli, required this.baseValues});

  /// `g`, or a serving name such as `bowl` or `idli`.
  final String unit;
  final int baseQtyMilli;
  final NutritionValues baseValues;

  bool get isGrams => unit == 'g';

  /// Step for the − and + buttons.
  int get stepMilli => isGrams ? 10000 : 500;

  int get defaultQtyMilli => isGrams ? 100000 : 1000;

  NutritionValues valuesFor(int qtyMilli) =>
      scaleToQuantity(baseValues, servingQtyMilli: baseQtyMilli, quantityMilli: qtyMilli);
}

String _unitName(String label) => label.trim().replaceFirst(RegExp(r'^1\s+'), '');

/// The ways [food] can be measured, the most natural first.
List<Portion> portionsFor(Food food) {
  final portions = <Portion>[];
  final household = food.householdLabel;
  final householdMg = food.householdWeightMg;
  final gramsPerServing = food.servingUnit == 'g' ? food.servingQtyMilli : food.servingWeightMg;

  if (household != null && householdMg != null && householdMg > 0 && gramsPerServing != null) {
    portions.add(
      Portion(
        unit: _unitName(household),
        baseQtyMilli: 1000,
        baseValues: scaleToQuantity(food.values, servingQtyMilli: gramsPerServing, quantityMilli: householdMg),
      ),
    );
  }
  if (food.servingUnit != 'g') {
    portions.add(Portion(unit: _unitName(food.servingLabel), baseQtyMilli: 1000, baseValues: food.values));
  }
  if (gramsPerServing != null && gramsPerServing > 0) {
    portions.add(Portion(unit: 'g', baseQtyMilli: gramsPerServing, baseValues: food.values));
  }
  return portions;
}

/// An item while the meal form is open.
@immutable
final class DraftItem {
  const DraftItem({
    required this.name,
    required this.portion,
    required this.qtyMilli,
    this.portions = const [],
    this.food,
    this.foodItemId,
    this.junk,
    this.isEstimate = false,
  });

  factory DraftItem.fromFood(Food food, Portion portion, int qtyMilli, {JunkCategory? junk}) => DraftItem(
    name: food.name,
    portion: portion,
    qtyMilli: qtyMilli,
    portions: portionsFor(food),
    food: food,
    foodItemId: food.isMine ? food.id : null,
    junk: junk ?? food.junk,
    isEstimate: food.isEstimate,
  );

  /// An item from a logged or saved meal: it can be rescaled in its own unit.
  factory DraftItem.fromMealItem(MealItem item) {
    final portion = Portion(unit: item.unit, baseQtyMilli: item.quantityMilli, baseValues: item.values);
    return DraftItem(
      name: item.foodName,
      portion: portion,
      qtyMilli: item.quantityMilli,
      portions: [portion],
      foodItemId: item.foodItemId,
      junk: item.junk,
    );
  }

  final String name;
  final Portion portion;
  final int qtyMilli;
  final List<Portion> portions;

  /// Set when added in this session (a catalogue food is copied into the
  /// user's foods when the meal is saved).
  final Food? food;
  final String? foodItemId;
  final JunkCategory? junk;
  final bool isEstimate;

  NutritionValues get values => portion.valuesFor(qtyMilli);

  /// "1.5 bowl", "250 g".
  String get quantityText {
    final decimals = qtyMilli % 1000 == 0 ? 0 : (qtyMilli % 100 == 0 ? 1 : 2);
    return '${formatScaled(qtyMilli, 3, decimals: decimals)} ${portion.unit}';
  }

  DraftItem copyWith({Portion? portion, int? qtyMilli, JunkCategory? Function()? junk, String? foodItemId}) =>
      DraftItem(
        name: name,
        portion: portion ?? this.portion,
        qtyMilli: qtyMilli ?? this.qtyMilli,
        portions: portions,
        food: food,
        foodItemId: foodItemId ?? this.foodItemId,
        junk: junk == null ? this.junk : junk(),
        isEstimate: isEstimate,
      );

  MealItem toMealItem() => MealItem(
    foodItemId: foodItemId,
    foodName: name,
    quantityMilli: qtyMilli,
    unit: portion.unit,
    values: values,
    junk: junk,
  );
}
