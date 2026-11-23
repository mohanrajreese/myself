import 'package:fitbuddy/app/budget_alerts.dart';
import 'package:fitbuddy/core/database/app_database.dart';
import 'package:fitbuddy/core/database/settings_repository.dart';
import 'package:fitbuddy/core/utils/local_date.dart';
import 'package:fitbuddy/features/money/data/drift_money_repository.dart';
import 'package:fitbuddy/features/money/domain/money.dart';
import 'package:fitbuddy/l10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late AppDatabase db;
  late MutableClock time;
  late DriftMoneyRepository money;
  late FakeNotificationGateway gateway;
  late BudgetAlerts alerts;
  final food = DriftMoneyRepository.categoryId('food');

  setUp(() async {
    db = memoryDatabase();
    time = MutableClock(DateTime(2026, 11, 20, 13));
    money = DriftMoneyRepository(
      db,
      clock: time.clock,
      ids: SequentialIds(),
      timeZone: const FixedTimeZone(),
    );
    gateway = FakeNotificationGateway();
    alerts = BudgetAlerts(
      money: money,
      settings: SettingsRepository(db, clock: time.clock),
      gateway: gateway,
      clock: time.clock,
      l10n: AppLocalizationsEn(),
      categoryName: (_) => 'Food',
    );
    await money.seedCategories(const {});
    await money.setBudget(categoryId: food, amountPaise: 500000, from: LocalDate(2026, 11, 1));
  });
  tearDown(() => db.close());

  Future<void> spend(int rupees) => money.addExpense((
    amountPaise: rupees * 100,
    categoryId: food,
    method: PaymentMethod.upi,
    at: time.now,
    note: null,
    mealLogId: null,
  ));

  test('alerts once at 80% and once at 100% in a month, without amounts', () async {
    await spend(3000);
    await alerts.check();
    expect(gateway.shown, isEmpty);
    await spend(1100); // 82 %
    await alerts.check();
    expect(gateway.shown.single.title, 'Food budget: 80% used');
    expect(gateway.shown.single.body, isNot(contains('₹')));
    await spend(100);
    await alerts.check();
    expect(gateway.shown, hasLength(1), reason: 'each threshold alerts once a month');
    await spend(900); // 102 %
    await alerts.check();
    expect(gateway.shown.last.title, 'Food budget: all used');
  });

  test('turned off, or a different first threshold', () async {
    await alerts.save(const BudgetAlertSetting(enabled: false));
    await spend(4900);
    await alerts.check();
    expect(gateway.shown, isEmpty);
    await alerts.save(const BudgetAlertSetting(first: 50));
    await alerts.check();
    expect(gateway.shown.single.title, 'Food budget: 50% used');
  });
}
