import 'package:meta/meta.dart';

/// Starting targets worked out from body weight (owner decision D7).
///
/// These are general rules of thumb per kilogram of body weight, offered as
/// editable starting points. They are estimates, not medical advice, and the
/// user can change or clear every one of them.
///
/// | Target   | Lose   | Maintain | Gain   |
/// |----------|--------|----------|--------|
/// | Calories | 25/kg  | 30/kg    | 35/kg  |
/// | Protein  | 1.6 g  | 1.2 g    | 1.2 g  |  (1.6 g when building strength)
/// | Water    | 35 ml/kg in every case            |
enum WeightDirection { lose, maintain, gain }

@immutable
final class GoalSuggestion {
  const GoalSuggestion({
    required this.direction,
    required this.energyKcalMilli,
    required this.proteinMg,
    required this.dailyWaterMl,
  });

  final WeightDirection direction;
  final int energyKcalMilli;
  final int proteinMg;
  final int dailyWaterMl;
}

const _maintainBandG = 500;

int _roundTo(int value, int step) => ((value + step ~/ 2) ~/ step) * step;

/// Returns null when there is no weight to work from.
GoalSuggestion? suggestGoals({
  required int? weightG,
  int? targetWeightG,
  bool buildStrength = false,
}) {
  if (weightG == null || weightG <= 0) return null;

  final direction = switch (targetWeightG) {
    null => WeightDirection.maintain,
    final target when target < weightG - _maintainBandG => WeightDirection.lose,
    final target when target > weightG + _maintainBandG => WeightDirection.gain,
    _ => WeightDirection.maintain,
  };

  final kcalPerKg = switch (direction) {
    WeightDirection.lose => 25,
    WeightDirection.maintain => 30,
    WeightDirection.gain => 35,
  };
  // grams * kcal/kg / 1000 = kcal
  final kcal = _roundTo(weightG * kcalPerKg ~/ 1000, 50).clamp(1500, 4000);

  final proteinMgPerKg = direction == WeightDirection.lose || buildStrength ? 1600 : 1200;
  // grams * mg/kg / 1000 = mg; then to whole grams, nearest 5 g
  final proteinG = _roundTo(weightG * proteinMgPerKg ~/ 1000000, 5).clamp(40, 220);

  final waterMl = _roundTo(weightG * 35 ~/ 1000, 50).clamp(1500, 4000);

  return GoalSuggestion(
    direction: direction,
    energyKcalMilli: kcal * 1000,
    proteinMg: proteinG * 1000,
    dailyWaterMl: waterMl,
  );
}
