import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/insights_providers.dart';
import '../../../app/measurement_labels.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/tracking_providers.dart' hide DateRange;
import '../../../core/widgets/fb_fields.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../profile/domain/profile.dart';
import '../domain/report.dart';

/// What a report screen is about. Each has a card or row on Insights.
enum ReportKind {
  steps,
  weight,
  nutrition,
  water,
  sleep,
  workouts,
  activities,
  screenTime,
  measurements,
  wellness,
  junk,
  gym,
}

/// The period chosen on Insights, shared with the report screens.
typedef Selection = ({ReportPeriod period, DateRange range});

String _periodWord(ReportPeriod p) => switch (p) {
  ReportPeriod.day => 'day',
  ReportPeriod.week => 'week',
  ReportPeriod.month => 'month',
  ReportPeriod.custom => 'period',
};

String rangeLabel(BuildContext context, DateRange r) =>
    r.days == 1 ? context.dayLabel(r.from) : '${context.shortDate(r.from)} – ${context.shortDate(r.to)} ${r.to.year}';

/// One sentence per insight, descriptive only (04 §7: "increased",
/// "compared with"; never "because" or advice).
String insightSentence(BuildContext context, Insight i, ReportPeriod p, UnitPreferences u) {
  final l = context.l10n;
  final dir = i.delta >= 0 ? 'up' : 'down';
  final period = _periodWord(p);
  final d = i.delta.abs();
  return switch (i.kind) {
    InsightKind.stepsAverage => l.insightSteps(dir, context.number(d), period),
    InsightKind.sleepAverage => l.insightSleep(dir, context.duration(Duration(minutes: d)), period),
    InsightKind.weightLatest => l.insightWeight(dir, context.mass(d, u.mass), period),
    InsightKind.waterAverage => l.insightWater(dir, context.volume(d, u.volume), period),
    InsightKind.kcalAverage => l.insightKcal(dir, context.kcal(d), period),
    InsightKind.proteinAverage => l.insightProtein(dir, context.grams(d), period),
    InsightKind.fibreAverage => l.insightFibre(dir, context.grams(d), period),
    InsightKind.workouts => l.insightWorkouts(i.current, i.previous, period),
    InsightKind.essentialPercent => l.insightEssential(i.current, i.previous, period),
    InsightKind.screenAverage => l.insightScreen(dir, context.duration(Duration(milliseconds: d)), period),
  };
}

/// "1,200 more", "0.6 kg lower", or null when there is nothing to compare.
String? _change(BuildContext context, int? now, int? before, String Function(int) fmt, {bool lowerWord = false}) {
  if (now == null || before == null) return null;
  final l = context.l10n;
  final d = now - before;
  if (d == 0) return l.sameAsBefore;
  return lowerWord
      ? (d > 0 ? l.higherBy(fmt(d.abs())) : l.lowerBy(fmt(d.abs())))
      : (d > 0 ? l.moreBy(fmt(d.abs())) : l.lessBy(fmt(d.abs())));
}

