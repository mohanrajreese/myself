import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/budget_alert_providers.dart';
import '../../../app/budget_alerts.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';

/// Budget alerts on/off and the first threshold (board P9Alerts, §5.22K).
class MoneySettingsScreen extends ConsumerWidget {
  const MoneySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(budgetAlertSettingProvider);
    Future<void> save(BudgetAlertSetting s) async {
      await ref.read(budgetAlertsProvider).save(s);
      ref.invalidate(budgetAlertSettingProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.moneySettings)),
      body: switch (async) {
        AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
          children: [
            FbCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FbSwitchRow(
                    title: l10n.moneyBudgetAlerts,
                    subtitle: l10n.moneyBudgetAlertsLine(value.first),
                    value: value.enabled,
                    onChanged: (v) => save(BudgetAlertSetting(enabled: v, first: value.first)),
                  ),
                  if (value.enabled)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.moneyFirstAlertAt, style: context.text.label),
                          const SizedBox(height: FbSpace.xs),
                          Wrap(
                            spacing: FbSpace.sm,
                            runSpacing: FbSpace.sm,
                            children: [
                              for (final p in BudgetAlertSetting.choices)
                                FbToggleChip(
                                  label: '$p%',
                                  selected: p == value.first,
                                  onTap: () => save(BudgetAlertSetting(first: p)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: FbSpace.md),
            Text(l10n.moneySettingsNote, style: context.text.caption),
          ],
        ),
        _ => const FbLoading(),
      },
    );
  }
}
