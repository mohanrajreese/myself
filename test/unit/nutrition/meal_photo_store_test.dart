import 'dart:io';

import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/encryption/file_cipher.dart';
import 'package:fitbuddy/features/nutrition/data/drift_meal_repository.dart';
import 'package:fitbuddy/features/nutrition/data/encrypted_meal_photo_store.dart';
import 'package:fitbuddy/features/nutrition/domain/meals.dart';
import 'package:fitbuddy/features/nutrition/domain/nutrition_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late DriftMealRepository meals;
  late EncryptedMealPhotoStore photos;
  late String mealId;
  final key = List<int>.generate(32, (i) => i);
  final image = List<int>.generate(4096, (i) => (i * 7) % 256)..setAll(0, 'JPEG-MARKER'.codeUnits);

  setUp(() async {
    db = memoryDatabase();
    dir = Directory.systemTemp.createTempSync('fitbuddy_photos_');
    final time = MutableClock(DateTime(2026, 11, 16, 13));
    final ids = SequentialIds();
    meals = DriftMealRepository(db, clock: time.clock, ids: ids, timeZone: const FixedTimeZone());
    photos = EncryptedMealPhotoStore(
      db: db,
      directory: Directory('${dir.path}/meal_photos'),
      cipher: FileCipher(key),
      meals: meals,
      clock: time.clock,
      ids: ids,
    );
    mealId = (await meals.add(
      const MealDraft(
        category: MealCategory.lunch,
        items: [MealItem(foodName: 'Dal', quantityMilli: 1000, unit: 'bowl', values: NutritionValues.zero)],
      ),
    )).valueOrNull!.id;
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  List<File> files() => Directory('${dir.path}/meal_photos').listSync().whereType<File>().toList();

  test('a photo is stored encrypted, reads back intact and flags the meal', () async {
    expect((await photos.attach(mealId, image)).isOk, isTrue);
    final stored = files().single.readAsBytesSync();
    expect(String.fromCharCodes(stored).contains('JPEG-MARKER'), isFalse);
    expect(await photos.read(mealId), image);
    expect((await meals.watchOn((await db.select(db.mealLogs).getSingle()).localDate).first).single.hasPhoto, isTrue);
  });

  test('the photo index never enters the sync outbox', () async {
    await db.customStatement('DELETE FROM sync_outbox');
    await photos.attach(mealId, image);
    expect((await outboxEntries(db)).map((e) => e.table), everyElement('meal_logs'));
  });

  test('replacing a photo removes the old file', () async {
    await photos.attach(mealId, image);
    await photos.attach(mealId, List<int>.filled(100, 1));
    expect(files(), hasLength(1));
    expect(await photos.read(mealId), List<int>.filled(100, 1));
  });

  test('removing deletes the file and clears the flag', () async {
    await photos.attach(mealId, image);
    await photos.remove(mealId);
    expect(files(), isEmpty);
    expect(await photos.read(mealId), isNull);
    expect((await db.select(db.mealLogs).getSingle()).hasPhoto, isFalse);
  });

  test('a wrong key or altered file cannot be read', () async {
    await photos.attach(mealId, image);
    final sealed = files().single.readAsBytesSync();
    final otherKey = FileCipher(List<int>.generate(32, (i) => 255 - i));
    await expectLater(otherKey.decrypt(sealed), throwsA(anything));
    sealed[sealed.length ~/ 2] ^= 1;
    await expectLater(FileCipher(key).decrypt(sealed), throwsA(anything));
  });

  test('empty and oversized images are rejected', () async {
    expect((await photos.attach(mealId, const [])).failureOrNull?.code, 'out_of_range');
    final huge = List<int>.filled(EncryptedMealPhotoStore.maxBytes + 1, 0);
    expect((await photos.attach(mealId, huge)).failureOrNull?.code, 'out_of_range');
  });
}