/// Insights tab (approved design "Insights: week").
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  ReportPeriod _period = ReportPeriod.week;
  DateRange? _range;

  DateRange _current(LocalDate today) => _range ?? periodRange(_period, today);

  Future<void> _choose(ReportPeriod p) async {
    final today = ref.read(todayProvider);
    if (p == ReportPeriod.custom) {
      final picked = await showFbSheet<DateRange>(context, CustomRangeSheet(today: today, initial: _range));
      if (picked == null) return;
      setState(() {
        _period = p;
        _range = picked;
      });
      return;
    }
    setState(() {
      _period = p;
      _range = periodRange(p, today);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final range = _current(today);
    final prevRange = previousPeriod(_period, range);
    final now = ref.watch(periodReportProvider(range));
    final before = ref.watch(periodReportProvider(prevRange)).value;
    final units = ref.watch(unitsProvider);
    final atEnd = !range.to.isBefore(today);
    final sel = (period: _period, range: range);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabInsights)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.xs, FbSpace.lg, FbSpace.xxl),
        children: [
          FbSegmented<ReportPeriod>(
            options: {
              ReportPeriod.day: l10n.periodDay,
              ReportPeriod.week: l10n.week,
              ReportPeriod.month: l10n.month,
              ReportPeriod.custom: l10n.periodCustom,
            },
            selected: _period,
            onChanged: _choose,
          ),
          const SizedBox(height: FbSpace.sm),
          Row(
            children: [
              IconButton(
                tooltip: l10n.previousPeriod,
                onPressed: () => setState(() => _range = stepPeriod(_period, range, -1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(rangeLabel(context, range), style: context.text.bodyStrong, textAlign: TextAlign.center),
                    Text(
                      l10n.comparedWith(rangeLabel(context, prevRange)),
                      style: context.text.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.nextPeriod,
                onPressed: atEnd ? null : () => setState(() => _range = stepPeriod(_period, range, 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: FbSpace.sm),
          switch (now) {
            AsyncData(:final value) => _Body(now: value, before: before, sel: sel, units: units),
            AsyncError() => FbErrorState(message: l10n.errLoadFailed),
            _ => const Padding(padding: EdgeInsets.all(FbSpace.xl), child: FbLoading()),
          },
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.now, required this.before, required this.sel, required this.units});
  final PeriodReport now;
  final PeriodReport? before;
  final Selection sel;
  final UnitPreferences units;

  void _open(BuildContext context, ReportKind k) => context.push(Routes.report(k.name), extra: sel);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final b = before;
    final insights = b == null ? const <Insight>[] : insightsFor(now, b);
    final days = now.range.days;
    String logged(Metric m) => l.daysLogged(now.daysWith(m), days);
    final workouts = now.workouts;

    Widget card(ReportKind k, String title, String value, String? sub) =>
        _StatCard(title: title, value: value, sub: sub, onTap: () => _open(context, k));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FbCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.inBrief, style: context.text.bodyStrong),
              const SizedBox(height: FbSpace.sm),
              if (insights.isEmpty)
                Text(l.noInsightsYet, style: context.text.bodySmall)
              else
                for (final i in insights)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FbSpace.xs),
                    child: Text('• ${insightSentence(context, i, sel.period, units)}', style: context.text.body),
                  ),
              const SizedBox(height: FbSpace.xs),
              Text(l.insightsDisclaimer, style: context.text.caption),
            ],
          ),
        ),
        const SizedBox(height: FbSpace.md),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 340 && MediaQuery.textScalerOf(context).scale(1) < 1.6 ? 2 : 1;
            final cards = [
              card(
                ReportKind.steps,
                l.stepsDailyAverage,
                now.average(Metric.steps) == null ? '–' : context.number(now.average(Metric.steps)!),
                _change(context, now.average(Metric.steps), b?.average(Metric.steps), context.number) ??
                    logged(Metric.steps),
              ),
              card(
                ReportKind.weight,
                l.weightLatest,
                now.latest(Metric.weightG) == null ? '–' : context.mass(now.latest(Metric.weightG)!, units.mass),
                _change(
                      context,
                      now.latest(Metric.weightG),
                      b?.latest(Metric.weightG),
                      (g) => context.mass(g, units.mass),
                      lowerWord: true,
                    ) ??
                    logged(Metric.weightG),
              ),
              card(
                ReportKind.nutrition,
                l.caloriesDailyAverage,
                now.average(Metric.kcalMilli) == null ? '–' : context.kcal(now.average(Metric.kcalMilli)!),
                logged(Metric.kcalMilli),
              ),
              card(
                ReportKind.water,
                l.waterDailyAverage,
                now.average(Metric.waterMl) == null ? '–' : context.volume(now.average(Metric.waterMl)!, units.volume),
                logged(Metric.waterMl),
              ),
              card(
                ReportKind.sleep,
                l.sleepAverageNight,
                now.average(Metric.sleepMin) == null
                    ? '–'
                    : context.duration(Duration(minutes: now.average(Metric.sleepMin)!)),
                _change(
                      context,
                      now.average(Metric.sleepMin),
                      b?.average(Metric.sleepMin),
                      (m) => context.duration(Duration(minutes: m)),
                    ) ??
                    logged(Metric.sleepMin),
              ),
              card(
                ReportKind.workouts,
                l.workoutsTitle,
                context.number(workouts),
                workouts == 0
                    ? l.noneRecorded
                    : [
                        if (now.total(Metric.gymSessions) > 0) l.gymCount(now.total(Metric.gymSessions)),
                        if (now.total(Metric.walks) > 0) l.walkCount(now.total(Metric.walks)),
                        if (now.total(Metric.runs) > 0) l.runCount(now.total(Metric.runs)),
                        if (now.total(Metric.rides) > 0) l.rideCount(now.total(Metric.rides)),
                      ].join(' · '),
              ),
              card(
                ReportKind.activities,
                l.activitiesDone,
                now.essentialPercent == null ? '–' : '${now.essentialPercent}%',
                now.essentialPercent == null
                    ? l.noneScheduled
                    : l.essentialOf(now.total(Metric.essentialDone), now.total(Metric.essentialScheduled)),
              ),
              card(
                ReportKind.screenTime,
                l.screenTimeDaily,
                now.average(Metric.screenMs) == null
                    ? '–'
                    : context.duration(Duration(milliseconds: now.average(Metric.screenMs)!)),
                _change(
                      context,
                      now.average(Metric.screenMs),
                      b?.average(Metric.screenMs),
                      (ms) => context.duration(Duration(milliseconds: ms)),
                    ) ??
                    logged(Metric.screenMs),
              ),
            ];
            return Wrap(
              spacing: FbSpace.sm,
              runSpacing: FbSpace.sm,
              children: [
                for (final w in cards)
                  SizedBox(width: cols == 2 ? (c.maxWidth - FbSpace.sm) / 2 : c.maxWidth, child: w),
              ],
            );
          },
        ),
        const SizedBox(height: FbSpace.md),
        FbListCard(
          children: [
            FbListRow(
              title: l.measurementsTitle,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(context, ReportKind.measurements),
            ),
            FbListRow(
              title: l.wellnessTitle,
              subtitle: now.average(Metric.moodMilli) == null
                  ? null
                  : l.moodOutOf5((now.average(Metric.moodMilli)! / 1000).toStringAsFixed(1)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(context, ReportKind.wellness),
            ),
            FbListRow(
              title: l.junkFoodTitle,
              subtitle: l.itemsCount(now.total(Metric.junkItems)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(context, ReportKind.junk),
            ),
            FbListRow(
              title: l.gymProgression,
              subtitle: l.newRecordsCount(now.newRecords),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(context, ReportKind.gym),
            ),
            FbListRow(
              title: l.privateHistory,
              subtitle: l.unlockToView,
              leading: const Icon(Icons.lock_outline_rounded),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.privateReport),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.onTap, this.sub});
  final String title;
  final String value;
  final String? sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: true,
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FbRadius.card),
          side: BorderSide(color: context.colors.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(FbRadius.card),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 104),
            child: Padding(
              padding: const EdgeInsets.all(FbSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.bodySmall),
                  const SizedBox(height: FbSpace.xs),
                  Text(value, style: context.text.title),
                  if (sub != null) Text(sub!, style: context.text.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Custom range (approved design): presets or two dates.
class CustomRangeSheet extends StatefulWidget {
  const CustomRangeSheet({required this.today, this.initial, super.key});
  final LocalDate today;
  final DateRange? initial;

  @override
  State<CustomRangeSheet> createState() => _CustomRangeSheetState();
}

class _CustomRangeSheetState extends State<CustomRangeSheet> {
  late DateRange _range = widget.initial ?? (from: widget.today.addDays(-13), to: widget.today);

  DateTime _dt(LocalDate d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = widget.today;
    final presets = <String, DateRange>{
      l.last14Days: (from: t.addDays(-13), to: t),
      l.last90Days: (from: t.addDays(-89), to: t),
      l.thisYear: (from: LocalDate(t.year, 1, 1), to: t),
    };
    return FbSheetBody(
      title: l.customRange,
      children: [
        Wrap(
          spacing: FbSpace.sm,
          runSpacing: FbSpace.sm,
          children: [
            for (final e in presets.entries)
              FbToggleChip(label: e.key, selected: _range == e.value, onTap: () => setState(() => _range = e.value)),
          ],
        ),
        const SizedBox(height: FbSpace.md),
        FbPickerField(
          label: l.dates,
          valueText:
              '${context.shortDate(_range.from)} ${_range.from.year} – ${context.shortDate(_range.to)} ${_range.to.year}',
          onTap: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: _dt(t),
              initialDateRange: DateTimeRange(start: _dt(_range.from), end: _dt(_range.to)),
            );
            if (picked != null) {
              setState(
                () => _range = (from: LocalDate.fromDateTime(picked.start), to: LocalDate.fromDateTime(picked.end)),
              );
            }
          },
        ),
        const SizedBox(height: FbSpace.sm),
        Text(l.customRangeHelp(_range.days, rangeLabel(context, _range.previous)), style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l.showReport, onPressed: () => Navigator.of(context).pop(_range)),
      ],
    );
  }
}

/// A table row: label, this period, previous period, formatter.
typedef ReportRow = (String, int?, int?, String Function(int));

/// One domain's report for the chosen period (approved design "Report").
class ReportScreen extends ConsumerWidget {
  const ReportScreen({required this.kind, required this.selection, super.key});
  final ReportKind kind;
  final Selection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final range = selection.range;
    final prevRange = previousPeriod(selection.period, range);
    final now = ref.watch(periodReportProvider(range)).value;
    final before = ref.watch(periodReportProvider(prevRange)).value;
    final u = ref.watch(unitsProvider);
    final title = _title(l, kind);
    if (now == null || before == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const FbLoading(),
      );
    }

    String mass(int g) => context.mass(g, u.mass);
    String dur(int min) => context.duration(Duration(minutes: min));
    String screen(int ms) => context.duration(Duration(milliseconds: ms));
    String km(int m) => l.valueKm((m / 1000).toStringAsFixed(1));
    String score(int milli) => (milli / 1000).toStringAsFixed(1);
    String pct(int v) => '$v%';

    final (Metric? chart, List<ReportRow> rows) = switch (kind) {
      ReportKind.steps => (
        Metric.steps,
        <ReportRow>[(l.stepsDailyAverage, now.average(Metric.steps), before.average(Metric.steps), context.number)],
      ),
      ReportKind.weight => (
        Metric.weightG,
        <ReportRow>[(l.weightLatest, now.latest(Metric.weightG), before.latest(Metric.weightG), mass)],
      ),
      ReportKind.nutrition => (
        Metric.kcalMilli,
        <ReportRow>[
          (l.calories, now.average(Metric.kcalMilli), before.average(Metric.kcalMilli), context.kcal),
          (l.protein, now.average(Metric.proteinMg), before.average(Metric.proteinMg), context.grams),
          (l.carbohydrates, now.average(Metric.carbsMg), before.average(Metric.carbsMg), context.grams),
          (l.fat, now.average(Metric.fatMg), before.average(Metric.fatMg), context.grams),
          (l.fibre, now.average(Metric.fibreMg), before.average(Metric.fibreMg), context.grams),
        ],
      ),
      ReportKind.water => (
        Metric.waterMl,
        <ReportRow>[
          (
            l.waterDailyAverage,
            now.average(Metric.waterMl),
            before.average(Metric.waterMl),
            (v) => context.volume(v, u.volume),
          ),
        ],
      ),
      ReportKind.sleep => (
        Metric.sleepMin,
        <ReportRow>[(l.sleepAverageNight, now.average(Metric.sleepMin), before.average(Metric.sleepMin), dur)],
      ),
      ReportKind.workouts => (
        null,
        <ReportRow>[
          (l.walking, now.total(Metric.walks), before.total(Metric.walks), context.number),
          (l.walkingDistance, now.total(Metric.walkM), before.total(Metric.walkM), km),
          (l.running, now.total(Metric.runs), before.total(Metric.runs), context.number),
          (l.runningDistance, now.total(Metric.runM), before.total(Metric.runM), km),
          (l.cycling, now.total(Metric.rides), before.total(Metric.rides), context.number),
          (l.cyclingDistance, now.total(Metric.cycleM), before.total(Metric.cycleM), km),
          (l.gymSessions, now.total(Metric.gymSessions), before.total(Metric.gymSessions), context.number),
        ],
      ),
      ReportKind.gym => (
        Metric.gymSessions,
        <ReportRow>[
          (l.gymSessions, now.total(Metric.gymSessions), before.total(Metric.gymSessions), context.number),
          (l.newRecords, now.newRecords, before.newRecords, context.number),
        ],
      ),
      ReportKind.activities => (
        null,
        <ReportRow>[
          (l.essentialDonePercent, now.essentialPercent, before.essentialPercent, pct),
          (l.essentialDoneCount, now.total(Metric.essentialDone), before.total(Metric.essentialDone), context.number),
          (
            l.essentialScheduledCount,
            now.total(Metric.essentialScheduled),
            before.total(Metric.essentialScheduled),
            context.number,
          ),
        ],
      ),
      ReportKind.screenTime => (
        Metric.screenMs,
        <ReportRow>[(l.screenTimeDaily, now.average(Metric.screenMs), before.average(Metric.screenMs), screen)],
      ),
      ReportKind.wellness => (
        null,
        <ReportRow>[
          (l.wMood, now.average(Metric.moodMilli), before.average(Metric.moodMilli), score),
          (l.wEnergy, now.average(Metric.energyMilli), before.average(Metric.energyMilli), score),
          (l.wStress, now.average(Metric.stressMilli), before.average(Metric.stressMilli), score),
          (l.wWellness, now.average(Metric.wellnessMilli), before.average(Metric.wellnessMilli), score),
        ],
      ),
      ReportKind.junk => (
        Metric.junkItems,
        <ReportRow>[
          (l.junkItems, now.total(Metric.junkItems), before.total(Metric.junkItems), context.number),
          (l.junkDays, now.daysWith(Metric.junkItems), before.daysWith(Metric.junkItems), context.number),
        ],
      ),
      ReportKind.measurements => (
        null,
        <ReportRow>[
          for (final t in now.measurements.keys)
            (
              measurementName(l, t),
              now.measurements[t],
              before.measurements[t],
              (v) => measurementValue(l, v, t, u.length),
            ),
        ],
      ),
    };

    final missing = chart == null ? 0 : range.days - now.daysWith(chart);
    final insights = insightsFor(now, before, limit: 10).where((i) => _belongs(i.kind, kind)).toList();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          Text(
            '${rangeLabel(context, range)} · ${l.comparedWith(rangeLabel(context, prevRange))}',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: FbSpace.md),
          if (chart != null && range.days > 1) ...[
            _ReportChart(report: now, metric: chart, summary: _chartSummary(context, now, chart, rows)),
            if (missing > 0) ...[
              const SizedBox(height: FbSpace.xs),
              Text(l.daysWithoutRecords(missing), style: context.text.caption),
            ],
            const SizedBox(height: FbSpace.md),
          ],
          if (rows.isEmpty)
            FbEmptyHint(l.noRecordsInPeriod, boxed: true)
          else
            FbCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _TableRow(l.thisPeriod, l.previousColumn, header: true, label: ''),
                  for (final (label, a, b, fmt) in rows)
                    _TableRow(a == null ? '–' : fmt(a), b == null ? '–' : fmt(b), label: label),
                ],
              ),
            ),
          if (insights.isNotEmpty) ...[
            const SizedBox(height: FbSpace.md),
            FbCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.inBrief, style: context.text.bodyStrong),
                  const SizedBox(height: FbSpace.xs),
                  for (final i in insights)
                    Text(insightSentence(context, i, selection.period, u), style: context.text.body),
                ],
              ),
            ),
          ],
          const SizedBox(height: FbSpace.md),
          Text(l.reportNote, style: context.text.caption),
        ],
      ),
    );
  }

  static bool _belongs(InsightKind i, ReportKind k) => switch (i) {
    InsightKind.stepsAverage => k == ReportKind.steps,
    InsightKind.sleepAverage => k == ReportKind.sleep,
    InsightKind.weightLatest => k == ReportKind.weight,
    InsightKind.waterAverage => k == ReportKind.water,
    InsightKind.kcalAverage || InsightKind.proteinAverage || InsightKind.fibreAverage => k == ReportKind.nutrition,
    InsightKind.workouts => k == ReportKind.workouts,
    InsightKind.essentialPercent => k == ReportKind.activities,
    InsightKind.screenAverage => k == ReportKind.screenTime,
  };

  static String _title(AppLocalizations l, ReportKind k) => switch (k) {
    ReportKind.steps => l.stepsTitle,
    ReportKind.weight => l.weightTitle,
    ReportKind.nutrition => l.nutritionReport,
    ReportKind.water => l.waterTitle,
    ReportKind.sleep => l.sleepTitle,
    ReportKind.workouts => l.workoutsTitle,
    ReportKind.activities => l.activitiesDone,
    ReportKind.screenTime => l.screenTimeTitle,
    ReportKind.measurements => l.measurementsTitle,
    ReportKind.wellness => l.wellnessTitle,
    ReportKind.junk => l.junkFoodTitle,
    ReportKind.gym => l.gymProgression,
  };

  static String _chartSummary(
    BuildContext context,
    PeriodReport r,
    Metric m,
    List<(String, int?, int?, String Function(int))> rows,
  ) {
    final l = context.l10n;
    final first = rows.isEmpty ? null : rows.first;
    return l.reportChartSummary(
      r.daysWith(m),
      r.range.days,
      first == null || first.$2 == null ? '–' : '${first.$1}: ${first.$4(first.$2!)}',
    );
  }
}

