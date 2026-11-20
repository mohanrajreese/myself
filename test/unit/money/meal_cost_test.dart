import 'package:fitbuddy/app/meal_cost.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/data/drift_money_repository.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late DriftMoneyRepository money;
  final at = DateTime(2026, 11, 20, 13, 10);

  setUp(() async {
    db = memoryDatabase();
    final time = MutableClock(at);
    money = DriftMoneyRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
    await money.seedCategories(const {});
    await db
        .into(db.mealLogs)
        .insert(
          MealLogsCompanion.insert(
            id: 'meal',
            createdAt: at.toUtc(),
            updatedAt: at.toUtc(),
            mealCategory: 'lunch',
            occurredAt: at.toUtc(),
            localDate: LocalDate(2026, 11, 20),
            tz: 'Asia/Kolkata',
          ),
        );
  });
  tearDown(() => db.close());

  Future<void> sync(int? paise) =>
      syncMealCost(money, mealId: 'meal', costPaise: paise, method: PaymentMethod.upi, at: at);

  test('a cost adds one Food expense, a new cost updates it, no cost removes it', () async {
    await sync(24000);
    var e = await money.expenseForMeal('meal');
    expect(e?.amountPaise, 24000);
    expect(e?.categoryId, DriftMoneyRepository.categoryId('food'));
    await sync(26000);
    expect((await db.select(db.expenses).get()).where((r) => r.deletedAt == null), hasLength(1));
    e = await money.expenseForMeal('meal');
    expect(e?.amountPaise, 26000);
    await sync(null);
    expect(await money.expenseForMeal('meal'), isNull);
  });

  test('deleting the meal can keep the expense unlinked or delete it', () async {
    await sync(24000);
    final linked = (await money.expenseForMeal('meal'))!;
    await afterMealDeleted(money, linked, deleteExpense: false);
    final kept = (await db.select(db.expenses).get()).single;
    expect(kept.deletedAt, isNull);
    expect(kept.mealLogId, isNull);
    await afterMealDeleted(money, linked, deleteExpense: true);
    expect((await db.select(db.expenses).get()).single.deletedAt, isNotNull);
  });
}
