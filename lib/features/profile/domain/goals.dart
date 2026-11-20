import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';

bool _outside(int? value, int min, int max) => value != null && (value < min || value > max);

/// Daily targets. Every field is optional (PRD §5.1).
@immutable
final class DailyGoals {
  const DailyGoals({
    this.targetWeightG,
    this.dailySteps,
    this.dailyWaterMl,
    this.sleepTargetMin,
    this.fitnessGoals = const [],
  });

  final int? targetWeightG;
  final int? dailySteps;
  final int? dailyWaterMl;
  final int? sleepTargetMin;
  final List<String> fitnessGoals;

  ValidationFailure? validate() {
    if (_outside(targetWeightG, 1000, 700000)) {
      return const ValidationFailure('targetWeightG', 'out_of_range');
    }
    if (_outside(dailySteps, 0, 200000)) {
      return const ValidationFailure('dailySteps', 'out_of_range');
    }
    if (_outside(dailyWaterMl, 0, 20000)) {
      return const ValidationFailure('dailyWaterMl', 'out_of_range');
    }
    if (_outside(sleepTargetMin, 0, 1440)) {
      return const ValidationFailure('sleepTargetMin', 'out_of_range');
    }
    if (fitnessGoals.length > 12 || fitnessGoals.any((g) => g.trim().isEmpty || g.length > 40)) {
      return const ValidationFailure('fitnessGoals', 'invalid');
    }
    return null;
  }
}

/// Daily nutrition targets in base units. Every field is optional; Praxis
/// never proposes a calorie target itself (PRD §1.3).
@immutable
final class NutritionTargets {
  const NutritionTargets({this.energyKcalMilli, this.proteinMg, this.carbsMg, this.fatMg, this.fibreMg});

  final int? energyKcalMilli;
  final int? proteinMg;
  final int? carbsMg;
  final int? fatMg;
  final int? fibreMg;

  ValidationFailure? validate() {
    if (_outside(energyKcalMilli, 0, 20000000)) {
      return const ValidationFailure('energyKcalMilli', 'out_of_range');
    }
    for (final (field, value) in [
      ('proteinMg', proteinMg),
      ('carbsMg', carbsMg),
      ('fatMg', fatMg),
      ('fibreMg', fibreMg),
    ]) {
      if (_outside(value, 0, 2000000)) return ValidationFailure(field, 'out_of_range');
    }
    return null;
  }
}