class _ReportChart extends StatelessWidget {
  const _ReportChart({required this.report, required this.metric, required this.summary});
  final PeriodReport report;
  final Metric metric;
  final String summary;

  /// Display value of a base-unit integer.
  double _display(int v) => switch (metric) {
    Metric.kcalMilli => v / 1000,
    Metric.weightG => v / 1000,
    Metric.screenMs => v / 3600000,
    Metric.sleepMin => v / 60,
    _ => v.toDouble(),
  };

  @override
  Widget build(BuildContext context) {
    final r = report.range;
    final s = report.of(metric);
    final weekly = r.days > 31;
    final values = <double>[];
    final labels = <String>[];
    if (weekly) {
      for (var start = r.from; !start.isAfter(r.to); start = start.addDays(7)) {
        final week = [for (var i = 0; i < 7; i++) s[start.addDays(i)]].whereType<int>().toList();
        values.add(week.isEmpty ? 0 : _display(week.fold(0, (a, b) => a + b) ~/ week.length));
        labels.add('${start.day}/${start.month}');
      }
    } else {
      for (final d in r.dates) {
        values.add(s[d] == null ? 0 : _display(s[d]!));
        labels.add(r.days <= 7 ? context.dayLabel(d).split(' ').first : '${d.day}');
      }
    }
    final step = (labels.length / 7).ceil();
    return FbChartCard(
      summary: summary,
      chart: FbBarChart(
        values: values,
        bottomLabel: (i) => i % step == 0 && i < labels.length ? labels[i] : '',
        leftLabel: (y) => y >= 100 ? context.number(y.round()) : y.toStringAsFixed(y < 10 ? 1 : 0),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow(this.now, this.before, {required this.label, this.header = false});
  final String label;
  final String now;
  final String before;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header ? context.text.caption : context.text.body;
    return MergeSemantics(
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: FbSpace.lg, vertical: FbSpace.sm),
        decoration: BoxDecoration(
          border: header ? null : Border(top: BorderSide(color: context.colors.outline.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(label, style: style)),
            Expanded(
              flex: 2,
              child: Text(now, textAlign: TextAlign.end, style: header ? style : context.text.bodyStrong),
            ),
            Expanded(
              flex: 2,
              child: Text(before, textAlign: TextAlign.end, style: header ? style : context.text.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
