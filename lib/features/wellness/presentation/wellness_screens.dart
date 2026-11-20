import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../../sleep/domain/sleep_math.dart';
import '../domain/wellness.dart';

/// Wellness check-in (PRD §5.10): four 1-to-5 scales and a note.
class CheckinScreen extends ConsumerStatefulWidget {
  const CheckinScreen({super.key});

  @override
  ConsumerState<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends ConsumerState<CheckinScreen> {
  int? _energy;
  int? _mood;
  int? _stress;
  int? _overall;
  String _note = '';
  int _formKey = 0;
  bool _incomplete = false;
  bool _busy = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    if ([_energy, _mood, _stress, _overall].contains(null)) {
      setState(() => _incomplete = true);
      return;
    }
    setState(() => _busy = true);
    final result = await ref
        .read(wellnessRepositoryProvider)
        .add(
          WellnessScores(energy: _energy!, mood: _mood!, stress: _stress!, wellness: _overall!),
          notes: _note,
        );
    if (!mounted) return;
    if (result.isOk) {
      showFbSnackBar(context, l10n.checkinSaved);
      setState(() {
        _energy = _mood = _stress = _overall = null;
        _note = '';
        _formKey++;
        _incomplete = false;
      });
    } else {
      showFbSnackBar(context, l10n.errSaveFailed);
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.checkinTitle),
        actions: [TextButton(onPressed: () => context.push(Routes.checkinHistory), child: Text(l10n.history))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: ValueKey(_formKey),
                padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
                children: [
                  Text(l10n.checkinIntro, style: context.text.bodySmall),
                  const SizedBox(height: FbSpace.lg),
                  FbCard(
                    child: Column(
                      children: [
                        FbScoreRow(
                          label: l10n.scaleEnergy,
                          value: _energy,
                          onChanged: (v) => setState(() => _energy = v),
                        ),
                        const SizedBox(height: FbSpace.lg),
                        FbScoreRow(label: l10n.scaleMood, value: _mood, onChanged: (v) => setState(() => _mood = v)),
                        const SizedBox(height: FbSpace.lg),
                        FbScoreRow(
                          label: l10n.scaleStress,
                          value: _stress,
                          onChanged: (v) => setState(() => _stress = v),
                        ),
                        const SizedBox(height: FbSpace.lg),
                        FbScoreRow(
                          label: l10n.scaleOverall,
                          value: _overall,
                          onChanged: (v) => setState(() => _overall = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: FbSpace.lg),
                  FbTextField(
                    label: l10n.note,
                    optional: true,
                    optionalLabel: l10n.optional,
                    value: _note,
                    hint: l10n.noteHint,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onChanged: (v) => _note = v,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(FbSpace.lg, 0, FbSpace.lg, FbSpace.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_incomplete) ...[
                    FbNotice(l10n.checkinIncomplete, isError: true),
                    const SizedBox(height: FbSpace.md),
                  ],
                  FbPrimaryButton(label: l10n.saveCheckin, onPressed: _save, busy: _busy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Daily averages of each scale next to sleep, and the list of check-ins.
class CheckinHistoryScreen extends ConsumerStatefulWidget {
  const CheckinHistoryScreen({super.key});

  @override
  ConsumerState<CheckinHistoryScreen> createState() => _CheckinHistoryScreenState();
}

class _CheckinHistoryScreenState extends ConsumerState<CheckinHistoryScreen> {
  ChartRange _range = ChartRange.month;

  Future<void> _delete(WellnessCheckin c) async {
    final l10n = context.l10n;
    final agreed = await showFbConfirm(
      context,
      title: l10n.deleteEntryTitle,
      message: l10n.deleteEntryMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!agreed) return;
    await ref.read(wellnessRepositoryProvider).delete(c.id);
    if (mounted) showFbSnackBar(context, l10n.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final start = today.addDays(-(_range.days - 1));
    final range = (from: start, to: today);
    final checkins = ref.watch(wellnessBetweenProvider(range));
    final sleep = ref.watch(sleepBetweenProvider(range)).value ?? const [];

    final sleepPerDay = <LocalDate, int>{};
    for (final e in sleep.where((e) => e.period.kind == SleepKind.night)) {
      sleepPerDay.update(
        e.period.wakeDate,
        (m) => m + e.period.duration.inMinutes,
        ifAbsent: () => e.period.duration.inMinutes,
      );
    }

    Widget scaleChart(
      String name,
      int Function(({int energy, int mood, int stress, int wellness}) m) pick,
      Map<LocalDate, ({int energy, int mood, int stress, int wellness})> means,
    ) {
      final days = means.keys.toList()..sort();
      return Padding(
        padding: const EdgeInsets.only(bottom: FbSpace.md),
        child: FbChartCard(
          title: name,
          height: 120,
          summary: l10n.wellnessChartSummary(name, _range.days),
          chart: FbLineChart(
            points: [for (final d in days) (x: dayOffset(start, d), y: pick(means[d]!) / 10)],
            minX: 0,
            maxX: (_range.days - 1).toDouble(),
            minY: 1,
            maxY: 5,
            bottomInterval: (_range.days / 3).ceilToDouble(),
            bottomLabel: (x) => context.shortDate(start.addDays(x.round())),
            leftLabel: (y) => y.toStringAsFixed(0),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.wellnessHistoryTitle)),
      body: checkins.when(
        loading: () => FbLoading(semanticLabel: l10n.loading),
        error: (_, _) => FbErrorState(message: l10n.errSaveFailed),
        data: (list) {
          final means = dailyMeansTenths(list);
          return ListView(
            padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
            children: [
              FbSegmented<ChartRange>(
                semanticLabel: l10n.rangeLabel,
                options: {
                  ChartRange.week: l10n.range7,
                  ChartRange.month: l10n.range30,
                  ChartRange.quarter: l10n.range90,
                },
                selected: _range,
                onChanged: (r) => setState(() => _range = r),
              ),
              const SizedBox(height: FbSpace.md),
              Text(l10n.wellnessHistoryNote, style: context.text.caption),
              const SizedBox(height: FbSpace.md),
              if (list.isEmpty)
                FbEmptyHint(l10n.noEntries, boxed: true)
              else ...[
                scaleChart(l10n.scaleEnergy, (m) => m.energy, means),
                scaleChart(l10n.scaleMood, (m) => m.mood, means),
                scaleChart(l10n.scaleStress, (m) => m.stress, means),
                scaleChart(l10n.scaleOverall, (m) => m.wellness, means),
                FbChartCard(
                  title: l10n.sleepHoursChart,
                  height: 120,
                  summary: l10n.sleepHoursChart,
                  chart: FbBarChart(
                    values: [for (var i = 0; i < _range.days; i++) (sleepPerDay[start.addDays(i)] ?? 0) / 60],
                    bottomLabel: (i) => context.shortDate(start.addDays(i)),
                    color: context.colors.secondary,
                  ),
                ),
                const SizedBox(height: FbSpace.xl),
                FbListCard(
                  children: [
                    for (final c in list)
                      FbListRow(
                        title: l10n.checkinRow(c.scores.energy, c.scores.mood, c.scores.stress, c.scores.wellness),
                        subtitle: [
                          '${context.dayLabel(c.localDate, today: today)} · ${context.time(c.occurredAt)}',
                          ?c.notes,
                        ].join(' · '),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          onPressed: () => _delete(c),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
