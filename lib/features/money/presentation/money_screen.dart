import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money_report.dart';
import 'expenses_screen.dart';
import 'money_common.dart';

/// The Money tab: the month at a glance (board P8Money).
class MoneyScreen extends ConsumerWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final month = ref.watch(moneyMonthProvider);
    final isCurrent = month == monthStart(today);
    final range = monthRange(month, today);
    final report = ref.watch(moneyReportProvider(range));
    final expenses = ref.watch(expensesProvider(range)).value ?? const [];
    final cats = ref.watch(moneyCategoryMapProvider);
    final emis = ref.watch(upcomingEmisProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabMoney),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.md),
            // Large text keeps the title readable: the button shrinks to its icon.
            child: MediaQuery.textScalerOf(context).scale(1) > 1.5
                ? IconButton.filled(
                    tooltip: l10n.moneyAddExpenseLabel,
                    onPressed: () => showExpenseSheet(context),
                    icon: const Icon(Icons.add_rounded),
                  )
                : FilledButton.icon(
                    onPressed: () => showExpenseSheet(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(l10n.moneyAddExpense, semanticsLabel: l10n.moneyAddExpenseLabel),
                  ),
          ),
        ],
      ),
      body: switch (report) {
        AsyncError() => FbErrorState(
          message: l10n.moneyLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => ref.invalidate(expensesProvider(range)),
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: l10n.moneyPrevMonth,
                  onPressed: () => ref.read(moneyMonthProvider.notifier).step(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(monthLabel(month), textAlign: TextAlign.center, style: context.text.bodyStrong),
                ),
                // Hidden rather than disabled in the current month: no future months.
                if (isCurrent)
                  const SizedBox(width: 48)
                else
                  IconButton(
                    tooltip: l10n.moneyNextMonth,
                    onPressed: () => ref.read(moneyMonthProvider.notifier).step(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
              ],
            ),
            _SpentCard(report: value, month: month, isCurrent: isCurrent, today: today),
            const SizedBox(height: FbSpace.md),
            const _Shortcuts(),
            if (emis.isNotEmpty) ...[
              MoneySectionHeader(l10n.moneyUpcomingEmis),
              FbListCard(
                children: [
                  for (final s in emis.take(3))
                    FbListRow(
                      title: '${s.debt.name} · ${s.debt.counterparty}',
                      subtitle: l10n.moneyEmiRow(context.shortDate(s.nextDue!), s.nextInstalment!, s.debt.emi!.count),
                      trailing: Text(formatRupees(s.debt.emi!.emiPaise), style: context.text.bodyStrong),
                      onTap: () => context.push(Routes.moneyDebt(s.debt.id)),
                    ),
                ],
              ),
            ],
            if (value.byCategory.isNotEmpty) ...[
              MoneySectionHeader(l10n.moneyTopCategories),
              FbCard(
                child: Column(
                  children: [
                    for (final MapEntry(:key, :value) in report.requireValue.byCategory.entries.take(3))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: FbSpace.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(categoryLabel(l10n, cats[key]), style: context.text.body)),
                                Text(formatRupees(value), style: context.text.bodyStrong),
                              ],
                            ),
                            const SizedBox(height: FbSpace.xs),
                            MoneyBar(
                              fraction: value / report.requireValue.totalPaise,
                              semanticLabel: l10n.moneyPercentA11y(report.requireValue.sharePercent(value)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            MoneySectionHeader(
              l10n.moneyRecent,
              action: expenses.isEmpty
                  ? null
                  : TextButton(onPressed: () => context.push(Routes.moneyExpenses), child: Text(l10n.moneySeeAll)),
            ),
            if (expenses.isEmpty)
              FbEmptyHint(l10n.moneyNothingInMonth, boxed: true)
            else
              FbListCard(
                children: [
                  for (final e in expenses.take(3))
                    ExpenseRow(
                      expense: e,
                      category: cats[e.categoryId],
                      showDay: true,
                      onTap: () => showExpenseSheet(context, existing: e),
                    ),
                ],
              ),
            const SizedBox(height: FbSpace.md),
            FbCard(
              child: Row(
                children: [
                  Expanded(
                    child: _Figure(label: l10n.moneyYouOwe, value: formatRupees(value.iOwePaise)),
                  ),
                  Expanded(
                    child: _Figure(label: l10n.moneyOwedToYou, value: formatRupees(value.owedToMePaise)),
                  ),
                ],
              ),
            ),
          ],
        ),
        _ => const FbLoading(),
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.text.caption),
        Text(value, style: context.text.title),
      ],
    ),
  );
}

class _SpentCard extends StatelessWidget {
  const _SpentCard({required this.report, required this.month, required this.isCurrent, required this.today});
  final MoneyReport report;
  final LocalDate month;
  final bool isCurrent;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final budget = report.budgetPaise;
    final spent = report.totalPaise;
    final prevMonth = addMonths(month, -1);
    final daysLeft = monthEnd(month).daysSince(today);
    return FbCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(isCurrent ? l10n.moneySpentThisMonth : l10n.moneySpentIn(monthName(month)), style: context.text.caption),
          Text(formatRupees(spent), style: context.text.displayMetric),
          const SizedBox(height: FbSpace.sm),
          if (budget != null) ...[
            MoneyBar(
              fraction: spent / budget,
              over: spent > budget,
              semanticLabel: l10n.moneyBudgetA11y(formatRupees(spent), formatRupees(budget), _pct(spent, budget)),
            ),
            const SizedBox(height: FbSpace.sm),
            Text(
              [
                spent > budget
                    ? l10n.moneyBudgetOverLine(formatRupees(spent - budget), _pct(spent, budget), formatRupees(budget))
                    : l10n.moneyBudgetLine(_pct(spent, budget), formatRupees(budget), formatRupees(budget - spent)),
                if (isCurrent && daysLeft > 0) l10n.moneyDaysToGo(daysLeft),
              ].join(' · '),
              style: context.text.bodySmall,
            ),
          ] else
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.moneyNoBudget, style: context.text.bodySmall),
                TextButton(onPressed: () => context.push(Routes.moneyBudgets), child: Text(l10n.moneySetBudget)),
              ],
            ),
          const SizedBox(height: FbSpace.xs),
          Text(
            isCurrent
                ? l10n.moneyComparedSameDate(monthName(prevMonth), formatRupees(report.previousTotalPaise))
                : l10n.moneyComparedWhole(monthName(prevMonth), formatRupees(report.previousTotalPaise)),
            style: context.text.caption,
          ),
        ],
      ),
    );
  }

  static int _pct(int part, int whole) => (part * 100 / whole).round();
}

class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (Icons.receipt_long_rounded, l10n.moneyExpenses, Routes.moneyExpenses),
      (Icons.pie_chart_outline_rounded, l10n.moneyBudgets, Routes.moneyBudgets),
      (Icons.swap_horiz_rounded, l10n.moneyDebts, Routes.moneyDebts),
      (Icons.bar_chart_rounded, l10n.moneyAnalysis, Routes.moneyAnalysis),
    ];
    return Wrap(
      spacing: FbSpace.sm,
      runSpacing: FbSpace.sm,
      children: [
        for (final (icon, label, route) in items)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 2 * FbSpace.lg - 3 * FbSpace.sm) / 4,
            child: FbCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: () => context.push(route),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.all(FbSpace.xs),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, color: context.colors.primary),
                        const SizedBox(height: FbSpace.xs),
                        Text(label, style: context.text.caption, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
