import '../../../core/errors/result.dart';

/// Photos attached to meals. Stored encrypted on this phone only; never
/// uploaded (decision C2).
abstract interface class MealPhotoStore {
  /// Encrypts and stores [imageBytes] for [mealId], replacing any earlier photo.
  Future<Result<void>> attach(String mealId, List<int> imageBytes);

  /// The decrypted photo, or null when the meal has none.
  Future<List<int>?> read(String mealId);

  Future<Result<void>> remove(String mealId);

  /// Deletes every stored photo file (erasing the phone's data, §7.3).
  Future<void> removeAll();
}
