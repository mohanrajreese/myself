import 'package:meta/meta.dart';

import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../nutrition/domain/nutrition_math.dart';

/// A food the user can log: their own, or one from the bundled catalogue.
/// [values] describe one serving of [servingQtyMilli] × [servingUnit].
@immutable
final class Food {
  const Food({
    required this.id,
    required this.name,
    required this.category,
    required this.servingLabel,
    required this.servingQtyMilli,
    required this.servingUnit,
    required this.values,
    required this.source,
    this.servingWeightMg,
    this.brand,
    this.junk,
    this.isSaved = false,
    this.isEstimate = false,
    this.useCount = 0,
  });

  final String id;
  final String name;
  final String? brand;
  final String category;
  final String servingLabel;
  final int servingQtyMilli;
  final String servingUnit;
  final int? servingWeightMg;
  final NutritionValues values;
  final JunkCategory? junk;

  /// `mine` for the user's foods, otherwise the catalogue source (`usda`, `indb`).
  final String source;
  final bool isSaved;
  final bool isEstimate;
  final int useCount;

  bool get isMine => source == FoodSources.mine;
}

abstract final class FoodSources {
  static const mine = 'mine';
  static const usda = 'usda';
  static const indb = 'indb';
}

/// What the user types to create or edit one of their foods.
@immutable
final class FoodDraft {
  const FoodDraft({
    required this.name,
    required this.servingLabel,
    required this.servingQtyMilli,
    required this.servingUnit,
    required this.values,
    this.category = 'other',
    this.brand,
    this.servingWeightMg,
    this.junk,
    this.isSaved = false,
  });

  final String name;
  final String? brand;
  final String category;
  final String servingLabel;
  final int servingQtyMilli;
  final String servingUnit;
  final int? servingWeightMg;
  final NutritionValues values;
  final JunkCategory? junk;
  final bool isSaved;

  ValidationFailure? validate() {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const ValidationFailure('name', 'required');
    if (trimmed.length > 120) return const ValidationFailure('name', 'too_long');
    if (servingLabel.trim().isEmpty) return const ValidationFailure('servingLabel', 'required');
    if (servingQtyMilli <= 0) return const ValidationFailure('servingQtyMilli', 'out_of_range');
    if (values.energyKcalMilli < 0 || values.energyKcalMilli > 10000000) {
      return const ValidationFailure('energyKcalMilli', 'out_of_range');
    }
    for (final (field, v) in [
      ('proteinMg', values.proteinMg),
      ('carbsMg', values.carbsMg),
      ('fatMg', values.fatMg),
      ('fibreMg', values.fibreMg),
    ]) {
      if (v < 0 || v > 1000000) return ValidationFailure(field, 'out_of_range');
    }
    return null;
  }
}

enum FoodFilter { all, recent, saved, mine }

abstract interface class FoodRepository {
  Future<Result<Food>> create(FoodDraft draft);

  /// Edits one of the user's foods. Past meals keep their own values.
  Future<Result<void>> update(String id, FoodDraft draft);
  Future<Result<void>> delete(String id);
  Future<Result<void>> setSaved(String id, bool saved);

  /// Copies a catalogue food into the user's foods so it can be edited and
  /// saved. Returns the existing copy if there is one.
  Future<Result<Food>> adopt(Food catalogueFood);

  /// The user's foods first (most used first), then catalogue matches.
  /// Works offline.
  Future<List<Food>> search(String query, {FoodFilter filter = FoodFilter.all, int limit = 50});

  /// Records that a food was logged (for "recent" and ordering).
  Future<void> markUsed(String id, DateTime at);
}
