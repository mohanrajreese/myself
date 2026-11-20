import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/fitness_providers.dart';
import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../core/utils/local_date.dart';
import '../../../core/widgets/fb_card.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_progress.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/step_repository.dart';

/// Steps dashboard (approved designs "Steps" and "Step counting states").
class StepsScreen extends ConsumerStatefulWidget {
  const StepsScreen({super.key});

  @override
  ConsumerState<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends ConsumerState<StepsScreen> {
  bool _month = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Re-check after the user returns from the permission settings page.
    _lifecycle = AppLifecycleListener(onResume: () => ref.invalidate(stepStatusProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) => syncSteps(ref));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    final granted = await ref.read(stepServiceProvider).enable();
    ref.invalidate(stepStatusProvider);
    if (!granted && mounted) showFbSnackBar(context, context.l10n.stepsPermissionRefused);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(stepStatusProvider);
    final s = status.value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cardSteps)),
      body: s == null
          ? (status.hasError ? FbErrorState(message: l10n.errLoadFailed) : const FbLoading())
          : ListView(
              padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
              children: !s.supported
                  ? [
                      _StateCard(
                        icon: Icons.do_not_step_rounded,
                        title: l10n.stepsUnsupportedTitle,
                        body: l10n.stepsUnsupportedBody,
                        action: OutlinedButton(
                          onPressed: () => context.push(Routes.logCardio('walk')),
                          child: Text(l10n.logAWalk),
                        ),
                      ),
                    ]
                  : !s.permission
                  ? [
                      _StateCard(
                        icon: Icons.directions_walk_rounded,
                        title: l10n.stepsIntroTitle,
                        body: l10n.stepsIntroBody,
                        action: FilledButton(onPressed: _enable, child: Text(l10n.continueAction)),
                      ),
                    ]
                  : _dashboard(context, s),
            ),
    );
  }

  List<Widget> _dashboard(
    BuildContext context,
    ({bool supported, bool permission, bool continuous, DateTime? lastReading}) s,
  ) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final goal = ref.watch(currentDailyGoalsProvider).value?.dailySteps;
    final day = ref.watch(stepDayProvider(today)).value;
    final total = day?.total ?? 0;
    final from = today.addDays(_month ? -29 : -6);
    final range = ref.watch(stepRangeProvider((from: from, to: today))).value ?? const <StepDay>[];
    final byDate = {for (final d in range) d.date: d};
    final values = [
      for (var d = from; !d.isAfter(today); d = d.addDays(1)) (byDate[d]?.total ?? 0).toDouble(),
    ];
    final past7 = [
      for (final d in range)
        if (d.date.isAfter(today.addDays(-7)) && d.date != today) d.total,
    ];
    final avg7 = past7.isEmpty ? null : past7.reduce((a, b) => a + b) ~/ past7.length;
    final prevFrom = today.addDays(-59);
    final prevRange =
        ref.watch(stepRangeProvider((from: prevFrom, to: today.addDays(-30)))).value ??
        const <StepDay>[];
    final thisMonth = [
      for (final d
          in ref.watch(stepRangeProvider((from: today.addDays(-29), to: today))).value ??
              const <StepDay>[])
        d.total,
    ];
    final trend = prevRange.isEmpty || thisMonth.isEmpty
        ? null
        : ((thisMonth.reduce((a, b) => a + b) / thisMonth.length) /
                      (prevRange.map((d) => d.total).reduce((a, b) => a + b) / prevRange.length) *
                      100 -
                  100)
              .round();
    final uncertainDays = [
      for (final d in range)
        if (d.isUncertain) d,
    ];
    return [
      FbCard(
        child: Column(
          children: [
            FbProgressRing(
              fraction: goal == null || goal == 0 ? null : (total / goal).clamp(0, 1),
              semanticLabel: goal == null
                  ? l10n.stepsTodayLabel(context.number(total))
                  : l10n.stepsRingValue(context.number(total), context.number(goal)),
              size: 160,
            ),
            const SizedBox(height: FbSpace.md),
            Text(
              '${day?.isUncertain ?? false ? '≈ ' : ''}${context.number(total)}',
              style: context.text.displayMetric,
            ),
            Text(
              goal == null
                  ? l10n.noTarget
                  : l10n.stepsPercentOf(
                      (total * 100 ~/ (goal == 0 ? 1 : goal)),
                      context.number(goal),
                    ),
              style: context.text.caption,
            ),
            if ((day?.manualAdjustment ?? 0) != 0)
              Text(
                l10n.stepsAdjusted(_signed(context, day!.manualAdjustment)),
                style: context.text.caption,
              ),
            const SizedBox(height: FbSpace.md),
            Row(
              children: [
                _Stat(
                  goal == null ? '—' : context.number((goal - total).clamp(0, goal)),
                  l10n.stepsToGo,
                ),
                _Stat(avg7 == null ? '—' : context.number(avg7), l10n.steps7Avg),
                _Stat(
                  trend == null ? '—' : '${trend >= 0 ? '+' : ''}$trend%',
                  l10n.stepsVsLastMonth,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: FbSpace.lg),
      FbSegmented<bool>(
        options: {false: l10n.waterWeek, true: l10n.waterMonth},
        selected: _month,
        onChanged: (v) => setState(() => _month = v),
      ),
      const SizedBox(height: FbSpace.sm),
      FbChartCard(
        summary: l10n.stepsChartSummary(values.length),
        chart: FbBarChart(
          values: values,
          target: goal?.toDouble(),
          bottomLabel: (i) => context.shortDate(from.addDays(i)).split(' ').first,
          leftLabel: (y) => context.number(y.round()),
        ),
      ),
      for (final d
          in uncertainDays.where((d) => d.gapCount > 0 || d.uncertainSteps > 0).take(3)) ...[
        const SizedBox(height: FbSpace.xs),
        FbNotice(
          d.gapCount > 0
              ? l10n.stepsGapNotice(context.dayLabel(d.date, today: today))
              : l10n.stepsUncertainNotice(
                  context.dayLabel(d.date, today: today),
                  context.number(d.uncertainSteps),
                ),
        ),
      ],
      const SizedBox(height: FbSpace.lg),
      FbListCard(
        children: [
          FbListRow(
            title: l10n.stepsSensor,
            subtitle: s.continuous ? l10n.stepsSensorContinuous : l10n.stepsSensorSnapshots,
            leading: Icon(
              Icons.check_circle_rounded,
              color: context.colors.success,
              semanticLabel: l10n.allowed,
            ),
          ),
          FbSwitchRow(
            title: l10n.stepsContinuous,
            subtitle: l10n.stepsContinuousHelp,
            value: s.continuous,
            onChanged: (v) async {
              await ref.read(stepServiceProvider).setContinuous(v);
              ref.invalidate(stepStatusProvider);
            },
          ),
          FbListRow(
            title: l10n.stepsLastReading,
            subtitle: s.lastReading == null
                ? l10n.stepsNoReadingYet
                : '${context.dayLabel(LocalDate.fromDateTime(s.lastReading!.toLocal()), today: today)} ${context.time(s.lastReading!)}',
          ),
          FbListRow(
            title: l10n.stepsAdjustToday,
            subtitle: l10n.stepsAdjustHelp,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showFbSheet<void>(context, StepAdjustSheet(date: today, day: day)),
          ),
        ],
      ),
      const SizedBox(height: FbSpace.md),
      Text(l10n.stepsNote, style: context.text.caption),
    ];
  }

  static String _signed(BuildContext context, int v) =>
      '${v > 0 ? '+' : '−'}${context.number(v.abs())}';
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: MergeSemantics(
      child: Column(
        children: [
          Text(value, style: context.text.bodyStrong.copyWith(fontSize: 17)),
          Text(label, style: context.text.caption, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) => FbCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 32, color: context.colors.primary),
        const SizedBox(height: FbSpace.sm),
        Text(title, style: context.text.title),
        const SizedBox(height: FbSpace.xs),
        Text(body, style: context.text.bodySmall),
        const SizedBox(height: FbSpace.md),
        action,
      ],
    ),
  );
}

/// Labelled manual correction (approved design "Adjust steps", §5.6).
class StepAdjustSheet extends ConsumerStatefulWidget {
  const StepAdjustSheet({required this.date, this.day, super.key});
  final LocalDate date;
  final StepDay? day;

  @override
  ConsumerState<StepAdjustSheet> createState() => _StepAdjustSheetState();
}

class _StepAdjustSheetState extends ConsumerState<StepAdjustSheet> {
  bool _add = true;
  String _value = '';
  String? _error;

  Future<void> _save() async {
    final l10n = context.l10n;
    final n = int.tryParse(_value.trim().replaceAll(',', ''));
    if (n == null || n <= 0 || n > 100000) return setState(() => _error = l10n.errOutOfRange);
    final result = await ref.read(stepRepositoryProvider).adjust(widget.date, _add ? n : -n);
    if (!mounted) return;
    if (!result.isOk) return setState(() => _error = l10n.errSaveFailed);
    showFbSnackBar(context, l10n.stepsAdjustmentSaved);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = widget.day;
    final counted = d?.sensorSteps ?? 0;
    final current = d?.manualAdjustment ?? 0;
    final n = int.tryParse(_value.trim().replaceAll(',', '')) ?? 0;
    final next = (counted + current + (_add ? n : -n)).clamp(0, 1 << 31);
    return FbSheetBody(
      title: l10n.stepsAdjustTitle,
      children: [
        Text(
          l10n.stepsCountedAndAdjusted(
            context.number(counted),
            current == 0 ? l10n.none : context.number(current),
          ),
          style: context.text.bodySmall,
        ),
        const SizedBox(height: FbSpace.md),
        FbSegmented<bool>(
          options: {true: l10n.add, false: l10n.remove},
          selected: _add,
          onChanged: (v) => setState(() => _add = v),
        ),
        const SizedBox(height: FbSpace.md),
        FbTextField(
          label: l10n.cardSteps,
          value: _value,
          onChanged: (v) => setState(() => _value = v),
          errorText: _error,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: FbSpace.md),
        Text(l10n.stepsNewTotal(context.number(next)), style: context.text.bodyStrong),
        const SizedBox(height: FbSpace.lg),
        FbPrimaryButton(label: l10n.stepsSaveAdjustment, onPressed: _save),
      ],
    );
  }
}
