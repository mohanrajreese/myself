import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/units/units.dart';
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

/// Quick amounts in millilitres, shown in the user's unit.
const quickWaterMl = [150, 250, 500, 750];

Future<void> addWater(BuildContext context, WidgetRef ref, int ml, {DateTime? at}) async {
  final l10n = context.l10n;
  final units = ref.read(unitsProvider);
  final result = await ref.read(waterRepositoryProvider).add(ml, at: at);
  if (!context.mounted) return;
  showFbSnackBar(
    context,
    result.isOk ? l10n.waterAdded(context.volume(ml, units.volume)) : l10n.errSaveFailed,
  );
}

String _quickLabel(BuildContext context, int ml, VolumeUnit unit) =>
    '+${unit == VolumeUnit.ml ? context.number(ml) : formatVolume(ml, unit)}';

/// Water tracking (PRD §5.5).
class WaterScreen extends ConsumerStatefulWidget {
  const WaterScreen({super.key});

  @override
  ConsumerState<WaterScreen> createState() => _WaterScreenState();
}

class _WaterScreenState extends ConsumerState<WaterScreen> {
  ChartRange _range = ChartRange.week;

  Future<void> _remove(String id, String label) async {
    final l10n = context.l10n;
    final agreed = await showFbConfirm(
      context,
      title: l10n.removeEntryTitle,
      message: label,
      confirmLabel: l10n.remove,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!agreed) return;
    await ref.read(waterRepositoryProvider).remove(id);
    if (mounted) showFbSnackBar(context, l10n.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final today = ref.watch(todayProvider);
    final units = ref.watch(unitsProvider);
    final total = ref.watch(waterTotalOnProvider(today));
    final entries = ref.watch(waterOnProvider(today));
    final target = ref.watch(currentDailyGoalsProvider).value?.dailyWaterMl;
    final start = today.addDays(-(_range.days - 1));
    final totals = ref.watch(waterTotalsProvider((from: start, to: today))).value ?? const {};
    double display(int ml) => units.volume == VolumeUnit.ml
        ? ml.toDouble()
        : double.parse(formatVolume(ml, units.volume));
    final fraction = target == null || target == 0 ? null : total / target;
    final dayNames = MaterialLocalizations.of(context).narrowWeekdays;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.waterTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          FbCard(
            radius: FbRadius.hero,
            padding: const EdgeInsets.symmetric(horizontal: FbSpace.xl, vertical: FbSpace.lg),
            child: Row(
              children: [
                Expanded(
                  child: MergeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.waterToday, style: context.text.label),
                        Text(
                          context.volume(total, units.volume),
                          style: context.text.displayMetric,
                        ),
                        if (target != null)
                          Text(
                            total >= target
                                ? l10n.waterGoalReached
                                : l10n.waterToGo(
                                    context.volume(target, units.volume),
                                    context.volume(target - total, units.volume),
                                  ),
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                FbProgressRing(
                  fraction: fraction,
                  semanticLabel: l10n.waterRingLabel(((fraction ?? 0) * 100).round().clamp(0, 999)),
                ),
              ],
            ),
          ),
          const SizedBox(height: FbSpace.md),
          _QuickRow(units: units.volume),
          const SizedBox(height: FbSpace.md),
          FbChartCard(
            title: _range == ChartRange.week ? l10n.waterWeek : l10n.waterMonth,
            summary: l10n.waterChartSummary(_range.days),
            height: 150,
            chart: FbBarChart(
              values: [
                for (var i = 0; i < _range.days; i++) display(totals[start.addDays(i)] ?? 0),
              ],
              bottomLabel: (i) => _range == ChartRange.week
                  ? dayNames[start.addDays(i).weekday % 7]
                  : context.shortDate(start.addDays(i)),
              target: target == null ? null : display(target),
              color: context.colors.secondary,
            ),
            footer: FbSegmented<ChartRange>(
              semanticLabel: l10n.rangeLabel,
              options: {ChartRange.week: l10n.waterWeek, ChartRange.month: l10n.waterMonth},
              selected: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
          ),
          const SizedBox(height: FbSpace.xl),
          FbSectionTitle(l10n.waterEntriesToday),
          const SizedBox(height: FbSpace.sm),
          entries.when(
            loading: () => FbLoading(semanticLabel: l10n.loading),
            error: (_, _) => FbErrorState(message: l10n.errSaveFailed),
            data: (list) => list.isEmpty
                ? FbEmptyHint(l10n.noEntries)
                : FbListCard(
                    children: [
                      for (final e in list)
                        FbListRow(
                          leading: SizedBox(
                            width: 72,
                            child: Text(context.time(e.occurredAt), style: context.text.label),
                          ),
                          title: context.volume(e.amountMl, units.volume),
                          trailing: TextButton(
                            onPressed: () => _remove(
                              e.id,
                              l10n.removeWaterLabel(
                                context.volume(e.amountMl, units.volume),
                                context.time(e.occurredAt),
                              ),
                            ),
                            child: Text(
                              l10n.remove,
                              semanticsLabel: l10n.removeWaterLabel(
                                context.volume(e.amountMl, units.volume),
                                context.time(e.occurredAt),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickRow extends ConsumerWidget {
  const _QuickRow({required this.units});
  final VolumeUnit units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Row(
      children: [
        for (final ml in quickWaterMl.take(3)) ...[
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, FbSize.primaryButton)),
              onPressed: () => addWater(context, ref, ml),
              child: Text(
                _quickLabel(context, ml, units),
                semanticsLabel: l10n.quickAddAmount(context.volume(ml, units)),
              ),
            ),
          ),
          const SizedBox(width: FbSpace.sm),
        ],
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, FbSize.primaryButton)),
            onPressed: () => showFbSheet<void>(context, const WaterSheet()),
            child: Text(l10n.waterOther),
          ),
        ),
      ],
    );
  }
}

/// Quick-add water sheet (approved design "Quick add sheet (water)").
class WaterSheet extends ConsumerStatefulWidget {
  const WaterSheet({super.key});

  @override
  ConsumerState<WaterSheet> createState() => _WaterSheetState();
}

class _WaterSheetState extends ConsumerState<WaterSheet> {
  String _text = '';
  DateTime? _at;
  String? _error;

  Future<void> _quick(int ml) async {
    await addWater(context, ref, ml);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final ml = millilitresFromText(_text, ref.read(unitsProvider).volume);
    if (ml == null || ml < 1 || ml > 5000) {
      setState(() => _error = ml == null ? l10n.errInvalidNumber : l10n.errOutOfRange);
      return;
    }
    await addWater(context, ref, ml, at: _at);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final units = ref.watch(unitsProvider).volume;
    final today = ref.watch(todayProvider);
    final total = ref.watch(waterTotalOnProvider(today));
    final target = ref.watch(currentDailyGoalsProvider).value?.dailyWaterMl;
    final now = ref.watch(clockProvider).now();
    return FbSheetBody(
      title: l10n.addWaterTitle,
      trailing: Text(
        target == null
            ? context.volume(total, units)
            : l10n.ofTargetValue(context.volume(total, units), context.volume(target, units)),
        style: context.text.bodySmall,
      ),
      children: [
        Row(
          children: [
            for (final ml in quickWaterMl) ...[
              if (ml != quickWaterMl.first) const SizedBox(width: FbSpace.sm),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, FbSize.primaryButton)),
                  onPressed: () => _quick(ml),
                  child: Text(
                    _quickLabel(context, ml, units),
                    semanticsLabel: l10n.quickAddAmount(context.volume(ml, units)),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: FbSpace.sm),
        Text(l10n.waterOneTap, style: context.text.caption),
        const SizedBox(height: FbSpace.lg),
        FbTextField(
          label: l10n.otherAmount,
          value: _text,
          suffix: units == VolumeUnit.ml ? l10n.unitMl : l10n.unitFlOz,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: FbTextField.decimal,
          errorText: _error,
          onChanged: (v) => setState(() => _text = v),
        ),
        const SizedBox(height: FbSpace.lg),
        FbDateTimeField(
          label: l10n.timeLabel,
          value: _at ?? now,
          last: now,
          onChanged: (v) => setState(() => _at = v),
        ),
        const SizedBox(height: FbSpace.xl),
        FbPrimaryButton(label: l10n.save, onPressed: _save),
      ],
    );
  }
}
