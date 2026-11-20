import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';
import 'money_common.dart';

/// Overall and per-category budgets for this month (board P8Budgets).
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final month = monthStart(today);
    final report = ref.watch(moneyReportProvider(monthRange(month, today)));
    final cats = ref.watch(moneyCategoryMapProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moneyBudgets),
        actions: [
          TextButton(
            onPressed: () =>
                _editBudget(context, categoryId: null, current: report.value?.budgetPaise),
            child: Text(l10n.edit),
          ),
        ],
      ),
      body: switch (report) {
        AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
          children: [
            Text(
              l10n.moneyMonthDaysLeft(monthLabel(month), monthEnd(month).daysSince(today) + 1),
              style: context.text.bodySmall,
            ),
            const SizedBox(height: FbSpace.md),
            if (value.budgetPaise == null)
              FbCard(
                dashed: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.moneyNoBudgetYet, style: context.text.body),
                    const SizedBox(height: FbSpace.sm),
                    FilledButton(
                      onPressed: () => _editBudget(context, categoryId: null, current: null),
                      child: Text(l10n.moneySetBudget),
                    ),
                  ],
                ),
              )
            else
              FbCard(
                child: _BudgetLine(
                  title: l10n.moneyMonthlyBudget,
                  spent: value.totalPaise,
                  budget: value.budgetPaise!,
                  big: true,
                ),
              ),
            MoneySectionHeader(l10n.moneyByCategory),
            if (value.categoryBudgets.isEmpty)
              FbEmptyHint(l10n.moneyNoCategoryBudgets)
            else
              FbCard(
                child: Column(
                  children: [
                    for (final MapEntry(:key, value: budget) in value.categoryBudgets.entries)
                      InkWell(
                        onTap: () => _editBudget(context, categoryId: key, current: budget),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: FbSpace.sm),
                          child: _BudgetLine(
                            title: categoryLabel(l10n, cats[key]),
                            spent: value.byCategory[key] ?? 0,
                            budget: budget,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: FbSpace.md),
            OutlinedButton.icon(
              onPressed: () async {
                final id = await _pickCategory(
                  context,
                  ref,
                  exclude: value.categoryBudgets.keys.toSet(),
                );
                if (id != null && context.mounted) {
                  await _editBudget(context, categoryId: id, current: null);
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.moneyAddCategoryBudget),
            ),
          ],
        ),
        _ => const FbLoading(),
      },
    );
  }

  static Future<String?> _pickCategory(
    BuildContext context,
    WidgetRef ref, {
    required Set<String> exclude,
  }) {
    final l10n = context.l10n;
    final cats = [
      for (final c in ref.read(moneyCategoriesProvider).value ?? const <FinanceCategory>[])
        if (!c.archived && !exclude.contains(c.id)) c,
    ];
    return showFbSheet<String>(
      context,
      FbSheetBody(
        title: l10n.moneyCategory,
        children: [
          for (final c in cats)
            FbListRow(title: categoryLabel(l10n, c), onTap: () => Navigator.of(context).pop(c.id)),
        ],
      ),
    );
  }

  static Future<void> _editBudget(
    BuildContext context, {
    required String? categoryId,
    required int? current,
  }) => showFbSheet<void>(context, _BudgetSheet(categoryId: categoryId, current: current));
}

class _BudgetLine extends StatelessWidget {
  const _BudgetLine({
    required this.title,
    required this.spent,
    required this.budget,
    this.big = false,
  });
  final String title;
  final int spent;
  final int budget;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pct = (spent * 100 / budget).round();
    final over = spent > budget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: big ? context.text.bodySmall : context.text.body)),
            Text(
              big
                  ? formatRupees(budget)
                  : l10n.moneyOfBudget(formatRupees(spent), formatRupees(budget)),
              style: big ? context.text.title : context.text.bodyStrong,
            ),
          ],
        ),
        const SizedBox(height: FbSpace.xs),
        MoneyBar(
          fraction: spent / budget,
          over: over,
          semanticLabel: over ? l10n.moneyOverBudgetA11y(pct) : l10n.moneyPercentA11y(pct),
        ),
        const SizedBox(height: FbSpace.xs),
        Row(
          children: [
            if (over) ...[
              Icon(Icons.error_outline_rounded, size: 16, color: context.colors.error),
              const SizedBox(width: FbSpace.xs),
            ],
            Expanded(
              child: Text(
                over
                    ? l10n.moneyOverLine(formatRupees(spent - budget), pct)
                    : big
                    ? l10n.moneySpentLeftLine(
                        formatRupees(spent),
                        formatRupees(budget - spent),
                        pct,
                      )
                    : l10n.moneyLeftLine(pct, formatRupees(budget - spent)),
                style: context.text.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({required this.categoryId, required this.current});
  final String? categoryId;
  final int? current;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  late String _amount = widget.current == null ? '' : rupeesInput(widget.current!);
  bool _nextMonth = false;
  String? _error;
  bool _busy = false;

  LocalDate get _from {
    final m = monthStart(ref.read(todayProvider));
    return _nextMonth ? addMonths(m, 1) : m;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final paise = parseRupees(_amount.replaceAll(',', '.'));
    if (paise == null || paise <= 0) {
      setState(() => _error = l10n.errAmountInvalid);
      return;
    }
    setState(() => _busy = true);
    final r = await ref
        .read(moneyRepositoryProvider)
        .setBudget(categoryId: widget.categoryId, amountPaise: paise, from: _from);
    if (!mounted) return;
    if (!r.isOk) {
      setState(() => (_busy = false, _error = l10n.errSaveFailed));
      return;
    }
    showFbSnackBar(context, l10n.moneyBudgetSaved);
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    await ref
        .read(moneyRepositoryProvider)
        .removeBudget(categoryId: widget.categoryId, from: _from);
    if (!mounted) return;
    showFbSnackBar(context, l10n.moneyBudgetRemoved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cats = ref.watch(moneyCategoryMapProvider);
    final month = monthStart(ref.watch(todayProvider));
    final title = widget.categoryId == null
        ? l10n.moneyMonthlyBudget
        : l10n.moneyBudgetFor(categoryLabel(l10n, cats[widget.categoryId]));
    return FbSheetBody(
      title: title,
      children: [
        FbTextField(
          label: l10n.moneyAmount,
          value: _amount,
          suffix: '₹',
          errorText: _error,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: rupeeInputFormatters,
          onChanged: (v) => setState(() => (_amount = v, _error = null)),
        ),
        const SizedBox(height: FbSpace.lg),
        Text(l10n.moneyStartsFrom, style: context.text.label),
        const SizedBox(height: FbSpace.xs),
        FbSegmented<bool>(
          semanticLabel: l10n.moneyStartsFrom,
          options: {
            false: l10n.moneyThisMonthOption(monthName(month)),
            true: l10n.moneyNextMonthOption(monthName(addMonths(month, 1))),
          },
          selected: _nextMonth,
          onChanged: (v) => setState(() => _nextMonth = v),
        ),
        const SizedBox(height: FbSpace.xs),
        Text(l10n.moneyEarlierKeep, style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.save, onPressed: _save, busy: _busy),
        if (widget.current != null) ...[
          const SizedBox(height: FbSpace.sm),
          TextButton(
            onPressed: _remove,
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: Text(l10n.moneyRemoveBudget),
          ),
        ],
      ],
    );
  }
}
