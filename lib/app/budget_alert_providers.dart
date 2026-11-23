import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'budget_alerts.dart';
import 'money_labels.dart';
import 'money_providers.dart';
import 'notification_setup.dart';
import 'providers.dart';
import 'routine_providers.dart';

final budgetAlertsProvider = Provider<BudgetAlerts>((ref) {
  final l10n = deviceLocalizations();
  return BudgetAlerts(
    money: ref.watch(moneyRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    gateway: ref.watch(notificationGatewayProvider),
    clock: ref.watch(clockProvider),
    l10n: l10n,
    categoryName: (id) {
      final c = ref.read(moneyCategoryMapProvider)[id];
      return c == null ? l10n.moneyCatOther : (categoryNames(l10n)[c.systemKey] ?? c.name);
    },
  );
});

final budgetAlertSettingProvider = FutureProvider<BudgetAlertSetting>(
  (ref) => ref.watch(budgetAlertsProvider).setting(),
);
