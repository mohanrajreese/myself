/// Read-side providers shared by several screens (Home, the Health and
/// Nutrition tabs). They sit in the composition root so features never
/// import each other's application code.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/photo_picker.dart';
import '../core/utils/local_date.dart';
import '../features/body_measurements/domain/measurements.dart';
import '../features/nutrition/domain/meal_photos.dart';
import '../features/nutrition/domain/meals.dart';
import '../features/nutrition/domain/nutrition_math.dart';
import '../features/profile/domain/profile.dart';
import '../features/sleep/domain/sleep_repository.dart';
import '../features/water/domain/water.dart';
import '../features/wellness/domain/wellness.dart';
import '../features/weight/domain/weight_entry.dart';
import 'providers.dart';

/// Supplied at start-up (encrypted files in app storage) and by tests.
final mealPhotoStoreProvider = Provider<MealPhotoStore>((ref) => throw StateError('not provided'));

final photoPickerProvider = Provider<PhotoPicker>((ref) => const SystemPhotoPicker());

/// The signed-in user's unit choices; metric until a profile exists.
final unitsProvider = Provider<UnitPreferences>((ref) {
  final account = ref.watch(currentAccountProvider);
  if (account == null) return UnitPreferences.metric;
  return ref.watch(profileProvider(account.id)).value?.units ?? UnitPreferences.metric;
});

final waterOnProvider = StreamProvider.family<List<WaterEntry>, LocalDate>(
  (ref, date) => ref.watch(waterRepositoryProvider).watchOn(date),
);

final waterTotalOnProvider = Provider.family<int, LocalDate>(
  (ref, date) => ref.watch(waterOnProvider(date)).value?.fold<int>(0, (sum, e) => sum + e.amountMl) ?? 0,
);

final mealsOnProvider = StreamProvider.family<List<Meal>, LocalDate>(
  (ref, date) => ref.watch(mealRepositoryProvider).watchOn(date),
);

final nutritionOnProvider = Provider.family<NutritionValues, LocalDate>(
  (ref, date) => sumNutrition((ref.watch(mealsOnProvider(date)).value ?? const []).map((m) => m.total)),
);

typedef DateRange = ({LocalDate from, LocalDate to});

final sleepBetweenProvider = StreamProvider.family<List<SleepEntry>, DateRange>(
  (ref, range) => ref.watch(sleepRepositoryProvider).watchBetween(range.from, range.to),
);

final wellnessBetweenProvider = StreamProvider.family<List<WellnessCheckin>, DateRange>(
  (ref, range) => ref.watch(wellnessRepositoryProvider).watchBetween(range.from, range.to),
);

final latestMeasurementsProvider = StreamProvider<List<Measurement>>(
  (ref) => ref.watch(measurementRepositoryProvider).watchLatestPerType(),
);

final measurementHistoryProvider = StreamProvider.family<List<Measurement>, String>(
  (ref, type) => ref.watch(measurementRepositoryProvider).watchHistory(type),
);

final weightSinceProvider = StreamProvider.family<List<WeightEntry>, LocalDate>(
  (ref, from) => ref.watch(weightRepositoryProvider).watchSince(from),
);

/// Every 30 days of history needs a fresh query; this rebuilds on demand.
final waterTotalsProvider = FutureProvider.family<Map<LocalDate, int>, DateRange>((ref, range) {
  ref.watch(waterOnProvider(range.to));
  return ref.watch(waterRepositoryProvider).totalsBetween(range.from, range.to);
});

final nutritionTotalsProvider = FutureProvider.family<Map<LocalDate, NutritionValues>, DateRange>((ref, range) {
  ref.watch(mealsOnProvider(range.to));
  return ref.watch(mealRepositoryProvider).totalsBetween(range.from, range.to);
});

final junkBetweenProvider = FutureProvider.family<List<JunkEntry>, DateRange>((ref, range) {
  ref.watch(mealsOnProvider(range.to));
  return ref.watch(mealRepositoryProvider).junkBetween(range.from, range.to);
});

final savedMealsProvider = StreamProvider<List<SavedMeal>>((ref) => ref.watch(mealRepositoryProvider).watchSaved());

/// Night sleep that ended on [date] (the day it counts towards).
final sleepOnProvider = Provider.family<Duration?, LocalDate>((ref, date) {
  final entries = ref.watch(sleepBetweenProvider((from: date, to: date))).value ?? const [];
  final nights = entries.where((e) => e.period.kind.name == 'night');
  if (nights.isEmpty) return null;
  return nights.fold<Duration>(Duration.zero, (sum, e) => sum + e.period.duration);
});
