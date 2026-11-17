import 'dart:io';

import '../../../core/database/app_database.dart';
import '../../../core/encryption/file_cipher.dart';
import '../../../core/errors/failure.dart';
import '../../../core/errors/result.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/meal_photos.dart';
import '../domain/meals.dart';

/// Keeps one encrypted photo per meal in [directory] (app-private storage,
/// excluded from backups) and records it in `local_meal_photos`.
final class EncryptedMealPhotoStore implements MealPhotoStore {
  EncryptedMealPhotoStore({
    required AppDatabase db,
    required this.directory,
    required this.cipher,
    required this.meals,
    required this.clock,
    required this.ids,
  }) : _db = db;

  final AppDatabase _db;
  final Directory directory;
  final FileCipher cipher;
  final MealRepository meals;
  final Clock clock;
  final IdGenerator ids;

  static const maxBytes = 15 * 1024 * 1024;

  File _file(String name) => File('${directory.path}/$name');

  Future<MealPhotoRow?> _row(String mealId) =>
      (_db.select(_db.localMealPhotos)..where((t) => t.mealLogId.equals(mealId))).getSingleOrNull();

  @override
  Future<Result<void>> attach(String mealId, List<int> imageBytes) async {
    if (imageBytes.isEmpty || imageBytes.length > maxBytes) {
      return const Err(ValidationFailure('photo', 'out_of_range'));
    }
    return Result.guard(() async {
      await directory.create(recursive: true);
      final id = ids.newId();
      final name = '$id.bin';
      await _file(name).writeAsBytes(await cipher.encrypt(imageBytes), flush: true);
      final previous = await _row(mealId);
      await _db.transaction(() async {
        if (previous != null) {
          await (_db.delete(_db.localMealPhotos)..where((t) => t.id.equals(previous.id))).go();
        }
        await _db
            .into(_db.localMealPhotos)
            .insert(
              LocalMealPhotosCompanion.insert(
                id: id,
                mealLogId: mealId,
                fileName: name,
                takenAt: clock.now().toUtc(),
              ),
            );
      });
      if (previous != null) await _deleteFile(previous.fileName);
      await meals.setHasPhoto(mealId, true);
    }, onError: (_) => const StorageFailure('photo_write'));
  }

  @override
  Future<List<int>?> read(String mealId) async {
    final row = await _row(mealId);
    if (row == null) return null;
    final file = _file(row.fileName);
    if (!file.existsSync()) return null;
    return cipher.decrypt(await file.readAsBytes());
  }

  @override
  Future<Result<void>> remove(String mealId) => Result.guard(() async {
    final row = await _row(mealId);
    if (row == null) return;
    await (_db.delete(_db.localMealPhotos)..where((t) => t.id.equals(row.id))).go();
    await _deleteFile(row.fileName);
    await meals.setHasPhoto(mealId, false);
  }, onError: (_) => const StorageFailure('photo_write'));

  Future<void> _deleteFile(String name) async {
    final file = _file(name);
    if (file.existsSync()) await file.delete();
  }
}
