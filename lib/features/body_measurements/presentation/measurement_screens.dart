import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/routes.dart';
import '../../../app/tracking_providers.dart';
import '../../../core/units/decimal_text.dart';
import '../../../core/units/units.dart';
import '../../../core/widgets/fb_charts.dart';
import '../../../core/widgets/fb_choice.dart';
import '../../../core/widgets/fb_fields.dart';
import '../../../core/widgets/fb_format.dart';
import '../../../core/widgets/fb_scaffolds.dart';
import '../../../core/widgets/fb_sheet.dart';
import '../../../core/widgets/fb_states.dart';
import '../../../core/widgets/l10n.dart';
import '../../../core/widgets/tokens.dart';
import '../domain/measurements.dart';

String measurementName(AppLocalizations l10n, String type) => switch (type) {
  MeasurementTypes.waist => l10n.mWaist,
  MeasurementTypes.chest => l10n.mChest,
  MeasurementTypes.hips => l10n.mHips,
  MeasurementTypes.neck => l10n.mNeck,
  MeasurementTypes.arm => l10n.mArm,
  MeasurementTypes.thigh => l10n.mThigh,
  MeasurementTypes.bodyFat => l10n.mBodyFat,
  _ => type.startsWith('custom:') ? type.substring(7) : type,
};

/// Thousandths of a centimetre (or percent) in the user's length unit.
String measurementValue(AppLocalizations l10n, int valueMilli, String type, LengthUnit length) {
  if (MeasurementTypes.isPercent(type)) {
    return '${formatScaled(valueMilli, 3, decimals: 1)} ${l10n.unitPercent}';
  }
  if (length == LengthUnit.cm) return '${formatScaled(valueMilli, 3, decimals: 1)} ${l10n.unitCm}';
  return '${formatScaled(divRound(valueMilli * 100, 254), 3, decimals: 1)} ${l10n.unitIn}';
}

/// Parses what the user typed into thousandths of a centimetre (or percent).
int? parseMeasurement(String text, String type, LengthUnit length) {
  final milli = parseScaled(text, 3);
  if (milli == null || milli < 0) return null;
  if (MeasurementTypes.isPercent(type) || length == LengthUnit.cm) return milli;
  return divRound(milli * 254, 100);
}

/// Latest value of each measurement type (PRD §5.3).
class MeasurementsScreen extends ConsumerWidget {
  const MeasurementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final latest = ref.watch(latestMeasurementsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.measurementsTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: FbSpace.sm),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(64, FbSize.touch)),
              onPressed: () => showFbSheet<void>(context, const MeasurementSheet()),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.addEntry),
            ),
          ),
        ],
      ),
      body: latest.when(
        loading: () => FbLoading(semanticLabel: l10n.loading),
        error: (_, _) => FbErrorState(message: l10n.errSaveFailed),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
          children: [
            if (items.isEmpty)
              FbEmptyHint(l10n.measurementsNone, boxed: true)
            else
              FbListCard(children: [for (final m in items) _LatestRow(measurement: m)]),
            const SizedBox(height: FbSpace.md),
            Text(l10n.measurementsHelp, style: context.text.caption),
          ],
        ),
      ),
    );
  }
}

class _LatestRow extends ConsumerWidget {
  const _LatestRow({required this.measurement});
  final Measurement measurement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final length = ref.watch(unitsProvider).length;
    final history = ref.watch(measurementHistoryProvider(measurement.type)).value ?? const [];
    final previous = history.length >= 2 ? history[history.length - 2] : null;
    String since;
    if (previous == null) {
      since = l10n.measurementNoEarlier;
    } else {
      final delta = measurement.valueMilli - previous.valueMilli;
      final amount = measurementValue(l10n, delta.abs(), measurement.type, length);
      final change = delta == 0
          ? l10n.changeSame
          : (delta < 0 ? l10n.changeDown(amount) : l10n.changeUp(amount));
      since = l10n.measurementSince(change, context.shortDate(previous.localDate));
    }
    return FbListRow(
      title: measurementName(l10n, measurement.type),
      subtitle: '${context.shortDate(measurement.localDate)} · $since',
      trailing: Text(
        measurementValue(l10n, measurement.valueMilli, measurement.type, length),
        style: context.text.bodyStrong.copyWith(fontSize: 18),
      ),
      onTap: () => context.push(Routes.measurementHistory(measurement.type)),
    );
  }
}

