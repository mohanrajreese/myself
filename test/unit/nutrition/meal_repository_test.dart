import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/food_database/data/drift_food_repository.dart';
import 'package:fitbuddy/features/food_database/domain/food.dart';
import 'package:fitbuddy/features/nutrition/data/drift_meal_repository.dart';
import 'package:fitbuddy/features/nutrition/domain/meals.dart';
import 'package:fitbuddy/features/nutrition/domain/nutrition_math.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

MealItem item(String name, int kcal, {int protein = 0, JunkCategory? junk, String? foodId}) => MealItem(
  foodItemId: foodId,
  foodName: name,
  quantityMilli: 1000,
  unit: 'serving',
  values: NutritionValues(energyKcalMilli: kcal * 1000, proteinMg: protein * 1000, carbsMg: 0, fatMg: 0, fibreMg: 0),
  junk: junk,
);

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftMealRepository meals;
  final today = LocalDate(2026, 11, 16);

  setUp(() {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 16, 20));
    meals = DriftMealRepository(db, clock: time.clock, ids: SequentialIds(), timeZone: const FixedTimeZone());
  });
  tearDown(() => db.close());

  Future<Meal> breakfast() async => (await meals.add(
    MealDraft(
      category: MealCategory.breakfast,
      at: DateTime(2026, 11, 16, 8),
      items: [item('Idli', 174, protein: 6), item('Sambar', 150, protein: 7), item('Filter coffee', 96)],
    ),
  )).valueOrNull!;

  test('a meal with several items totals them exactly', () async {
    final meal = await breakfast();
    expect(meal.items.map((i) => i.foodName), ['Idli', 'Sambar', 'Filter coffee']);
    expect(meal.total.energyKcalMilli, 420000);
    expect(meal.total.proteinMg, 13000);
    expect(meal.localDate, today);
  });

  test('the meal and every item are queued for sync', () async {
    await breakfast();
    final queued = await outboxEntries(db);
    expect(queued.where((e) => e.table == 'meal_logs'), hasLength(1));
    expect(queued.where((e) => e.table == 'meal_food_items'), hasLength(3));
  });

  test('validation: at least one item, positive quantity, not in the future', () async {
    expect((await meals.add(const MealDraft(category: MealCategory.lunch, items: []))).failureOrNull?.code, 'required');
    expect(
      (await meals.add(
        MealDraft(category: MealCategory.lunch, items: [item('x', 1)], at: DateTime(2026, 11, 17)),
      )).failureOrNull?.code,
      'in_future',
    );
    expect(await db.select(db.mealLogs).get(), isEmpty);
  });

  test('editing a food later does not change a past meal (snapshot)', () async {
    final foods = DriftFoodRepository(db, clock: time.clock, ids: SequentialIds());
    final dal = (await foods.create(
      const FoodDraft(
        name: 'Dal',
        servingLabel: '1 bowl',
        servingQtyMilli: 1000,
        servingUnit: 'bowl',
        values: NutritionValues(energyKcalMilli: 230000, proteinMg: 12000, carbsMg: 0, fatMg: 0, fibreMg: 0),
      ),
    )).valueOrNull!;
    await meals.add(
      MealDraft(
        category: MealCategory.lunch,
        items: [item('Dal', 230, foodId: dal.id)],
      ),
    );
    await foods.update(
      dal.id,
      const FoodDraft(
        name: 'Dal',
        servingLabel: '1 bowl',
        servingQtyMilli: 1000,
        servingUnit: 'bowl',
        values: NutritionValues(energyKcalMilli: 400000, proteinMg: 1, carbsMg: 0, fatMg: 0, fibreMg: 0),
      ),
    );
    await foods.delete(dal.id);
    final meal = (await meals.watchOn(today).first).single;
    expect(meal.total.energyKcalMilli, 230000);
  });

  test('the day view updates when a meal is added, edited or deleted', () async {
    final seen = <int>[];
    final sub = meals.watchOn(today).listen((list) => seen.add(sumNutrition(list.map((m) => m.total)).energyKcalMilli));
    await pumpEventQueue();
    final meal = await breakfast();
    await pumpEventQueue();
    await meals.update(meal.id, MealDraft(category: MealCategory.breakfast, items: [item('Idli', 174)]));
    await pumpEventQueue();
    await meals.delete(meal.id);
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen, contains(420000));
    expect(seen, contains(174000));
    expect(seen.last, 0);
  });

  test('an edit replaces the items and can move the meal to another day', () async {
    final meal = await breakfast();
    await meals.update(
      meal.id,
      MealDraft(category: MealCategory.lateNight, at: DateTime(2026, 11, 15, 23), items: [item('Toast', 90)]),
    );
    expect(await meals.watchOn(today).first, isEmpty);
    final moved = (await meals.watchOn(LocalDate(2026, 11, 15)).first).single;
    expect(moved.category, MealCategory.lateNight);
    expect(moved.items.single.foodName, 'Toast');
    expect((await db.select(db.mealFoodItems).get()).where((r) => r.deletedAt != null), hasLength(3));
  });

  test('duplicate copies items into a new meal at a new time', () async {
    final meal = await breakfast();
    time.now = DateTime(2026, 11, 17, 8, 30);
    final copy = (await meals.duplicate(meal.id)).valueOrNull!;
    expect(copy.id, isNot(meal.id));
    expect(copy.localDate, LocalDate(2026, 11, 17));
    expect(copy.total, meal.total);
  });

  test('day totals and junk history: junk calories are counted once', () async {
    await breakfast();
    await meals.add(
      MealDraft(
        category: MealCategory.eveningSnack,
        at: DateTime(2026, 11, 16, 17, 30),
        items: [item('Samosa', 160, junk: JunkCategory.friedSnacks)],
      ),
    );
    await meals.add(
      MealDraft(
        category: MealCategory.other,
        at: DateTime(2026, 11, 14, 16),
        items: [item('Cola', 140, junk: JunkCategory.sugaryDrinks)],
      ),
    );
    final totals = await meals.totalsBetween(LocalDate(2026, 11, 10), today);
    expect(totals[today]!.energyKcalMilli, 580000);
    expect(totals[LocalDate(2026, 11, 14)]!.energyKcalMilli, 140000);
    expect(totals.length, 2);

    final junk = await meals.junkBetween(LocalDate(2026, 11, 10), today);
    expect(junk.map((j) => j.foodName), ['Samosa', 'Cola']);
    expect(junk.first.category, JunkCategory.friedSnacks);
  });

  test('saved meals: save from a meal, log again, count uses, delete', () async {
    final meal = await breakfast();
    final saved = (await meals.saveAsTemplate(meal.id, 'South Indian breakfast')).valueOrNull!;
    expect(saved.items, hasLength(3));
    expect((await meals.saveAsTemplate(meal.id, ' ')).failureOrNull?.code, 'required');

    time.now = DateTime(2026, 11, 17, 8);
    final logged = (await meals.logSaved(saved.id)).valueOrNull!;
    expect(logged.category, MealCategory.breakfast);
    expect(logged.total.energyKcalMilli, 420000);
    expect(logged.localDate, LocalDate(2026, 11, 17));
    expect((await meals.watchSaved().first).single.useCount, 1);

    await meals.deleteSaved(saved.id);
    expect(await meals.watchSaved().first, isEmpty);
    expect(await meals.watchOn(LocalDate(2026, 11, 17)).first, hasLength(1), reason: 'logged meals stay');
  });
}
