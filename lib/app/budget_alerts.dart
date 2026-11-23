import 'package:intl/intl.dart';

import '../core/database/settings_repository.dart';
import '../core/notifications/local_notification_gateway.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/utils/clock.dart';
import '../core/utils/local_date.dart';
import '../features/money/domain/money.dart';
import '../l10n/generated/app_localizations.dart';

/// Budget alert settings (§5.22K): on/off and the first threshold.
final class BudgetAlertSetting {
  const BudgetAlertSetting({this.enabled = true, this.first = 80});
  final bool enabled;
  final int first;

  static const key = 'money_budget_alerts';
  static const choices = [50, 70, 80, 90];

  Map<String, Object?> toJson() => {'enabled': enabled, 'first': first};
  static BudgetAlertSetting fromJson(Object? json) => switch (json) {
    {'enabled': final bool e, 'first': final int f} when f >= 50 && f <= 95 => BudgetAlertSetting(
      enabled: e,
      first: f,
    ),
    _ => const BudgetAlertSetting(),
  };
}

/// One fixed notification id for budget alerts; a newer alert replaces it.
const budgetAlertNotificationId = 906;

/// Shows "Food budget: 80% used" once per threshold per month.
final class BudgetAlerts {
  BudgetAlerts({
    required this.money,
    required this.settings,
    required this.gateway,
    required this.clock,
    required this.l10n,
    required this.categoryName,
  });

  final MoneyRepository money;
  final SettingsRepository settings;
  final NotificationGateway gateway;
  final Clock clock;
  final AppLocalizations l10n;
  final String Function(String categoryId) categoryName;

  Future<BudgetAlertSetting> setting() async =>
      BudgetAlertSetting.fromJson(await settings.read(BudgetAlertSetting.key));

  Future<void> save(BudgetAlertSetting value) =>
      settings.write(BudgetAlertSetting.key, value.toJson());

  Future<void> check() async {
    final s = await setting();
    if (!s.enabled) return;
    final today = LocalDate.fromDateTime(clock.now().toLocal());
    final month = LocalDate(today.year, today.month, 1);
    final expenses = await money.watchExpenses(from: month, to: today).first;
    final budgets = await money.watchBudgets().first;
    final monthKey = month.toString().substring(0, 7);
    final monthLabel = DateFormat.MMMM().format(DateTime(month.year, month.month));
    final ids = <String?>{null, for (final b in budgets) b.categoryId};
    String? title;
    for (final id in ids) {
      final budget = budgetFor(month, id, budgets);
      if (budget == null) continue;
      final spent = expenses
          .where((e) => id == null || e.categoryId == id)
          .fold(0, (n, e) => n + e.amountPaise);
      for (final t in [100, s.first]) {
        if (spent * 100 < budget.amountPaise * t) continue;
        final key = id ?? '';
        if (await money.alertShown(monthKey, key, t)) break;
        await money.markAlertShown(monthKey, key, t);
        // Crossing 100% also covers the lower threshold.
        if (t == 100) await money.markAlertShown(monthKey, key, s.first);
        final name = id == null ? l10n.moneyMonthlyBudget : categoryName(id);
        title ??= t == 100 ? l10n.moneyBudgetAlertFull(name) : l10n.moneyBudgetAlert(name, t);
        break;
      }
    }
    if (title == null) return;
    await gateway.show(
      NotificationRequest(
        id: budgetAlertNotificationId,
        channelId: channelIdFor('routines'),
        title: title,
        body: l10n.moneyBudgetAlertBody(monthLabel),
        withActions: false,
      ),
    );
  }
}