/// History and chart for one measurement type.
class MeasurementHistoryScreen extends ConsumerWidget {
  const MeasurementHistoryScreen({required this.type, super.key});
  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final length = ref.watch(unitsProvider).length;
    final history = ref.watch(measurementHistoryProvider(type)).value;
    final name = measurementName(l10n, type);
    if (history == null) {
      return Scaffold(
        appBar: AppBar(title: Text(name)),
        body: FbLoading(semanticLabel: l10n.loading),
      );
    }
    final first = history.isEmpty ? null : history.first.localDate;
    double display(int milli) =>
        double.parse(measurementValue(l10n, milli, type, length).split(' ').first);

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FbSpace.lg, FbSpace.sm, FbSpace.lg, FbSpace.xxl),
        children: [
          if (history.length >= 2)
            FbChartCard(
              summary: l10n.measurementChartSummary(
                name,
                history.length,
                measurementValue(l10n, history.last.valueMilli, type, length),
              ),
              chart: FbLineChart(
                points: [
                  for (final m in history)
                    (x: dayOffset(first!, m.localDate), y: display(m.valueMilli)),
                ],
                bottomLabel: (x) => context.shortDate(first!.addDays(x.round())),
                leftLabel: (y) => y.toStringAsFixed(0),
              ),
            ),
          const SizedBox(height: FbSpace.lg),
          if (history.isEmpty)
            FbEmptyHint(l10n.noEntries)
          else
            FbListCard(
              children: [
                for (final m in history.reversed)
                  FbListRow(
                    title: measurementValue(l10n, m.valueMilli, type, length),
                    subtitle: [context.dayLabel(m.localDate), ?m.notes].join(' · '),
                    trailing: TextButton(
                      onPressed: () => showFbSheet<void>(context, MeasurementSheet(existing: m)),
                      child: Text(
                        l10n.edit,
                        semanticsLabel: l10n.editEntryLabel(context.shortDate(m.localDate)),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Adds a measurement, or edits [existing].
class MeasurementSheet extends ConsumerStatefulWidget {
  const MeasurementSheet({this.existing, super.key});
  final Measurement? existing;

  @override
  ConsumerState<MeasurementSheet> createState() => _MeasurementSheetState();
}

class _MeasurementSheetState extends ConsumerState<MeasurementSheet> {
  late String _type = widget.existing?.type ?? MeasurementTypes.waist;
  String? _text;
  late String _note = widget.existing?.notes ?? '';
  String? _error;
  bool _busy = false;

  Future<void> _addCustom() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.customTypeTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: l10n.customTypeHint),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.add),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) {
      setState(() => _type = MeasurementTypes.custom(name));
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final length = ref.read(unitsProvider).length;
    final text = _text ?? '';
    final milli = parseMeasurement(text, _type, length);
    if (milli == null) {
      setState(() => _error = l10n.errInvalidNumber);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(measurementRepositoryProvider);
    final existing = widget.existing;
    final result = existing == null
        ? await repo.add(
            type: _type,
            valueMilli: milli,
            entryUnit: length == LengthUnit.cm ? 'cm' : 'in',
            notes: _note,
          )
        : await repo.update(existing.id, valueMilli: milli, notes: _note);
    if (!mounted) return;
    if (result.isOk) {
      showFbSnackBar(context, l10n.saved);
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = result.failureOrNull?.code == 'out_of_range'
            ? l10n.errOutOfRange
            : l10n.errSaveFailed;
      });
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final agreed = await showFbConfirm(
      context,
      title: l10n.deleteEntryTitle,
      message: l10n.deleteEntryMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!agreed || !mounted) return;
    await ref.read(measurementRepositoryProvider).delete(widget.existing!.id);
    if (!mounted) return;
    showFbSnackBar(context, l10n.deleted);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final length = ref.watch(unitsProvider).length;
    final existing = widget.existing;
    final known = ref.watch(latestMeasurementsProvider).value ?? const [];
    final types = <String>{...MeasurementTypes.builtIn, for (final m in known) m.type, _type};
    final initial = existing == null
        ? ''
        : measurementValue(l10n, existing.valueMilli, existing.type, length).split(' ').first;
    final suffix = MeasurementTypes.isPercent(_type)
        ? l10n.unitPercent
        : (length == LengthUnit.cm ? l10n.unitCm : l10n.unitIn);

    return FbSheetBody(
      title: existing == null ? l10n.addMeasurementTitle : measurementName(l10n, existing.type),
      trailing: existing == null
          ? null
          : TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: context.colors.error),
              child: Text(l10n.delete),
            ),
      children: [
        if (existing == null) ...[
          Text(l10n.measurementType, style: context.text.label),
          const SizedBox(height: FbSpace.sm),
          Wrap(
            spacing: FbSpace.sm,
            runSpacing: FbSpace.sm,
            children: [
              for (final t in types)
                FbToggleChip(
                  label: measurementName(l10n, t),
                  selected: t == _type,
                  onTap: () => setState(() => _type = t),
                ),
              ActionChip(
                avatar: const Icon(Icons.add_rounded),
                label: Text(l10n.mYourOwn),
                onPressed: _addCustom,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
          const SizedBox(height: FbSpace.lg),
        ],
        FbTextField(
          label: l10n.valueLabel,
          value: _text ?? initial,
          suffix: suffix,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: FbTextField.decimal,
          errorText: _error,
          onChanged: (v) => setState(() => _text = v),
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
        const SizedBox(height: FbSpace.xl),
        FbPrimaryButton(
          label: l10n.save,
          busy: _busy,
          onPressed: () {
            _text ??= initial;
            _save();
          },
        ),
      ],
    );
  }
}
