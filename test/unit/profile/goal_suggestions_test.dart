import 'package:fitbuddy/features/profile/domain/goal_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no weight, no suggestion', () {
    expect(suggestGoals(weightG: null), isNull);
  });

  test('maintaining: 30 kcal, 1.2 g protein and 35 ml water per kg, rounded', () {
    final s = suggestGoals(weightG: 91800)!;
    expect(s.energyKcalMilli, 2750000); // 2,754 -> nearest 50
    expect(s.proteinMg, 110000); // 110.2 g -> nearest 5
    expect(s.dailyWaterMl, 3200); // 3,213 -> nearest 50
    expect(s.fibreMg, 40000); // 14 g x 2.75 = 38.5 -> 40
    expect(s.direction, WeightDirection.maintain);
  });

  test('a lower target weight uses 25 kcal and 1.6 g protein per kg', () {
    final s = suggestGoals(weightG: 91800, targetWeightG: 80000)!;
    expect(s.direction, WeightDirection.lose);
    expect(s.energyKcalMilli, 2300000); // 2,295
    expect(s.proteinMg, 145000); // 146.9 g
    expect(s.fibreMg, 30000); // 14 g x 2.3 = 32.2 -> 30
  });

  test('a higher target weight uses 35 kcal per kg', () {
    final s = suggestGoals(weightG: 60000, targetWeightG: 65000)!;
    expect(s.direction, WeightDirection.gain);
    expect(s.energyKcalMilli, 2100000);
    expect(s.proteinMg, 70000); // 72 g
  });

  test('a target within half a kilogram counts as maintaining', () {
    expect(suggestGoals(weightG: 70000, targetWeightG: 70400)!.direction, WeightDirection.maintain);
    expect(suggestGoals(weightG: 70000, targetWeightG: 69600)!.direction, WeightDirection.maintain);
  });

  test('building strength raises protein without changing calories', () {
    final base = suggestGoals(weightG: 70000)!;
    final strength = suggestGoals(weightG: 70000, buildStrength: true)!;
    expect(strength.energyKcalMilli, base.energyKcalMilli);
    expect(strength.proteinMg, 110000); // 112 g
  });

  test('suggestions stay inside safe bounds for very low and very high weights', () {
    final light = suggestGoals(weightG: 40000, targetWeightG: 35000)!;
    expect(light.energyKcalMilli, 1500000);
    expect(light.dailyWaterMl, 1500);
    expect(light.fibreMg, 25000); // 21 g -> at least 25
    final heavy = suggestGoals(weightG: 160000, targetWeightG: 170000)!;
    expect(heavy.energyKcalMilli, 4000000);
    expect(heavy.proteinMg, 190000); // 192 g
    expect(heavy.dailyWaterMl, 4000);
    final heavyLosing = suggestGoals(weightG: 160000, targetWeightG: 120000)!;
    expect(heavyLosing.proteinMg, 220000); // 256 g, capped
  });
}
