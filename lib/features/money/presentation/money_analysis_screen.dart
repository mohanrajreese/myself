import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/money_labels.dart';
import '../../../app/money_providers.dart';
import '../../../app/providers.dart';
import '../../../core/units/rupees.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/money.dart';
import '../domain/money_report.dart';
import 'money_common.dart';

/// Money analysis for a month or chosen dates (board P8Analysis, §5.21D).
class MoneyAnalysisScreen extends ConsumerStatefulWidget {
  const MoneyAnalysisScreen({super.key});

  @override
  ConsumerState<MoneyAnalysisScreen> createState() => _MoneyAnalysisScreenState();
}

class _MoneyAnalysisScreenState extends ConsumerState<MoneyAnalysisScreen> {
  bool _custom = false;
  DayRange? _range;

  Future<void> _chooseRange() async {
    final today = ref.read(todayProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked == null) return;
    setState(() {
      _custom = true;
      _range = (from: LocalDate.fromDateTime(picked.start), to: LocalDate.fromDateTime(picked.end));
    });
  }

  String _span(DayRange r) => r.from == r.to
      ? context.shortDate(r.from)
      : '${context.shortDate(r.from)} – ${context.shortDate(r.to)} ${r.to.year}';

  String _fact(MoneyFact f, Map<String, FinanceCategory> cats) {
    final l10n = context.l10n;
    return switch (f) {
      SpendVsPrevious(:final differencePaise) when differencePaise > 0 => l10n.moneyFactMore(
        formatRupees(differencePaise),
      ),
      SpendVsPrevious(:final differencePaise) when differencePaise < 0 => l10n.moneyFactLess(
        formatRupees(-differencePaise),
      ),
      SpendVsPrevious() => l10n.moneyFactSame,
      EmiShare(:final percent) => l10n.moneyFactEmi(percent),
      final FoodPerMeal f => l10n.moneyFactFood(formatRupees(f.totalPaise), f.meals, formatRupees(f.averagePaise)),
      CategoryOverBudget(:final categoryId, :final overPaise) => l10n.moneyFactOver(
        categoryLabel(l10n, cats[categoryId]),
        formatRupees(overPaise),
      ),
      final BudgetUsed b => l10n.moneyFactBudget(b.percent),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final range = _custom && _range != null ? _range! : monthRange(ref.watch(moneyMonthProvider), today);
    final prev = MoneyReport.previousRange(range.from, range.to);
    final async = ref.watch(moneyReportProvider(range));
    final cats = ref.watch(moneyCategoryMapProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.moneyAnalysisTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSegmented<bool>(
            options: {false: l10n.moneyRangeMonth, true: l10n.moneyRangeCustom},
            selected: _custom,
            onChanged: (v) => v ? _chooseRange() : setState(() => _custom = false),
          ),
          const SizedBox(height: FbSpace.sm),
          Row(
            children: [
              Expanded(child: Text(l10n.moneyComparedRange(_span(range), _span(prev)), style: context.text.bodySmall)),
              if (_custom) TextButton(onPressed: _chooseRange, child: Text(l10n.moneyChooseRange)),
            ],
          ),
          switch (async) {
            AsyncError() => FbErrorState(message: l10n.moneyLoadFailed),
            AsyncData(:final value) => _body(context, value, cats),
            _ => const Padding(padding: EdgeInsets.all(FbSpace.xxl), child: FbLoading()),
          },
        ],
      ),
    );
  }

  Widget _body(BuildContext context, MoneyReport r, Map<String, FinanceCategory> cats) {
    final l10n = context.l10n;
    final facts = r.facts;
    final days = r.daily.entries.toList();
    final top = days.fold<MapEntry<LocalDate, int>?>(null, (m, e) => m == null || e.value > m.value ? e : m);
    final catKeys = {...r.byCategory.keys, ...r.previousByCategory.keys}.toList()
      ..sort((a, b) => (r.byCategory[b] ?? 0).compareTo(r.byCategory[a] ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: FbSpace.md),
        FbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: Text(l10n.moneyInBrief, style: context.text.bodyStrong)),
              const SizedBox(height: FbSpace.sm),
              if (facts.isEmpty) Text(l10n.moneyNothingInRange, style: context.text.body),
              for (final f in facts)
                Padding(
                  padding: const EdgeInsets.only(bottom: FbSpace.xs),
                  child: Text('• ${_fact(f, cats)}', style: context.text.body),
                ),
              const SizedBox(height: FbSpace.xs),
              Text(l10n.moneyNotAdvice, style: context.text.caption),
            ],
          ),
        ),
        if (r.totalPaise > 0) ...[
          const SizedBox(height: FbSpace.md),
          FbChartCard(
            title: l10n.moneySpendingPerDay,
            summary: top == null
                ? l10n.moneySpendingPerDay
                : l10n.moneyDailySummary(context.shortDate(top.key), formatRupees(top.value)),
            height: 140,
            chart: FbBarChart(values: [for (final e in days) e.value / 100], bottomLabel: (i) => '${days[i].key.day}'),
          ),
          MoneySectionHeader(l10n.moneyByCategory),
          FbCard(
            child: Column(
              children: [
                _TableRow(
                  first: l10n.moneyCategoryHeader,
                  second: l10n.moneyThisPeriod,
                  third: l10n.moneyPreviousPeriod,
                  header: true,
                ),
                for (final k in catKeys)
                  _TableRow(
                    first: categoryLabel(l10n, cats[k]),
                    second: formatRupees(r.byCategory[k] ?? 0),
                    third: formatRupees(r.previousByCategory[k] ?? 0),
                  ),
              ],
            ),
          ),
          MoneySectionHeader(l10n.moneyByMethod),
          FbListCard(
            children: [
              for (final MapEntry(:key, :value) in r.byMethod.entries)
                MoneyValueRow(
                  label: paymentMethodLabel(l10n, key),
                  value: l10n.moneyMethodShare(formatRupees(value), r.sharePercent(value)),
                ),
            ],
          ),
        ],
        MoneySectionHeader(l10n.moneyFoodAndMeals),
        FbListCard(
          children: [
            MoneyValueRow(label: l10n.moneyFoodSpending, value: formatRupees(r.foodPaise)),
            MoneyValueRow(
              label: l10n.moneyLinkedMeals,
              value: l10n.moneyLinkedMealsValue(
                r.linkedMeals,
                formatRupees(r.linkedMeals == 0 ? 0 : (r.linkedMealPaise / r.linkedMeals).round()),
              ),
            ),
            MoneyValueRow(
              label: l10n.moneyJunkMeals,
              value: l10n.moneyJunkMealsValue(r.junkMeals, formatRupees(r.junkMealPaise)),
            ),
          ],
        ),
        MoneySectionHeader(l10n.moneyDebts),
        FbListCard(
          children: [
            MoneyValueRow(label: l10n.moneyYouOwe, value: formatRupees(r.iOwePaise)),
            MoneyValueRow(label: l10n.moneyOwedToYou, value: formatRupees(r.owedToMePaise)),
            MoneyValueRow(
              label: l10n.moneyEmisNext30,
              value: l10n.moneyEmisNext30Value(r.upcomingEmis, formatRupees(r.upcomingEmiPaise)),
            ),
          ],
        ),
      ],
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.first, required this.second, required this.third, this.header = false});
  final String first;
  final String second;
  final String third;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header ? context.text.caption : context.text.body;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FbSpace.xs),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(first, style: style)),
            Expanded(
              flex: 2,
              child: Text(second, textAlign: TextAlign.end, style: header ? style : context.text.bodyStrong),
            ),
            Expanded(
              flex: 2,
              child: Text(third, textAlign: TextAlign.end, style: style),
            ),
          ],
        ),
      ),
    );
  }
}
