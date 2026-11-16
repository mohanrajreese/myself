import '../../../core/errors/result.dart';
import '../../../core/utils/local_date.dart';
import 'goals.dart';

/// Goals are effective-dated: saving changes today and later days only, so
/// earlier days keep being judged against the goal they had (PRD §5.1).
abstract interface class GoalsRepository {
  Future<DailyGoals?> dailyGoalsOn(LocalDate date);
  Future<NutritionTargets?> nutritionGoalsOn(LocalDate date);
  Stream<DailyGoals?> watchCurrentDailyGoals();
  Stream<NutritionTargets?> watchCurrentNutritionGoals();
  Future<Result<void>> saveDailyGoals(DailyGoals goals);
  Future<Result<void>> saveNutritionGoals(NutritionTargets goals);
}
